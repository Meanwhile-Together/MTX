#!/usr/bin/env bash
# mtx clean — see clean/_lib.sh
desc="Remove build artifacts (auto org/payload; all uses workspace root from precond)"
nobanner=1
set -e

_LIB="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/clean"
# shellcheck source=clean/_lib.sh
source "$_LIB/_lib.sh"
unset MTX_CLEAN_NO_AUTO 2>/dev/null || true
mtx_clean_entry "$@"
