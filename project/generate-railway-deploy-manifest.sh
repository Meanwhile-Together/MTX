#!/usr/bin/env bash
# Pack project-bridge workspace packages to .tgz, write package.deploy.json + package-lock.deploy.json
# so Railway can run: npm install --omit=dev --ignore-scripts (no rsynced node_modules).
# Run from prepare-railway-artifact after org-build-server (project-bridge must be built).
#
# Usage: generate-railway-deploy-manifest.sh [deploy-root]
desc="Write package.deploy.json and package-lock.deploy.json for Railway npm install"
nobanner=1
set -euo pipefail

if [ -n "${1:-}" ]; then
  ROOT="$(cd "$1" && pwd)"
else
  ROOT="$(pwd)"
fi

PB="${PROJECT_BRIDGE_ROOT:-$ROOT/../project-bridge}"

if [ ! -f "$PB/package.json" ]; then
  echo "generate-railway-deploy-manifest: project-bridge not found at $PB" >&2
  exit 1
fi
if [ ! -f "$PB/targets/server/package.json" ]; then
  echo "generate-railway-deploy-manifest: missing $PB/targets/server/package.json" >&2
  exit 1
fi

PACK_DIR="$ROOT/targets/server/npm-packs"
mkdir -p "$PACK_DIR"
rm -f "$PACK_DIR"/*.tgz

echo "==> generate-railway-deploy-manifest: npm pack workspaces -> $PACK_DIR"
(
  cd "$PB"
  for ws in @meanwhile-together/shared @meanwhile-together/engine @meanwhile-together/ui @meanwhile-together/demo; do
    npm pack -w "$ws" --pack-destination "$PACK_DIR"
  done
)

unset MTX_ADMIN_FILE_SPEC MTX_ADMIN_PKG_NAME
ADMIN_ROOT=""
for cand in "$ROOT/../payload-admin" "$PB/../payload-admin"; do
  if [ -f "$cand/package.json" ]; then
    ADMIN_ROOT="$(cd "$cand" && pwd)"
    break
  fi
done
if [ -n "$ADMIN_ROOT" ]; then
  echo "==> generate-railway-deploy-manifest: npm pack payload-admin -> $PACK_DIR"
  MTX_ADMIN_PKG_NAME="$(jq -r '.name // "@meanwhile-together/admin"' "$ADMIN_ROOT/package.json")"
  ADM_TGZ="$(cd "$ADMIN_ROOT" && npm pack --pack-destination "$PACK_DIR" | tail -1 | tr -d '\r')"
  MTX_ADMIN_FILE_SPEC="file:targets/server/npm-packs/${ADM_TGZ}"
  export MTX_ADMIN_FILE_SPEC
  export MTX_ADMIN_PKG_NAME
  echo "    $MTX_ADMIN_PKG_NAME -> $MTX_ADMIN_FILE_SPEC"
else
  echo "==> generate-railway-deploy-manifest: no sibling payload-admin (expected ../payload-admin); skipping admin pack" >&2
fi

export ROOT
export PB
export PACK_DIR
node <<'NODE'
const fs = require('fs');
const path = require('path');
const root = process.env.ROOT;
const pb = process.env.PB;
const packDir = process.env.PACK_DIR;
const serverPkg = JSON.parse(fs.readFileSync(path.join(pb, 'targets/server/package.json'), 'utf8'));

function fileSpecForWorkspace(name) {
  const short = name.replace('@meanwhile-together/', '');
  const files = fs.readdirSync(packDir).filter((f) => f.endsWith('.tgz'));
  const re = new RegExp('^meanwhile-together-' + short.replace(/[^a-z0-9-]/gi, '') + '-');
  const hit = files.find((f) => re.test(f));
  if (!hit) {
    throw new Error(`No .tgz found in ${packDir} for ${name} (expected meanwhile-together-${short}-*.tgz)`);
  }
  const rel = path.join('targets/server/npm-packs', hit).split(path.sep).join('/');
  return 'file:' + rel;
}

const dependencies = {};
const overrides = {};

for (const [dep, spec] of Object.entries(serverPkg.dependencies || {})) {
  if (spec === '*') {
    const fileSpec = fileSpecForWorkspace(dep);
    dependencies[dep] = fileSpec;
    overrides[dep] = fileSpec;
  } else {
    dependencies[dep] = spec;
  }
}

if (!dependencies.prisma) {
  const prismaClientVersion = serverPkg.dependencies?.['@prisma/client'] || '^7.0.0';
  dependencies.prisma = prismaClientVersion;
}

const adminSpec = process.env.MTX_ADMIN_FILE_SPEC;
const adminName = process.env.MTX_ADMIN_PKG_NAME || '@meanwhile-together/admin';
if (adminSpec) {
  dependencies[adminName] = adminSpec;
  overrides[adminName] = adminSpec;
}

const manifest = {
  name: '@meanwhile-together/org-railway-runtime',
  version: '1.0.0',
  private: true,
  description: 'Generated for Railway npm install; workspace packages are file: tarballs from npm pack.',
  dependencies,
  overrides,
};

const out = path.join(root, 'package.deploy.json');
fs.writeFileSync(out, JSON.stringify(manifest, null, 2) + '\n');
console.log('Wrote', out);
NODE

echo "==> generate-railway-deploy-manifest: npm install --package-lock-only (writes package-lock.deploy.json)"
PKG_BACKUP="$(mktemp)"
cp "$ROOT/package.json" "$PKG_BACKUP"
cp "$ROOT/package.deploy.json" "$ROOT/package.json"
(
  cd "$ROOT"
  npm install --package-lock-only --omit=dev --ignore-scripts
)
mv "$ROOT/package-lock.json" "$ROOT/package-lock.deploy.json"
cp "$PKG_BACKUP" "$ROOT/package.json"
rm -f "$PKG_BACKUP"

echo "==> generate-railway-deploy-manifest: done"
