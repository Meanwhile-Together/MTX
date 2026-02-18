#!/usr/bin/env bash
# MTX create: new app from project-bridge — pick/enter owner, clone from GitHub, rebrand, create repo, push.
# Idempotent: if project folder exists with config, only updates config/rebrand/git as needed; never re-clones.
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

# Ensure gh is authenticated; run gh auth login and wait until gh auth status succeeds.
ensure_gh_auth() {
  if ! command -v gh &>/dev/null; then
    return 1
  fi
  while true; do
    if gh auth status &>/dev/null; then
      return 0
    fi
    echo ""
    echoc yellow "gh is not logged in. Complete authentication (browser or token)."
    if ! gh auth login; then
      warn "gh auth login failed or was cancelled."
      return 1
    fi
  done
}

# Update config/app.json app.name, app.owner, app.slug (preserve rest of JSON). Idempotent.
update_app_config() {
  local dir="$1"
  local app_json="${dir}/config/app.json"
  mkdir -p "${dir}/config"
  if [ ! -f "$app_json" ]; then
    if command -v jq &>/dev/null; then
      jq -n \
        --arg name "$NEW_APP_NAME" \
        --arg owner "$CHOSEN_OWNER" \
        --arg slug "$APP_SLUG" \
        '{ app: { name: $name, owner: $owner, slug: $slug, version: "1.0.0" } }' > "$app_json"
    else
      cat > "$app_json" <<EOF
{
  "app": {
    "name": "$NEW_APP_NAME",
    "owner": "$CHOSEN_OWNER",
    "slug": "$APP_SLUG",
    "version": "1.0.0"
  }
}
EOF
    fi
    return
  fi
  if command -v jq &>/dev/null; then
    jq ".app.name = \"$NEW_APP_NAME\" | .app.owner = \"$CHOSEN_OWNER\" | .app.slug = \"$APP_SLUG\"" "$app_json" > "$app_json.tmp" && mv "$app_json.tmp" "$app_json"
  else
    NODE_APP_JSON="$app_json" NNAME="$NEW_APP_NAME" NOWNER="$CHOSEN_OWNER" NSLUG="$APP_SLUG" node -e "
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
}

# Run rebrand in dir (non-interactive). Idempotent.
run_rebrand() {
  local dir="$1"
  (
    cd "$dir"
    export MTX_IS_PROJECTB=1
    export MTX_REBRAND_NONINTERACTIVE=1
    export PROJECT_NAME="$NEW_APP_NAME"
    export OWNER="$CHOSEN_OWNER"
    mtx project rebrand
  ) || { warn "Rebrand failed."; return 1; }
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

FORK_PATH="$WORKSPACE_ROOT/$APP_SLUG"
EXISTING_PROJECT=0
if [ -d "$FORK_PATH" ]; then
  if [ -f "$FORK_PATH/config/app.json" ]; then
    EXISTING_PROJECT=1
    echoc cyan "Using existing project at $FORK_PATH (idempotent update)."
  else
    warn "Directory $FORK_PATH exists but has no config/app.json. Remove it or choose a different app name."
    exit 1
  fi
fi

if [ "$EXISTING_PROJECT" -eq 0 ]; then
  # --- Clone from GitHub (only when folder does not exist) ---
  echoc cyan "Cloning $TEMPLATE_REPO from GitHub into $APP_SLUG..."
  if ! git clone --depth 1 "$TEMPLATE_URL" "$FORK_PATH"; then
    warn "Clone failed. Check network and that $TEMPLATE_URL exists and is accessible."
    exit 1
  fi
  # Keep .git so the new repo can be a real fork (same history as project-bridge)
  (cd "$FORK_PATH" && git remote rename origin upstream 2>/dev/null || true)
  echo ""
fi

# --- Update config/app.json (idempotent: always set name/owner/slug) ---
echoc cyan "Ensuring app identity in config..."
update_app_config "$FORK_PATH"
echo ""

# --- Rebrand (idempotent: safe to run every time) ---
echoc cyan "Running rebrand..."
run_rebrand "$FORK_PATH" || exit 1
echo ""

# --- Git: ensure repo, remote, commit, push (idempotent) ---
if ! command -v gh &>/dev/null; then
  warn "gh CLI not found. From $FORK_PATH run: git init && git add . && git commit -m '...' && git remote add origin git@github.com:$GITHUB_ORG/$APP_SLUG.git && git push -u origin main"
  exit 1
fi

ensure_gh_auth || { warn "gh authentication required for create/push."; exit 1; }

(
  cd "$FORK_PATH"
  WANT_REMOTE="git@github.com:${GITHUB_ORG}/${APP_SLUG}.git"
  WANT_REMOTE_HTTPS="https://github.com/${GITHUB_ORG}/${APP_SLUG}.git"

  if [ ! -d .git ]; then
    git init -q
    git branch -M main
  fi

  # Create the GitHub repo as a fork of project-bridge if it doesn't exist
  if ! gh repo view "$GITHUB_ORG/$APP_SLUG" &>/dev/null; then
    echoc cyan "Creating fork $GITHUB_ORG/$APP_SLUG (fork of $GITHUB_ORG/$TEMPLATE_REPO)..."
    if ! gh repo fork "$GITHUB_ORG/$TEMPLATE_REPO" --org "$GITHUB_ORG" --fork-name "$APP_SLUG" --clone=false 2>/dev/null; then
      # Same-org fork may be disabled; create repo and push (no fork link)
      echoc dim "Fork in same org not available; creating repository $GITHUB_ORG/$APP_SLUG..."
      gh repo create "$GITHUB_ORG/$APP_SLUG" --private --description "App: $NEW_APP_NAME (from project-bridge)"
    fi
  fi

  # Ensure remote origin points to the fork (set-url if origin exists, else add — avoids "already exists" error)
  CURRENT_REMOTE=$(git remote get-url origin 2>/dev/null || true)
  if [ "$CURRENT_REMOTE" = "$WANT_REMOTE" ] || [ "$CURRENT_REMOTE" = "$WANT_REMOTE_HTTPS" ]; then
    : # already correct
  elif [ -n "$CURRENT_REMOTE" ]; then
    git remote set-url origin "$WANT_REMOTE"
  else
    git remote add origin "$WANT_REMOTE"
  fi

  # Commit if there are changes
  if [ -n "$(git status --porcelain)" ]; then
    git add .
    git commit -q -m "mtx create: rebrand to $NEW_APP_NAME (idempotent sync)"
  fi

  git branch -M main

  # Push (fork already exists at this point)
  git push -u origin main 2>/dev/null || git push origin main
) || { warn "Git / gh push failed."; exit 1; }

echo ""
echoc green "Done. New app repo: https://github.com/$GITHUB_ORG/$APP_SLUG"
echoc dim "Local path: $FORK_PATH"
echo ""
