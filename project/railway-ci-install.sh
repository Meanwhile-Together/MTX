#!/usr/bin/env bash
# Railpack install: swap in package.deploy.json + lock, npm install only (no git, no build scripts).
# Requires package.deploy.json + npm-packs from mtx build / mtx project prepare-railway-artifact.
#
# Drops lockfile `integrity` for entries whose `resolved` is a local `file:…/*.tgz`. Those packs come
# from `npm pack` on the prepare machine; npm install on Railway then pins the actual bytes.
#
# Usage: railway-ci-install.sh [deploy-root]
#   Run with cwd = deploy root (e.g. Railway /app) or pass deploy root as first argument.
desc="Railpack/Railway: apply package.deploy.json and npm install (omit dev, ignore scripts)"
nobanner=1
set -euo pipefail

if [ -n "${1:-}" ]; then
  ROOT="$(cd "$1" && pwd)"
else
  ROOT="$(pwd)"
fi
cd "$ROOT"

if [ ! -f "$ROOT/package.deploy.json" ] || [ ! -f "$ROOT/package-lock.deploy.json" ]; then
  echo "railway-ci-install: missing package.deploy.json or package-lock.deploy.json" >&2
  echo "  Run locally: mtx build server  (or: mtx project prepare-railway-artifact)" >&2
  exit 1
fi

shopt -s nullglob
packs=( "$ROOT/targets/server/npm-packs"/*.tgz )
shopt -u nullglob
if [ ${#packs[@]} -eq 0 ]; then
  echo "railway-ci-install: missing targets/server/npm-packs/*.tgz" >&2
  echo "  Run: mtx build server  (or: mtx project prepare-railway-artifact)" >&2
  exit 1
fi

cp -f "$ROOT/package.deploy.json" "$ROOT/package.json"
cp -f "$ROOT/package-lock.deploy.json" "$ROOT/package-lock.json"

if ! command -v jq >/dev/null 2>&1; then
  echo "railway-ci-install: jq is required to normalize file: tarball integrity fields" >&2
  exit 1
fi

_lock="$ROOT/package-lock.json"
_tmp="$(mktemp)"
if ! jq '
  if .packages then
    .packages |= with_entries(
      .value |= if (type == "object")
          and ((.resolved // "") | startswith("file:"))
          and ((.resolved // "") | contains(".tgz"))
        then del(.integrity)
        else . end
    )
  else . end
' "$_lock" > "$_tmp"; then
  rm -f "$_tmp"
  echo "railway-ci-install: jq failed to rewrite package-lock.json" >&2
  exit 1
fi
mv "$_tmp" "$_lock"

exec npm install --omit=dev --ignore-scripts
