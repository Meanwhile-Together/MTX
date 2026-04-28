#!/usr/bin/env bash
# npm lifecycle: skip when SKIP_VENDOR_PREINSTALL=1 (e.g. Railway npm install --ignore-scripts still skips preinstall in some flows).
# Delegates to ensure-vendor-project-bridge.sh.
#
# Usage: ensure-vendor-preinstall.sh [deploy-root]
desc="npm preinstall: ensure vendor/project-bridge (SKIP_VENDOR_PREINSTALL=1 to no-op)"
nobanner=1
set -euo pipefail

if [ "${SKIP_VENDOR_PREINSTALL:-}" = "1" ]; then
  exit 0
fi

_script="${BASH_SOURCE[0]:-$0}"
MTX_ROOT="$(cd "$(dirname "$_script")/.." && pwd)"

if [ -n "${1:-}" ]; then
  ROOT="$(cd "$1" && pwd)"
else
  ROOT="$(pwd)"
fi

bash "$MTX_ROOT/project/ensure-vendor-project-bridge.sh" "$ROOT"
