#!/usr/bin/env bash
# mtx cursor <subcommand> — tools for Cursor IDE project data (chats, etc).
desc="Cursor IDE helpers (chat export, project inspection)"
nobanner=1
set -e

MTX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
declare -F warn >/dev/null || warn() { echo "[WARN] $*" >&2; }

case "${1:-}" in
  export)
    shift
    # shellcheck source=cursor/export.sh
    source "$MTX_ROOT/cursor/export.sh" "$@"
    return 0 2>/dev/null || exit 0
    ;;
  "")
    echo "mtx cursor <subcommand>"
    echo
    echo "Subcommands:"
    echo "  export   Export agent chat transcripts as JSON (interactive by default)"
    echo
    echo "Try: mtx cursor export --help"
    return 0 2>/dev/null || exit 0
    ;;
  *)
    warn "unknown mtx cursor subcommand: $1"
    echo "Known: export"
    return 1 2>/dev/null || exit 1
    ;;
esac
