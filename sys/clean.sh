#!/usr/bin/env bash
# Legacy entry: same behavior as mtx clean (see clean/_lib.sh).
desc="Remove build artifacts (alias of mtx clean; smart org/payload; all uses workspace root)"
nobanner=1
set -e

_TOP="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
# shellcheck source=clean/_lib.sh
source "$_TOP/clean/_lib.sh"
unset MTX_CLEAN_NO_AUTO 2>/dev/null || true
mtx_clean_entry "$@"
