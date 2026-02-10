#!/usr/bin/env bash
# MTX run dev: run the project's main dev script (server + prisma watch etc.)
desc="Run main dev (server, prisma watch)"
set -e
echo "▶️ main dev (server + prisma watch)..." >&2
mtx_run npm run dev
