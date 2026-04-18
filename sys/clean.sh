#!/usr/bin/env bash
# Deprecated: use mtx clean (see clean/_lib.sh). Kept for backward compatibility.
desc="Deprecated — use mtx clean (same behavior; smart org/payload; all uses workspace root)"
nobanner=1
set -e

echo "mtx sys clean is deprecated; use mtx clean instead. This alias will be removed in a future MTX version." >&2

_TOP="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
# shellcheck source=clean/_lib.sh
source "$_TOP/clean/_lib.sh"
unset MTX_CLEAN_NO_AUTO 2>/dev/null || true
mtx_clean_entry "$@"
