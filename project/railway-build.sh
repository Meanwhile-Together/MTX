#!/usr/bin/env bash
# Railway build: nothing to compile when prepare bundle was produced locally/CI (artifact deploy is default).
#
# Usage: railway-build.sh [deploy-root]
desc="Railway build gate: verify self-contained dist is present"
nobanner=1
set -euo pipefail

if [ -n "${1:-}" ]; then
  ROOT="$(cd "$1" && pwd)"
else
  ROOT="$(pwd)"
fi

if [ ! -f "$ROOT/targets/client/dist/index.html" ]; then
  echo "railway-build: missing targets/client/dist/index.html (Vite client not in deploy bundle)." >&2
  echo "  Run: mtx build server  (org-build-server runs build:client and mirrors targets/client/dist)." >&2
  exit 1
fi

if [ ! -f "$ROOT/targets/server/dist/db/app-client.js" ]; then
  echo "railway-build: missing targets/server/dist/db/app-client.js (Prisma app client not in deploy bundle)." >&2
  echo "  Run: mtx build server  from a machine with project-bridge (runs db:generate + build:server)." >&2
  exit 1
fi

if [ -f "$ROOT/.railway-self-contained" ] && [ -f "$ROOT/targets/server/dist/index.js" ] && [ -d "$ROOT/node_modules" ]; then
  echo "==> railway-build: self-contained bundle present — skipping server build"
  exit 0
fi

echo "railway-build: self-contained artifact missing." >&2
echo "  On a machine with project-bridge beside this repo, run:  mtx build server" >&2
echo "  Then deploy so Railway receives targets/server/dist, targets/client/dist, npm-packs, and deploy manifests." >&2
exit 1
