#!/usr/bin/env bash
# MTX create: new app from project-bridge — pick/enter owner, clone from GitHub, rebrand, create repo, push
desc="Create new app: clone project-bridge from GitHub, rebrand, create repo in Meanwhile-Together and push"
nobanner=1
set -e

# Use workspace from precond 02 when set (dir containing .code-workspace), else parent of cwd
WORKSPACE_ROOT="${MTX_WORKSPACE_ROOT:-$(cd .. && pwd)}"
GITHUB_ORG="${MTX_GITHUB_ORG:-Meanwhile-Together}"
TEMPLATE_REPO="project-bridge"
TEMPLATE_URL="https://github.com/${GITHUB_ORG}/${TEMPLATE_REPO}.git"

# Collect owner from config/app.json (jq or fallback)
get_owner() {
  local app_json="$1"
  if command -v jq &>/dev/null && [ -f "$app_json" ]; then
    jq -r '.app.owner // ""' "$app_json" 2>/dev/null || true
  else
    grep -o '"owner"[[:space:]]*:[[:space:]]*"[^"]*"' "$app_json" 2>/dev/null | sed 's/.*"\([^"]*\)"$/\1/' || true
  fi
}

# Slugify: lower case, non-alphanumeric → hyphen, trim hyphens
slugify() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/^-*\|-*$//g'
}

# --- 1) App name ---
echoc cyan "Create new app"
echo ""
read -rp "$(echo -e "${bold:-}New app name:${reset:-} ")" NEW_APP_NAME
NEW_APP_NAME="${NEW_APP_NAME#"${NEW_APP_NAME%%[![:space:]]*}"}"
NEW_APP_NAME="${NEW_APP_NAME%"${NEW_APP_NAME##*[![:space:]]}"}"
if [ -z "$NEW_APP_NAME" ]; then
  warn "No app name entered. Exiting."
  exit 0
fi

APP_SLUG=$(slugify "$NEW_APP_NAME")
[ -z "$APP_SLUG" ] && APP_SLUG="app"

# --- 2) Collect owners and let user pick or enter ---
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

# Build numbered list for pick
OWNERS_ARR=()
if [ -s "$OWNERS_FILE" ]; then
  while read -r o; do
    OWNERS_ARR+=("$o")
  done < <(sort -u "$OWNERS_FILE")
fi

CHOSEN_OWNER=""
if [ ${#OWNERS_ARR[@]} -gt 0 ]; then
  echoc green "Owners from workspace repos:"
  for i in "${!OWNERS_ARR[@]}"; do
    echo "  $((i+1))) ${OWNERS_ARR[$i]}"
  done
  echo ""
  read -rp "$(echo -e "${bold:-}Pick number (1-${#OWNERS_ARR[@]}) or enter owner (e.g. GitHub org):${reset:-} ")" OWNER_INPUT
  OWNER_INPUT="${OWNER_INPUT#"${OWNER_INPUT%%[![:space:]]*}"}"
  OWNER_INPUT="${OWNER_INPUT%"${OWNER_INPUT##*[![:space:]]}"}"
  if [ -n "$OWNER_INPUT" ]; then
    if [[ "$OWNER_INPUT" =~ ^[0-9]+$ ]] && [ "$OWNER_INPUT" -ge 1 ] && [ "$OWNER_INPUT" -le ${#OWNERS_ARR[@]} ]; then
      CHOSEN_OWNER="${OWNERS_ARR[$((OWNER_INPUT-1))]}"
    else
      CHOSEN_OWNER="$OWNER_INPUT"
    fi
  fi
fi

if [ -z "$CHOSEN_OWNER" ]; then
  read -rp "$(echo -e "${bold:-}Owner (e.g. GitHub org or username):${reset:-} ")" CHOSEN_OWNER
  CHOSEN_OWNER="${CHOSEN_OWNER#"${CHOSEN_OWNER%%[![:space:]]*}"}"
  CHOSEN_OWNER="${CHOSEN_OWNER%"${CHOSEN_OWNER##*[![:space:]]}"}"
fi

if [ -z "$CHOSEN_OWNER" ]; then
  warn "No owner entered. Exiting."
  exit 0
fi

echo ""
echoc cyan "App: $(color yellow "$NEW_APP_NAME") (slug: $APP_SLUG) — Owner: $CHOSEN_OWNER"
echo ""

# --- 3) Target path and clone from GitHub ---
FORK_PATH="$WORKSPACE_ROOT/$APP_SLUG"
if [ -d "$FORK_PATH" ]; then
  warn "Directory already exists: $FORK_PATH. Remove it or choose a different app name."
  exit 1
fi

echoc cyan "Cloning $TEMPLATE_REPO from GitHub into $APP_SLUG..."
if ! git clone --depth 1 "$TEMPLATE_URL" "$FORK_PATH"; then
  warn "Clone failed. Check network and that $TEMPLATE_URL exists and is accessible."
  exit 1
fi
rm -rf "$FORK_PATH/.git"
echo ""

# --- 5) Update config/app.json and run rebrand ---
echoc cyan "Updating app identity and running rebrand..."
mkdir -p "$FORK_PATH/config"
# Update app name/owner/slug in copied config (preserve rest of app.json)
if [ -f "$FORK_PATH/config/app.json" ]; then
  if command -v jq &>/dev/null; then
    jq ".app.name = \"$NEW_APP_NAME\" | .app.owner = \"$CHOSEN_OWNER\" | .app.slug = \"$APP_SLUG\"" "$FORK_PATH/config/app.json" > "$FORK_PATH/config/app.json.tmp" && mv "$FORK_PATH/config/app.json.tmp" "$FORK_PATH/config/app.json"
  else
    NODE_APP_JSON="$FORK_PATH/config/app.json" NNAME="$NEW_APP_NAME" NOWNER="$CHOSEN_OWNER" NSLUG="$APP_SLUG" node -e "
const fs=require('fs');
const p=process.env.NODE_APP_JSON;
const j=JSON.parse(fs.readFileSync(p,'utf8'));
if(!j.app) j.app={};
j.app.name=process.env.NNAME;
j.app.owner=process.env.NOWNER;
j.app.slug=process.env.NSLUG;
fs.writeFileSync(p,JSON.stringify(j,null,2)+'\n');
" 2>/dev/null || true
  fi
fi

(
  cd "$FORK_PATH"
  export MTX_IS_PROJECTB=1
  export MTX_REBRAND_NONINTERACTIVE=1
  export PROJECT_NAME="$NEW_APP_NAME"
  export OWNER="$CHOSEN_OWNER"
  mtx project rebrand
) || { warn "Rebrand failed."; exit 1; }
echo ""

# --- 6) Create GitHub repo and push ---
echoc cyan "Creating repository $GITHUB_ORG/$APP_SLUG and pushing..."
if ! command -v gh &>/dev/null; then
  warn "gh CLI not found. Create the repo manually: $GITHUB_ORG/$APP_SLUG then run from $FORK_PATH: git init && git add . && git commit -m '...' && git remote add origin git@github.com:$GITHUB_ORG/$APP_SLUG.git && git push -u origin main"
  exit 1
fi

(
  cd "$FORK_PATH"
  git init -q
  git add .
  git commit -q -m "Initial: fork from project-bridge, rebrand to $NEW_APP_NAME"
  git branch -M main
  gh repo create "$GITHUB_ORG/$APP_SLUG" --private --source=. --remote=origin --push
) || { warn "Git / gh repo create failed."; exit 1; }

echo ""
echoc green "Done. New app repo: https://github.com/$GITHUB_ORG/$APP_SLUG"
echoc dim "Local path: $FORK_PATH"
echo ""
