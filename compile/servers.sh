#!/usr/bin/env bash
# MTX compile servers: build app server and backend server
desc="Build app server and backend server"
set -e
echo "🔨 server..."
mtx_run npm run build:server
echo "🔨 backend-server..."
mtx_run npm run build:backend-server
echo "✅ servers done"
