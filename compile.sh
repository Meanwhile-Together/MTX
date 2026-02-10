#!/usr/bin/env bash
# MTX compile: build targets — use mtx compile <target> (no arguments here; see compile/*.sh)
desc="Build targets; use mtx compile <client|desktop|mobile|server|all|android-debug>"
set -e

echo "Usage: mtx compile <client|desktop|mobile|server|all|android-debug>"
echo "  client        - npm run build:client"
echo "  desktop       - npm run build:desktop"
echo "  mobile        - npm run build:mobile"
echo "  server        - npm run build:server"
echo "  all           - npm run build"
echo "  android-debug - Build Android debug APK"
