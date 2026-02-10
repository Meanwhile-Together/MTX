#!/usr/bin/env bash
# Precondition: project is a Project B app (has config/app.json with app.owner and app.slug).
# If not, can prompt to create one (stubbed). Log your own error and exit non-zero on failure.
set -e

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
    echo "📦 $owner / $slug" >&2
    exit 0
  fi
fi

# Empty or not a Project B folder
echo "⚠️ Not a Project B app (missing or empty $app_json app.owner/app.slug)." >&2
read -rp "Make a new project? (y/N): " answer
if [[ "$answer" =~ ^[Yy]$ ]]; then
  echo "wheeee" >&2
  # TODO: run project creation flow
  exit 0
fi
echo "❌ precondition failed: run mtx from a Project B app or create one." >&2
exit 1
