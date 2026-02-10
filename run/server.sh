#!/usr/bin/env bash
# MTX run server: run backend server in dev (with prisma watch)
desc="Run backend server in dev"
set -e
echo "▶️ dev server..." >&2
mtx_run npm run dev:server
