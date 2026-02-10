#!/usr/bin/env bash
# MTX dev build: run npm run build:* from repo root (client/desktop/mobile/server/all)
desc="Build client, desktop, mobile, server, or all"
set -e
TARGET="${1:-}"
if [ -z "$TARGET" ]; then
  echo "Usage: $0 <client|desktop|mobile|server|all>"
  echo "  client  - npm run build:client"
  echo "  desktop - npm run build:desktop"
  echo "  mobile  - npm run build:mobile"
  echo "  server  - npm run build:server"
  echo "  all     - npm run build"
  exit 1
fi
case "$TARGET" in
  client)  npm run build:client ;;
  desktop) npm run build:desktop ;;
  mobile)  npm run build:mobile ;;
  server)  npm run build:server ;;
  all)     npm run build ;;
  *)
    echo "Unknown target: $TARGET (use client|desktop|mobile|server|all)"
    exit 1
    ;;
esac
