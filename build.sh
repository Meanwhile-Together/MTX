#!/usr/bin/env bash
# Build unified server artifacts for the project root (tree with config/app.json).
# Same npm steps as mtx deploy uses before railway up; does not provision infra or upload.
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
    echo "  all      — both (default)"
    exit 0
    ;;
  *)
    echo "Unknown target: $TARGET" >&2
    echo "Usage: mtx build [server|backend|all]" >&2
    exit 1
    ;;
esac

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

case "$TARGET" in
  server) run_server_build ;;
  backend) run_backend_build ;;
  all)
    run_server_build
    run_backend_build
    ;;
esac
