#!/usr/bin/env bash
# MTX compile servers: build app server and backend server
desc="Build app server and backend server"
set -e
echo "🔨 server..." >&2
mtx_run npm run build:server
echo "🔨 backend-server..." >&2
mtx_run npm run build:backend-server
echo "✅ servers done" >&2
