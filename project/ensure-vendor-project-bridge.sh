#!/usr/bin/env bash
# Ensure vendor/project-bridge exists before npm resolves file: deps (preinstall / local dev).
# Workspace paths only — never downloads project-bridge from a remote.
#
# Usage: ensure-vendor-project-bridge.sh [deploy-root]
#   Default deploy-root: current working directory.
desc="Symlink or verify vendor/project-bridge for org-shaped deploy roots"
nobanner=1
set -euo pipefail

if [ -n "${1:-}" ]; then
  ROOT="$(cd "$1" && pwd)"
else
  ROOT="$(pwd)"
fi

mkdir -p "$ROOT/vendor"

if [ -n "${PROJECT_BRIDGE_ROOT:-}" ] && [ -f "${PROJECT_BRIDGE_ROOT}/package.json" ]; then
  if [ ! -f "$ROOT/vendor/project-bridge/package.json" ]; then
    ln -sfn "$(cd "${PROJECT_BRIDGE_ROOT}" && pwd)" "$ROOT/vendor/project-bridge"
    echo "ensure-vendor-project-bridge: linked vendor/project-bridge -> PROJECT_BRIDGE_ROOT"
  fi
  exit 0
fi

if [ -f "$ROOT/vendor/project-bridge/package.json" ]; then
  exit 0
fi

if [ -f "$ROOT/../project-bridge/package.json" ]; then
  ln -sfn "$(cd "$ROOT/../project-bridge" && pwd)" "$ROOT/vendor/project-bridge"
  echo "ensure-vendor-project-bridge: linked vendor/project-bridge -> sibling project-bridge"
  exit 0
fi

echo "ensure-vendor-project-bridge: project-bridge not found (local workspace only; no network fetch)." >&2
echo "  Development: keep project-bridge beside this repo (../project-bridge) or set PROJECT_BRIDGE_ROOT." >&2
echo "  Before deploy / remote build: run from this deploy root:  mtx build server  (or npm run prepare:railway)" >&2
if [ -n "${RAILWAY_ENVIRONMENT:-}" ] || [ -n "${RAILWAY:-}" ] || [ -n "${CI:-}" ]; then
  echo "" >&2
  echo "  Remote Railway build: run locally from this repo, then upload:" >&2
  echo "    mtx build server" >&2
  echo "    railway up" >&2
fi
exit 1
