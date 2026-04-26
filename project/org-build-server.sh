#!/usr/bin/env bash
# Canonical org unified server build: snapshot project-bridge config/, build in PB, mirror targets/.
# Invoked with org repo root as first arg (e.g. mtx build server, prepare-railway, or scripts/org-build-server.sh).
# Single source of truth for org-*/ and template-org; do not duplicate the build body in per-repo scripts.
# See project-bridge verify:org-identity (rule-of-law): framework placeholder org.json before overlay.
set -euo pipefail

# Respect MTX_VERBOSE (from mtx build / mtx deploy); quiet noisy npm at default -v. Direct bash: no-op wrapper.
_MTX_BASE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
# shellcheck source=../includes/mtx-run.sh
[ -f "$_MTX_BASE/includes/mtx-run.sh" ] && source "$_MTX_BASE/includes/mtx-run.sh"
if [ -z "${MTX_VERBOSE+x}" ]; then
  mtx_run() { "$@"; }
fi
declare -F mtx_run &>/dev/null || mtx_run() { "$@"; }

if [ -n "${1:-}" ]; then
  ROOT="$(cd "$1" && pwd)"
else
  echo "org-build-server: org repo root required (pass \$1, e.g. from mtx build server)" >&2
  exit 1
fi
cd "$ROOT" || exit 1

# Build-time fan-out: payload-admin uses VITE_MASTER_AUTH_URL (master /auth) — a platform singleton.
# 1) Workspace <root>/.mtx.prepare.env (MASTER_AUTH_PUBLIC_URL from mtx prepare)
# 2) Org ROOT/.env (tenant-only overrides; e.g. local JWT)
mtx_org_build_find_workspace_root() {
  local walk="${1:-$ROOT}"
  while [ -n "$walk" ] && [ "$walk" != "/" ]; do
    for f in "$walk"/*.code-workspace; do
      if [ -f "$f" ]; then
        printf '%s' "$walk"
        return 0
      fi
    done
    walk="$(dirname "$walk")"
  done
  return 1
}

WS_ROOT="$(mtx_org_build_find_workspace_root "$ROOT")" || true
if [ -n "$WS_ROOT" ] && [ -f "$WS_ROOT/.mtx.prepare.env" ]; then
  set -a
  # shellcheck source=/dev/null
  source "$WS_ROOT/.mtx.prepare.env"
  set +a
fi

ENV_FILE="$ROOT/.env"
if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck source=/dev/null
  source "$ENV_FILE"
  set +a
fi
if [ -z "${VITE_MASTER_AUTH_URL:-}" ] && [ -n "${MASTER_AUTH_PUBLIC_URL:-}" ]; then
  base="${MASTER_AUTH_PUBLIC_URL%/}"
  export VITE_MASTER_AUTH_URL="${base}/auth"
fi

# Prisma: hosted builds (Railway) often have no DATABASE_URL at build time — default to postgresql.
if [ -z "${DATABASE_PROVIDER:-}" ]; then
  if [ -n "${RAILWAY_PROJECT_ID:-}${RAILWAY_SERVICE_ID:-}${RAILWAY_ENVIRONMENT:-}${CI:-}${GITHUB_ACTIONS:-}${VERCEL_ENV:-}" ]; then
    export DATABASE_PROVIDER=postgresql
  fi
fi

resolve_project_bridge() {
  if [ -n "${PROJECT_BRIDGE_ROOT:-}" ] && [ -f "${PROJECT_BRIDGE_ROOT}/package.json" ]; then
    echo "$(cd "${PROJECT_BRIDGE_ROOT}" && pwd)"
    return 0
  fi
  local cand
  # Match mtx build.sh mtx_resolve_org_project_bridge: vendor first, then sibling
  for cand in "$ROOT/vendor/project-bridge" "$ROOT/../project-bridge"; do
    if [ -f "$cand/package.json" ]; then
      echo "$(cd "$cand" && pwd)"
      return 0
    fi
  done
  return 1
}

PB="$(resolve_project_bridge)" || {
  echo "org-build-server: project-bridge not found. Expected vendor/project-bridge, ../project-bridge, or set PROJECT_BRIDGE_ROOT." >&2
  exit 1
}

echo "==> org-build-server: using project-bridge at $PB"

if [ -f "$PB/scripts/verify-framework-org-identity.sh" ]; then
  if ! PROJECT_BRIDGE_ROOT="$PB" bash "$PB/scripts/verify-framework-org-identity.sh"; then
    echo "org-build-server: FATAL: project-bridge config/org.json must be the template placeholder before overlay (see project-bridge verify:org-identity)." >&2
    exit 1
  fi
else
  echo "org-build-server: WARNING: missing $PB/scripts/verify-framework-org-identity.sh; skipping preflight identity check" >&2
fi

RESTORE_TMP="$(mktemp -d)"
SNAP="$RESTORE_TMP/pb-config-snapshot"

restore_project_bridge_config() {
  trap - EXIT INT TERM
  if [ -d "$SNAP" ]; then
    echo "==> Restoring project-bridge config/ from pre-build snapshot"
    if ! rsync -a --delete "$SNAP/" "$PB/config/"; then
      echo "org-build-server: WARNING: failed to restore project-bridge config/" >&2
    elif [ -f "$PB/scripts/verify-framework-org-identity.sh" ]; then
      if ! PROJECT_BRIDGE_ROOT="$PB" bash "$PB/scripts/verify-framework-org-identity.sh"; then
        echo "org-build-server: FATAL: post-restore org identity check failed (snapshot/restore left project-bridge in an invalid state)" >&2
        exit 1
      fi
    fi
  fi
  rm -rf "$RESTORE_TMP"
}

trap restore_project_bridge_config EXIT INT TERM

mkdir -p "$SNAP"
rsync -a "$PB/config/" "$SNAP/"

echo "==> Temporarily sync org config/ -> project-bridge (snapshot will be restored after build)"
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
  mtx_run npm install
  mtx_run npm run build:packages
  mtx_run npm run build:client
  mtx_run npm run build:server
  mtx_run npm run build:backend
)

echo "==> Mirror server + client dist into org repo (for deploy tarball)"
mkdir -p "$ROOT/targets/server/dist"
rsync -a --delete "$PB/targets/server/dist/" "$ROOT/targets/server/dist/"
mkdir -p "$ROOT/targets/client/dist"
rsync -a --delete "$PB/targets/client/dist/" "$ROOT/targets/client/dist/"

echo "==> org-build-server: done (restoring project-bridge config next)"
