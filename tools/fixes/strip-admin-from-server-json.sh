#!/usr/bin/env bash
# Remove legacy admin entries from config/server.json apps[] (payload-admin, admin-org-*, admin-platform-*).
# Usage: bash strip-admin-from-server-json.sh [org-root]   (default: cwd)
desc="Strip admin SPA entries from config/server.json apps[]"
set -euo pipefail
ROOT="${1:-$(pwd)}"
CFG="$ROOT/config/server.json"
[ -f "$CFG" ] || { echo "No $CFG" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq required" >&2; exit 1; }
tmp="$(mktemp)"
jq '
  (if (.apps | type) == "array" then .apps else [] end) as $apps
  | .apps = (
      $apps
      | map(select(
          ((.id // "") | test("^(payload-admin|admin-org-|admin-platform-)")) | not
        ))
    )
' "$CFG" >"$tmp"
mv "$tmp" "$CFG"
echo "✅ Stripped admin entries from $CFG"
