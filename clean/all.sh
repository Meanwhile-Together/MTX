#!/usr/bin/env bash
# Self-contained scope entry: sources sibling _lib.sh; 'all' uses MTX_WORKSPACE_ROOT when set.
desc="Clean every package.json tree under workspace root (all scope)"
nobanner=1
set -e

_CLEAN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=clean/_lib.sh
source "$_CLEAN_DIR/_lib.sh"
unset MTX_CLEAN_ORG_ROOT MTX_CLEAN_SINGLE_ROOT MTX_CLEAN_ALL_SCAN_ROOT CLEAN_AUTO_MSG 2>/dev/null || true
MTX_CLEAN_NO_AUTO=1
MTX_CLEAN_SCOPE=all
mtx_clean_entry "$@"
unset MTX_CLEAN_NO_AUTO MTX_CLEAN_SCOPE 2>/dev/null || true
