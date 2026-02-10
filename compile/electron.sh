#!/usr/bin/env bash
# MTX compile electron: build desktop app
desc="Build desktop app (Electron)"
set -e
echo "🔨 desktop (Electron)..."
mtx_run npm run build:desktop
echo "✅ electron done"
