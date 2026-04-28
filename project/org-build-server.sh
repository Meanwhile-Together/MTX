#!/usr/bin/env bash
# Build packages + Vite client + unified server in project-bridge with a deploy root's config/,
# then mirror targets/server/dist and targets/client/dist into that deploy root.
# project-bridge's config/ is snapshotted before sync and restored on exit (success or failure).
#
# Usage: org-build-server.sh [deploy-root]
#   deploy-root — directory with config/app.json (default: current working directory)
desc="Build unified server in project-bridge and mirror dist into deploy root"
nobanner=1
set -euo pipefail

if [ -n "${1:-}" ]; then
  ROOT="$(cd "$1" && pwd)"
else
  ROOT="$(pwd)"
fi

resolve_project_bridge() {
  if [ -n "${PROJECT_BRIDGE_ROOT:-}" ] && [ -f "${PROJECT_BRIDGE_ROOT}/package.json" ]; then
    echo "$(cd "${PROJECT_BRIDGE_ROOT}" && pwd)"
    return 0
  fi
  local cand
  for cand in "$ROOT/../project-bridge" "$ROOT/vendor/project-bridge"; do
    if [ -f "$cand/package.json" ]; then
      echo "$(cd "$cand" && pwd)"
      return 0
    fi
  done
  return 1
}

PB="$(resolve_project_bridge)" || {
  echo "org-build-server: project-bridge not found. Expected vendor/project-bridge, sibling ../project-bridge, or set PROJECT_BRIDGE_ROOT." >&2
  exit 1
}

echo "==> org-build-server: using project-bridge at $PB"

RESTORE_TMP="$(mktemp -d)"
SNAP="$RESTORE_TMP/pb-config-snapshot"

restore_project_bridge_config() {
  trap - EXIT INT TERM
  if [ -d "$SNAP" ]; then
    echo "==> Restoring project-bridge config/ from pre-build snapshot"
    rsync -a --delete "$SNAP/" "$PB/config/" || echo "org-build-server: WARNING: failed to restore project-bridge config/" >&2
  fi
  rm -rf "$RESTORE_TMP"
}

trap restore_project_bridge_config EXIT INT TERM

mkdir -p "$SNAP"
rsync -a "$PB/config/" "$SNAP/"

echo "==> Temporarily sync deploy config/ -> project-bridge (snapshot will be restored after build)"
rsync -a --delete \
  --exclude 'server.json' \
  --exclude 'server.json.railway' \
  "$ROOT/config/" "$PB/config/"
if [ -f "$ROOT/config/server.json.railway" ]; then
  cp -a "$ROOT/config/server.json.railway" "$PB/config/server.json"
else
  cp -a "$ROOT/config/server.json" "$PB/config/server.json"
fi

echo "==> Install dependencies + build packages, web client, and server (project-bridge)"
(
  cd "$PB"
  npm install
  npm run build:packages
  npm run build:client
  need_admin=false
  for f in "$ROOT/config/server.json" "$ROOT/config/server.json.railway"; do
    if [ -f "$f" ] && grep -q '"slug"[[:space:]]*:[[:space:]]*"admin"' "$f"; then
      need_admin=true
      break
    fi
  done
  if [ "$need_admin" = true ]; then
    echo "==> org-build-server: server config lists admin → npm run build:backend (payload-admin)"
    npm run build:backend
  fi
  DATABASE_PROVIDER=postgresql npm run build:server
)

echo "==> Mirror server + client dist into deploy root (for deploy tarball)"
mkdir -p "$ROOT/targets/server/dist"
rsync -a --delete "$PB/targets/server/dist/" "$ROOT/targets/server/dist/"
mkdir -p "$ROOT/targets/client/dist"
rsync -a --delete "$PB/targets/client/dist/" "$ROOT/targets/client/dist/"

echo "==> org-build-server: done (restoring project-bridge config next)"
