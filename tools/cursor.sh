#!/usr/bin/env bash
# mtx tools cursor <subcommand> — tools for Cursor IDE project data (chats, etc).
desc="Cursor IDE helpers (chat export, project inspection)"
nobanner=1
set -e

MTX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
declare -F warn >/dev/null || warn() { echo "[WARN] $*" >&2; }

case "${1:-}" in
  export)
    shift
    # shellcheck source=cursor/export.sh
    source "$MTX_ROOT/tools/cursor/export.sh" "$@"
    return 0 2>/dev/null || exit 0
    ;;
  "")
    echo "mtx tools cursor <subcommand>"
    echo
    echo "Subcommands:"
    echo "  export   Export agent chat transcripts as JSON (interactive by default)"
    echo
    echo "Try: mtx tools cursor export --help"
    return 0 2>/dev/null || exit 0
    ;;
  *)
    warn "unknown mtx tools cursor subcommand: $1"
    echo "Known: export"
    return 1 2>/dev/null || exit 1
    ;;
esac
