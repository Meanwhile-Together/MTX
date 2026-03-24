#!/usr/bin/env bash
# MTX create: canonical "new app" flow = create a new payload repo from a payload template.
desc="Create new payload/app: clone payload template, rename, create repo, and push"
nobanner=1
set -e

# Workspace root (dir containing MTX + project-bridge + payload repos)
WORKSPACE_ROOT="${MTX_WORKSPACE_ROOT:-$(cd .. && pwd)}"
GITHUB_ORG="${MTX_GITHUB_ORG:-Meanwhile-Together}"
TEMPLATE_REPO="${MTX_PAYLOAD_TEMPLATE_REPO:-payload-basic}"
TEMPLATE_URL="https://github.com/${GITHUB_ORG}/${TEMPLATE_REPO}.git"
LOCAL_TEMPLATE_PATH="$WORKSPACE_ROOT/$TEMPLATE_REPO"

slugify() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/^-*\|-*$//g'
}

ensure_payload_prefix() {
  local raw="$1"
  case "$raw" in
    payload-*) echo "$raw" ;;
    *) echo "payload-$raw" ;;
  esac
}

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

update_payload_metadata() {
  local dir="$1"
  local pkg_json="$dir/package.json"
  local readme="$dir/README.md"

  if [ ! -f "$pkg_json" ]; then
    warn "Template does not include package.json at $pkg_json"
    exit 1
  fi

  if command -v jq &>/dev/null; then
    jq \
      --arg pkgName "@meanwhile-together/${PAYLOAD_REPO}" \
      --arg appName "$NEW_APP_NAME" \
      --arg repo "$PAYLOAD_REPO" \
      '
      .name = $pkgName
      | .description = ("Payload app: " + $appName + " (created from " + $repo + ")")
      ' "$pkg_json" > "$pkg_json.tmp" && mv "$pkg_json.tmp" "$pkg_json"
  else
    NODE_PAYLOAD_PACKAGE_JSON="$pkg_json" \
    NNAME="@meanwhile-together/${PAYLOAD_REPO}" \
    NAPP="$NEW_APP_NAME" \
    NREPO="$PAYLOAD_REPO" \
    node -e "
const fs=require('fs');
const p=process.env.NODE_PAYLOAD_PACKAGE_JSON;
const j=JSON.parse(fs.readFileSync(p,'utf8'));
j.name=process.env.NNAME;
j.description='Payload app: '+process.env.NAPP+' (created from '+process.env.NREPO+')';
fs.writeFileSync(p,JSON.stringify(j,null,2)+'\n');
" 2>/dev/null || true
  fi

  cat > "$readme" <<EOF
# $PAYLOAD_REPO

Payload repository for **$NEW_APP_NAME**.

Created by \`mtx create\` from template \`$TEMPLATE_REPO\`.

## Next steps

1. Install dependencies:
   \`\`\`bash
   npm install
   \`\`\`
2. Build the payload:
   \`\`\`bash
   npm run build
   \`\`\`
3. Register this payload in project-bridge \`config/server.json\` under \`server.apps\`.
EOF
}

echoc cyan "Create new payload app"
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
PAYLOAD_REPO=$(ensure_payload_prefix "$APP_SLUG")
PAYLOAD_PATH="$WORKSPACE_ROOT/$PAYLOAD_REPO"

echo ""
echoc cyan "Workspace: $WORKSPACE_ROOT"
echoc cyan "Template: $TEMPLATE_REPO"
echoc cyan "New payload repo: $(color yellow "$PAYLOAD_REPO")"
echo ""

if [ -d "$PAYLOAD_PATH" ]; then
  if [ -f "$PAYLOAD_PATH/package.json" ]; then
    echoc cyan "Using existing payload directory at $PAYLOAD_PATH (idempotent update)."
  else
    warn "Directory $PAYLOAD_PATH exists but has no package.json. Remove it or choose another app name."
    exit 1
  fi
else
  echoc cyan "Cloning payload template into $PAYLOAD_PATH..."
  if [ -d "$LOCAL_TEMPLATE_PATH/.git" ]; then
    if ! git clone --depth 1 "$LOCAL_TEMPLATE_PATH" "$PAYLOAD_PATH"; then
      warn "Local template clone failed from $LOCAL_TEMPLATE_PATH."
      exit 1
    fi
  elif [ -f "$LOCAL_TEMPLATE_PATH/package.json" ]; then
    if ! cp -R "$LOCAL_TEMPLATE_PATH" "$PAYLOAD_PATH"; then
      warn "Local template copy failed from $LOCAL_TEMPLATE_PATH."
      exit 1
    fi
    rm -rf "$PAYLOAD_PATH/.git"
  else
    if ! git clone --depth 1 "$TEMPLATE_URL" "$PAYLOAD_PATH"; then
      warn "Template clone failed. Check local template '$LOCAL_TEMPLATE_PATH' or remote '$TEMPLATE_URL'."
      exit 1
    fi
  fi
  (cd "$PAYLOAD_PATH" && git remote rename origin upstream 2>/dev/null || true)
  echo ""
fi

echoc cyan "Applying payload naming and metadata..."
update_payload_metadata "$PAYLOAD_PATH"
echo ""

if ! command -v gh &>/dev/null; then
  warn "gh CLI not found. From $PAYLOAD_PATH run: git init && git add . && git commit -m 'mtx create: initialize $PAYLOAD_REPO' && git remote add origin git@github.com:$GITHUB_ORG/$PAYLOAD_REPO.git && git push -u origin main"
  exit 1
fi

ensure_gh_auth || { warn "gh authentication required for create/push."; exit 1; }

(
  cd "$PAYLOAD_PATH"
  WANT_REMOTE="git@github.com:${GITHUB_ORG}/${PAYLOAD_REPO}.git"
  WANT_REMOTE_HTTPS="https://github.com/${GITHUB_ORG}/${PAYLOAD_REPO}.git"

  if [ ! -d .git ]; then
    git init -q
  fi
  git branch -M main

  if ! gh repo view "$GITHUB_ORG/$PAYLOAD_REPO" &>/dev/null; then
    echoc cyan "Creating repository $GITHUB_ORG/$PAYLOAD_REPO..."
    gh repo create "$GITHUB_ORG/$PAYLOAD_REPO" --private --description "Payload app: $NEW_APP_NAME (from $TEMPLATE_REPO)"
  fi

  CURRENT_REMOTE=$(git remote get-url origin 2>/dev/null || true)
  if [ "$CURRENT_REMOTE" = "$WANT_REMOTE" ] || [ "$CURRENT_REMOTE" = "$WANT_REMOTE_HTTPS" ]; then
    :
  elif [ -n "$CURRENT_REMOTE" ]; then
    git remote set-url origin "$WANT_REMOTE"
  else
    git remote add origin "$WANT_REMOTE"
  fi

  if [ -n "$(git status --porcelain)" ]; then
    git add .
    git commit -q -m "mtx create: initialize ${PAYLOAD_REPO} from ${TEMPLATE_REPO}"
  fi

  git push -u origin main 2>/dev/null || git push origin main
)

echo ""
echoc green "Done. New payload repo: https://github.com/$GITHUB_ORG/$PAYLOAD_REPO"
echoc dim "Local path: $PAYLOAD_PATH"
echo ""
echoc cyan "Add this to project-bridge config/server.json (server.apps):"
echo ""
echo "{"
echo "  \"id\": \"$PAYLOAD_REPO\","
echo "  \"name\": \"$NEW_APP_NAME\","
echo "  \"slug\": \"$APP_SLUG\","
echo "  \"source\": {"
echo "    \"git\": {"
echo "      \"url\": \"https://github.com/$GITHUB_ORG/$PAYLOAD_REPO.git\","
echo "      \"ref\": \"main\""
echo "    }"
echo "  }"
echo "}"
echo ""
