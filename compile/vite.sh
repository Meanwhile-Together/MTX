#!/usr/bin/env bash
# MTX compile vite: build all Vite-based targets (client, desktop renderer, backend, mobile)
desc="Build all Vite-based targets (client, desktop, backend, mobile)"
set -e
echo "🔨 client..."
mtx_run npm run build:client
echo "🔨 desktop..."
mtx_run npm run build:desktop
echo "🔨 backend..."
mtx_run npm run build:backend
echo "🔨 mobile..."
mtx_run npm run build:mobile
echo "✅ vite done"
