#!/usr/bin/env bash
# MTX create: interactive menu — new app name, then list deduplicated owners from all repos in workspace
desc="Interactive create: new app name, then list owners from all workspace repos"
nobanner=1
set -e

# Resolve workspace root: one level up from current dir (project root when mtx runs)
WORKSPACE_ROOT="$(cd .. && pwd)"

# Collect owner from config/app.json (jq or fallback)
get_owner() {
  local app_json="$1"
  if command -v jq &>/dev/null && [ -f "$app_json" ]; then
    jq -r '.app.owner // ""' "$app_json" 2>/dev/null || true
  else
    grep -o '"owner"[[:space:]]*:[[:space:]]*"[^"]*"' "$app_json" 2>/dev/null | sed 's/.*"\([^"]*\)"$/\1/' || true
  fi
}

# 1) Ask for new app name
echoc cyan "Create new app"
echo ""
read -rp "$(echo -e "${bold:-}New app name:${reset:-} ")" NEW_APP_NAME
NEW_APP_NAME="${NEW_APP_NAME#"${NEW_APP_NAME%%[![:space:]]*}"}"
NEW_APP_NAME="${NEW_APP_NAME%"${NEW_APP_NAME##*[![:space:]]}"}"
if [ -z "$NEW_APP_NAME" ]; then
  warn "No app name entered. Exiting."
  exit 0
fi

# 2) Iterate workspace repos and collect deduplicated owners
echoc cyan "Workspace: $WORKSPACE_ROOT"
echoc dim "Scanning repos for config/app.json..."
echo ""

OWNERS_FILE=""
if command -v mktemp &>/dev/null; then
  OWNERS_FILE=$(mktemp)
else
  OWNERS_FILE="/tmp/mtx_create_owners_$$"
  : > "$OWNERS_FILE"
fi
trap 'rm -f "$OWNERS_FILE"' EXIT

for repo_dir in "$WORKSPACE_ROOT"/*/; do
  [ -d "$repo_dir" ] || continue
  app_json="${repo_dir}config/app.json"
  if [ -f "$app_json" ]; then
    owner=$(get_owner "$app_json")
    [ -n "$owner" ] && echo "$owner" >> "$OWNERS_FILE"
  fi
done

# Deduplicate and show
if [ -s "$OWNERS_FILE" ]; then
  echoc green "Owners from workspace repos (deduplicated):"
  sort -u "$OWNERS_FILE" | while read -r o; do
    echo "  - $o"
  done
else
  warn "No config/app.json found in any repo under $WORKSPACE_ROOT"
fi

echo ""
echoc dim "New app name: $(color yellow "$NEW_APP_NAME")"
echo ""
