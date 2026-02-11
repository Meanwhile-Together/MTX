#!/usr/bin/env bash
# Precondition: project is a Project B app (has config/app.json with app.owner and app.slug).
# When found, set MTX_IS_PROJECTB=1 and print framework identity. Always passes.
set -e

MTX_IS_PROJECTB=""
app_json="config/app.json"
if [ -f "$app_json" ]; then
  if command -v jq &>/dev/null; then
    owner=$(jq -r '.app.owner // ""' "$app_json" 2>/dev/null || echo "")
    slug=$(jq -r '.app.slug // ""' "$app_json" 2>/dev/null || echo "")
  else
    owner=$(grep -o '"owner"[[:space:]]*:[[:space:]]*"[^"]*"' "$app_json" 2>/dev/null | sed 's/.*"\([^"]*\)"$/\1/' || echo "")
    slug=$(grep -o '"slug"[[:space:]]*:[[:space:]]*"[^"]*"' "$app_json" 2>/dev/null | head -1 | sed 's/.*"\([^"]*\)"$/\1/' || echo "")
  fi
  if [ -n "$owner" ] && [ -n "$slug" ]; then
    MTX_IS_PROJECTB=1
    export MTX_IS_PROJECTB
    echo "📦 framework: $owner / $slug" >&2
  fi
fi
true

