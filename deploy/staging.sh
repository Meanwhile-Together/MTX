#!/usr/bin/env bash
# MTX deploy staging: shortcut → mtx deploy manual staging
desc="Deploy to staging"
set -e
MTX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
"$MTX_ROOT/deploy.sh" staging
