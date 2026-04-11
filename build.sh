#!/usr/bin/env bash
# Build unified server artifacts for the project root (tree with config/app.json).
# Same npm steps as mtx deploy uses before railway up; does not provision infra or upload.
# Org repos (scripts/org-build-server.sh): before build:server, primes resolved project-bridge with
# npm install and npm run db:generate (matches org-build-server expectations).
# Usage: mtx build [server|backend|all]   (default: all)
desc="Build server artifacts (no deploy); optional: server, backend, or all"
nobanner=1
set -e

MTX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

# Match terraform/apply.sh PROJECT_ROOT resolution
PROJECT_ROOT=""
if [ -f "config/app.json" ]; then
  PROJECT_ROOT="$(pwd)"
fi
if [ -z "$PROJECT_ROOT" ] && [ -f "../config/app.json" ]; then
  PROJECT_ROOT="$(cd .. && pwd)"
fi
if [ -z "$PROJECT_ROOT" ]; then
  for d in . .. ../project-bridge; do
    [ -f "${d}/config/app.json" ] && PROJECT_ROOT="$(cd "$d" && pwd)" && break
  done
fi
[ -z "$PROJECT_ROOT" ] && PROJECT_ROOT="$(pwd)"
cd "$PROJECT_ROOT" || exit 1

TARGET="${1:-all}"
case "$TARGET" in
  server|app|s) TARGET=server ;;
  backend|b) TARGET=backend ;;
  all|a|'') TARGET=all ;;
  -h|--help|help)
    echo "Usage: mtx build [server|backend|all]"
    echo "  server   — npm run build:server (app / unified server)"
    echo "  backend  — npm run build:backend-server"
    echo "  all      — both (default; org repos run one unified build if backend aliases to server)"
    echo "  Org repos: project-bridge is primed with npm install + db:generate first (sibling, vendor/, or PROJECT_BRIDGE_ROOT)."
    exit 0
    ;;
  *)
    echo "Unknown target: $TARGET" >&2
    echo "Usage: mtx build [server|backend|all]" >&2
    exit 1
    ;;
esac

# Same resolution order as template org scripts/org-build-server.sh
mtx_resolve_org_project_bridge() {
  local root="$1"
  if [ -n "${PROJECT_BRIDGE_ROOT:-}" ] && [ -f "${PROJECT_BRIDGE_ROOT}/package.json" ]; then
    echo "$(cd "${PROJECT_BRIDGE_ROOT}" && pwd)"
    return 0
  fi
  local cand
  for cand in "$root/vendor/project-bridge" "$root/../project-bridge"; do
    if [ -f "$cand/package.json" ]; then
      echo "$(cd "$cand" && pwd)"
      return 0
    fi
  done
  return 1
}

mtx_prime_org_project_bridge_if_needed() {
  [ -f "$PROJECT_ROOT/scripts/org-build-server.sh" ] || return 0
  case "$TARGET" in server|backend|all) ;; *) return 0 ;; esac
  local pb
  if ! pb="$(mtx_resolve_org_project_bridge "$PROJECT_ROOT")"; then
    echo "❌ mtx build (org): project-bridge not found. Expected ../project-bridge, vendor/project-bridge, or PROJECT_BRIDGE_ROOT." >&2
    exit 1
  fi
  echo "ℹ️  Org repo: priming project-bridge at $pb (npm install, db:generate)..." >&2
  (cd "$pb" && npm install && npm run db:generate) || {
    echo "❌ project-bridge prime failed (npm install / db:generate)" >&2
    exit 1
  }
}

ensure_npm_deps() {
  if [ ! -f "node_modules/.bin/prisma" ] && [ -f "package.json" ]; then
    echo "ℹ️  Dependencies missing, running npm install..." >&2
    npm install || { echo "❌ npm install failed" >&2; exit 1; }
  fi
}

run_server_build() {
  echo "🔨 Building app server (npm run build:server)..." >&2
  ensure_npm_deps
  npm run build:server || { echo "❌ build:server failed" >&2; exit 1; }
  echo "✅ build:server complete" >&2
}

run_backend_build() {
  echo "🔨 Building backend server (npm run build:backend-server)..." >&2
  ensure_npm_deps
  npm run build:backend-server || { echo "❌ build:backend-server failed" >&2; exit 1; }
  echo "✅ build:backend-server complete" >&2
}

mtx_prime_org_project_bridge_if_needed

case "$TARGET" in
  server) run_server_build ;;
  backend) run_backend_build ;;
  all)
    run_server_build
    # org template aliases build:backend-server to build:server — avoid duplicate work
    if [ ! -f "$PROJECT_ROOT/scripts/org-build-server.sh" ]; then
      run_backend_build
    fi
    ;;
esac
