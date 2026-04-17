#!/usr/bin/env bash
# MTX deploy manual: same as mtx deploy (interactive menu)
desc="Same as mtx deploy (interactive menu)"
set -e
MTX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
"$MTX_ROOT/deploy.sh" "$@"
