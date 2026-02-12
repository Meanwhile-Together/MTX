#!/usr/bin/env bash
# MTX compile vite: build all Vite-based targets (client, desktop renderer, backend, mobile)
desc="Build all Vite-based targets (client, desktop, backend, mobile)"
set -e
echo "🔨 client..." >&2
mtx_run npm run build:client
echo "🔨 desktop..." >&2
mtx_run npm run build:desktop
echo "🔨 backend..." >&2
mtx_run npm run build:backend
echo "🔨 mobile..." >&2
mtx_run npm run build:mobile
echo "✅ vite done" >&2