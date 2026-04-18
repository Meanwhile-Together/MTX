#!/usr/bin/env bash
# Self-contained scope entry: sources sibling _lib.sh (same pattern as org.sh / all.sh).
desc="Clean build artifacts for the current package only (payload scope)"
nobanner=1
set -e

_CLEAN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=clean/_lib.sh
source "$_CLEAN_DIR/_lib.sh"
unset MTX_CLEAN_ORG_ROOT MTX_CLEAN_SINGLE_ROOT MTX_CLEAN_ALL_SCAN_ROOT CLEAN_AUTO_MSG 2>/dev/null || true
MTX_CLEAN_NO_AUTO=1
MTX_CLEAN_SCOPE=payload
mtx_clean_entry "$@"
unset MTX_CLEAN_NO_AUTO MTX_CLEAN_SCOPE 2>/dev/null || true
