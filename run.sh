#!/usr/bin/env bash
# MTX run: single dispatcher for runtime/dev commands
desc="Run targets (dev|desktop|android|web|server|electron)"
set -e

target="${1:-}"

run_npm_script() {
  local script="$1"
  if [ -f "project-bridge/package.json" ]; then
    mtx_run npm --prefix project-bridge run "$script"
  elif [ -f "package.json" ]; then
    mtx_run npm run "$script"
  else
    echo "❌ Could not find project-bridge/package.json or local package.json" >&2
    exit 1
  fi
}

case "$target" in
  dev)
    echo "▶️ main dev (project-bridge)..." >&2
    run_npm_script "dev"
    ;;
  desktop)
    echo "▶️ desktop dev..." >&2
    run_npm_script "dev:desktop"
    ;;
  electron)
    echo "▶️ electron alias -> desktop..." >&2
    run_npm_script "dev:desktop"
    ;;
  android)
    echo "▶️ android target..." >&2
    run_npm_script "mobile:android"
    ;;
  web)
    echo "▶️ web dev..." >&2
    run_npm_script "dev:client"
    ;;
  server)
    echo "▶️ dev server..." >&2
    run_npm_script "dev:server"
    ;;
  *)
    echo "Usage: mtx run <dev|desktop|android|web|server|electron>" >&2
    echo "Example: mtx run web" >&2
    exit 1
    ;;
esac
