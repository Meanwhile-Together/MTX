#!/usr/bin/env bash
# MTX deploy production: shortcut → mtx deploy manual production
desc="Deploy to production"
set -e
MTX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
"$MTX_ROOT/deploy.sh" production
