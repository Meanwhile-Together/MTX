#!/usr/bin/env bash
# MTX compile: run npm run build:* (client/desktop/mobile/server/all) or use mtx compile android-debug
desc="Build client, desktop, mobile, server, or all; or mtx compile android-debug"
set -e

TARGET="${1:-}"
if [ -z "$TARGET" ]; then
  echo "Usage: mtx compile <client|desktop|mobile|server|all|android-debug>"
  echo "  client        - npm run build:client"
  echo "  desktop       - npm run build:desktop"
  echo "  mobile        - npm run build:mobile"
  echo "  server        - npm run build:server"
  echo "  all           - npm run build"
  echo "  android-debug - Build Android debug APK"
  exit 1
fi
case "$TARGET" in
  client)        npm run build:client ;;
  desktop)       npm run build:desktop ;;
  mobile)        npm run build:mobile ;;
  server)        npm run build:server ;;
  all)           npm run build ;;
  android-debug) npm run build:android:debug ;;
  *)
    echo "Unknown target: $TARGET (use client|desktop|mobile|server|all|android-debug)"
    exit 1
    ;;
esac
