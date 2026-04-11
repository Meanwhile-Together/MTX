#!/usr/bin/env bash
# MTX compile servers: delegate to mtx build (shared with deploy)
desc="Build app server and backend server (see mtx build)"
set -e
MTX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
echo "🔨 servers (mtx build all)..." >&2
bash "$MTX_ROOT/build.sh" all
echo "✅ servers done" >&2
