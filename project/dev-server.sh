#!/usr/bin/env bash
# Run project-bridge's unified dev server with a deploy root's config/ (sync + restore on exit).
#
# Usage: dev-server.sh [deploy-root]
desc="Run project-bridge dev with deploy root config synced"
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
  echo "dev-server: project-bridge not found. Expected vendor/project-bridge, sibling ../project-bridge, or set PROJECT_BRIDGE_ROOT." >&2
  exit 1
}

echo "==> dev-server: using project-bridge at $PB"

RESTORE_TMP="$(mktemp -d)"
SNAP="$RESTORE_TMP/pb-config-snapshot"

restore_project_bridge_config() {
  trap - EXIT INT TERM
  if [ -d "$SNAP" ]; then
    echo "==> Restoring project-bridge config/ from pre-dev snapshot"
    rsync -a --delete "$SNAP/" "$PB/config/" || echo "dev-server: WARNING: failed to restore project-bridge config/" >&2
  fi
  rm -rf "$RESTORE_TMP"
}

trap restore_project_bridge_config EXIT INT TERM

mkdir -p "$SNAP"
rsync -a "$PB/config/" "$SNAP/"

echo "==> Sync deploy config/ -> project-bridge (restored when dev exits)"
rsync -a --delete "$ROOT/config/" "$PB/config/"

_script="${BASH_SOURCE[0]:-$0}"
MTX_ROOT="$(cd "$(dirname "$_script")/.." && pwd)"
export MTX_ROOT

if [ -f "${MTX_ROOT}/includes/mtx-predeploy.sh" ]; then
  # shellcheck disable=SC1091
  source "${MTX_ROOT}/includes/mtx-predeploy.sh"
  mtx_predeploy_normalize_source_paths_from_server_json "$ROOT" || echo "dev-server: WARNING: payload path normalize failed" >&2
else
  for _mtx_cand in "$ROOT/../MTX" "$ROOT/../../MTX"; do
    if [ -f "$_mtx_cand/includes/mtx-predeploy.sh" ]; then
      # shellcheck disable=SC1091
      source "$_mtx_cand/includes/mtx-predeploy.sh"
      mtx_predeploy_normalize_source_paths_from_server_json "$ROOT" || echo "dev-server: WARNING: payload path normalize failed" >&2
      break
    fi
  done
fi

if [ ! -d "$PB/node_modules" ]; then
  echo "==> npm install (project-bridge)"
  (cd "$PB" && npm install)
fi

echo "==> Starting project-bridge dev (Ctrl+C stops server and restores project-bridge config)"
cd "$PB" || exit 1
npm run dev
