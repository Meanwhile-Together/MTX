#!/usr/bin/env bash
# MTX compile: build targets — use mtx compile <target> (no arguments here; see compile/*.sh)
desc="Build targets; use mtx compile <vite|electron|android|ios|servers|all>"
set -e

echo "Usage: mtx compile <vite|electron|android|ios|servers|all>"
echo "  vite     - Build web client (Vite)"
echo "  electron - Build desktop app (Electron)"
echo "  android  - Build Android debug APK"
echo "  ios      - Build iOS app"
echo "  servers  - Build app server and backend server"
echo "  all      - Build all targets"
