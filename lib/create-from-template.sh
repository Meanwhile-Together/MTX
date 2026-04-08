# Shared: scaffold a GitHub repo from a template with a fixed name prefix (payload- or org-).
# Loaded only from mtx create/payload, create/org, payload/create, org/create, or top-level create — NOT from includes/ (mtx auto-sources includes/*.sh at boot).
# Callers must set MTX_ROOT to the MTX repo root before sourcing this file.
# Callers set: MTX_REPO_PREFIX, MTX_TEMPLATE_REPO, MTX_KIND_LABEL, MTX_CREATE_CMD
# Optional: MTX_WORKSPACE_ROOT, MTX_GITHUB_ORG, MTX_CREATE_SKIP_GITHUB=1 (local git + snippet only; no gh)
# With gh: new repos use `gh repo create org/repo --source=. --remote=origin --push`; existing repos get origin + git push.

: "${MTX_ROOT:?Set MTX_ROOT to the MTX repository root before sourcing lib/create-from-template.sh}"

slugify() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/^-*\|-*$//g'
}

# Ensure repo name starts with required prefix (payload- or org-).
ensure_mtx_repo_prefix() {
  local raw="$1"
  local p="$2"
  case "$raw" in
    "${p}"*) echo "$raw" ;;
    *) echo "${p}${raw}" ;;
  esac
}

ensure_gh_auth_create() {
  if ! command -v gh &>/dev/null; then
    return 1
  fi
  if gh auth status &>/dev/null; then
    return 0
  fi
  # Non-interactive: never hang on browser login
  if [ ! -t 0 ] || [ ! -t 1 ]; then
    warn "gh is not logged in (non-interactive). Run: gh auth login"
    return 1
  fi
  while true; do
    echo ""
    echoc yellow "gh is not logged in. Complete authentication (browser or token)."
    if ! gh auth login; then
      warn "gh auth login failed or was cancelled."
      return 1
    fi
    if gh auth status &>/dev/null; then
      return 0
    fi
  done
}

# Before prompting: template must exist locally or be cloneable from TEMPLATE_URL.
mtx_create_ensure_template_available() {
  local local_path="$1" url="$2" repo="$3" ws="$4"

  if [ -d "$local_path/.git" ] || [ -f "$local_path/package.json" ]; then
    echoc dim "Template source: $local_path"
    return 0
  fi

  echoc yellow "No local template at: $local_path"
  echoc dim "Expected a sibling of MTX: $ws/$repo (clone or copy payload-basic there), or set MTX_WORKSPACE_ROOT."
  if ! command -v git &>/dev/null; then
    warn "git is required to fetch template from $url"
    exit 1
  fi
  echoc cyan "Checking remote template (read-only)..."
  if command -v timeout &>/dev/null; then
    if ! GIT_TERMINAL_PROMPT=0 timeout 25 git ls-remote --exit-code "$url" HEAD &>/dev/null; then
      warn "Cannot reach template at $url (timeout, network, private repo without auth, or repo missing)."
      echoc dim "Fix: clone the template next to MTX, e.g.: git clone ${url} \"$local_path\""
      exit 1
    fi
  else
    if ! GIT_TERMINAL_PROMPT=0 git ls-remote --exit-code "$url" HEAD &>/dev/null; then
      warn "Cannot reach template at $url (network, auth, or repo missing)."
      echoc dim "Fix: clone the template next to MTX, e.g.: git clone ${url} \"$local_path\""
      exit 1
    fi
  fi
  echoc dim "Remote template OK: $url"
}

mtx_create_ensure_github_org_reachable() {
  local org="$1"
  if gh api "orgs/$org" &>/dev/null; then
    return 0
  fi
  if gh api "users/$org" &>/dev/null; then
    return 0
  fi
  warn "GitHub org or user '$org' not found or not visible to gh (typo, token scopes, or pending SSO authorization)."
  echoc dim "Try: gh auth refresh; authorize SSO for the org in the GitHub web UI; set MTX_GITHUB_ORG if needed."
  return 1
}

mtx_create_local_git_commit_initial() {
  local path="$1" msg="$2"
  (
    cd "$path" || exit 1
    if [ ! -d .git ]; then
      git init -q && git branch -M main
    fi
    if [ -n "$(git status --porcelain)" ]; then
      git add .
      git commit -q -m "$msg"
    fi
  )
}

mtx_create_print_server_json_snippet() {
  local id="$1" name="$2" slug="$3" org="$4" reponame="$5"
  echo ""
  echoc cyan "Add to project-bridge config/server.json (top-level apps array):"
  echo ""
  echo "{"
  echo "  \"id\": \"$id\","
  echo "  \"name\": \"$name\","
  echo "  \"slug\": \"$slug\","
  echo "  \"source\": {"
  echo "    \"git\": {"
  echo "      \"url\": \"https://github.com/$org/$reponame.git\","
  echo "      \"ref\": \"main\""
  echo "    }"
  echo "  }"
  echo "}"
  echo ""
}

update_repo_metadata_from_template() {
  local dir="$1"
  local pkg_json="$dir/package.json"
  local readme="$dir/README.md"
  local desc_line="${MTX_KIND_LABEL} payload: ${NEW_APP_NAME} (repo ${REPO_NAME}, template ${TEMPLATE_REPO})"

  if [ ! -f "$pkg_json" ]; then
    warn "Template does not include package.json at $pkg_json"
    exit 1
  fi

  if command -v jq &>/dev/null; then
    jq \
      --arg pkgName "@meanwhile-together/${REPO_NAME}" \
      --arg appName "$NEW_APP_NAME" \
      --arg repo "$REPO_NAME" \
      --arg d "$desc_line" \
      '
      .name = $pkgName
      | .description = $d
      ' "$pkg_json" > "$pkg_json.tmp" && mv "$pkg_json.tmp" "$pkg_json"
  else
    NODE_PAYLOAD_PACKAGE_JSON="$pkg_json" \
    NNAME="@meanwhile-together/${REPO_NAME}" \
    NDESC="$desc_line" \
    node -e "
const fs=require('fs');
const p=process.env.NODE_PAYLOAD_PACKAGE_JSON;
const j=JSON.parse(fs.readFileSync(p,'utf8'));
j.name=process.env.NNAME;
j.description=process.env.NDESC;
fs.writeFileSync(p,JSON.stringify(j,null,2)+'\n');
" 2>/dev/null || true
  fi

  cat > "$readme" <<EOF
# $REPO_NAME

${MTX_KIND_LABEL} payload for **$NEW_APP_NAME**.

Created by \`${MTX_CREATE_CMD}\` from template \`$TEMPLATE_REPO\`.

## Next steps

1. Install dependencies:
   \`\`\`bash
   npm install
   \`\`\`
2. Build:
   \`\`\`bash
   npm run build
   \`\`\`
3. Register in project-bridge \`config/server.json\` (top-level \`apps\` array) with \`source.git\` pointing at this repo.
EOF
}

mtx_create_from_template_run() {
  local WORKSPACE_ROOT GITHUB_ORG TEMPLATE_REPO TEMPLATE_URL LOCAL_TEMPLATE_PATH
  local NEW_APP_NAME APP_SLUG REPO_PATH

  : "${MTX_REPO_PREFIX:?Set MTX_REPO_PREFIX (payload- or org-)}"
  : "${MTX_TEMPLATE_REPO:?Set MTX_TEMPLATE_REPO}"
  : "${MTX_KIND_LABEL:?Set MTX_KIND_LABEL}"
  : "${MTX_CREATE_CMD:?Set MTX_CREATE_CMD}"

  WORKSPACE_ROOT="${MTX_WORKSPACE_ROOT:-$(cd "$MTX_ROOT/.." && pwd)}"
  GITHUB_ORG="${MTX_GITHUB_ORG:-Meanwhile-Together}"
  TEMPLATE_REPO="$MTX_TEMPLATE_REPO"
  TEMPLATE_URL="https://github.com/${GITHUB_ORG}/${TEMPLATE_REPO}.git"
  LOCAL_TEMPLATE_PATH="$WORKSPACE_ROOT/$TEMPLATE_REPO"

  if ! command -v git &>/dev/null; then
    warn "git is required for mtx create (template clone and commits)."
    exit 1
  fi

  mtx_create_ensure_template_available "$LOCAL_TEMPLATE_PATH" "$TEMPLATE_URL" "$TEMPLATE_REPO" "$WORKSPACE_ROOT"

  echoc cyan "Create new $(echo "$MTX_KIND_LABEL" | tr '[:upper:]' '[:lower:]') payload (${MTX_REPO_PREFIX}*)"
  echo ""
  read -rp "$(echo -e "${bold:-}Display name (organization or app name):${reset:-} ")" NEW_APP_NAME
  NEW_APP_NAME="${NEW_APP_NAME#"${NEW_APP_NAME%%[![:space:]]*}"}"
  NEW_APP_NAME="${NEW_APP_NAME%"${NEW_APP_NAME##*[![:space:]]}"}"
  if [ -z "$NEW_APP_NAME" ]; then
    warn "No name entered. Exiting."
    exit 0
  fi

  APP_SLUG=$(slugify "$NEW_APP_NAME")
  [ -z "$APP_SLUG" ] && APP_SLUG="app"
  REPO_NAME=$(ensure_mtx_repo_prefix "$APP_SLUG" "$MTX_REPO_PREFIX")
  REPO_PATH="$WORKSPACE_ROOT/$REPO_NAME"

  echo ""
  echoc cyan "Workspace: $WORKSPACE_ROOT"
  echoc cyan "Template: $TEMPLATE_REPO"
  echoc cyan "New repo: $(color yellow "$REPO_NAME")"
  echoc dim "Command: $MTX_CREATE_CMD"
  echo ""

  if [ -d "$REPO_PATH" ]; then
    if [ -f "$REPO_PATH/package.json" ]; then
      echoc cyan "Using existing directory at $REPO_PATH (idempotent update)."
    else
      warn "Directory $REPO_PATH exists but has no package.json. Remove it or choose another name."
      exit 1
    fi
  else
    echoc cyan "Cloning template into $REPO_PATH..."
    if [ -d "$LOCAL_TEMPLATE_PATH/.git" ]; then
      if ! git clone --depth 1 "$LOCAL_TEMPLATE_PATH" "$REPO_PATH"; then
        warn "Local template clone failed from $LOCAL_TEMPLATE_PATH."
        exit 1
      fi
    elif [ -f "$LOCAL_TEMPLATE_PATH/package.json" ]; then
      if ! cp -R "$LOCAL_TEMPLATE_PATH" "$REPO_PATH"; then
        warn "Local template copy failed from $LOCAL_TEMPLATE_PATH."
        exit 1
      fi
      rm -rf "$REPO_PATH/.git"
    else
      if ! git clone --depth 1 "$TEMPLATE_URL" "$REPO_PATH"; then
        warn "Template clone failed. Check local template '$LOCAL_TEMPLATE_PATH' or remote '$TEMPLATE_URL'."
        exit 1
      fi
    fi
    (cd "$REPO_PATH" && git remote rename origin upstream 2>/dev/null || true)
    echo ""
  fi

  echoc cyan "Applying package name and metadata..."
  update_repo_metadata_from_template "$REPO_PATH"
  echo ""

  if [ "${MTX_CREATE_SKIP_GITHUB:-}" = "1" ]; then
    mtx_create_local_git_commit_initial "$REPO_PATH" "${MTX_CREATE_CMD}: initialize ${REPO_NAME} from ${TEMPLATE_REPO} (local only)"
    echoc yellow "Skipped GitHub (MTX_CREATE_SKIP_GITHUB=1). Push from $REPO_PATH when the remote exists."
    echoc dim "Local path: $REPO_PATH"
    mtx_create_print_server_json_snippet "$REPO_NAME" "$NEW_APP_NAME" "$APP_SLUG" "$GITHUB_ORG" "$REPO_NAME"
    exit 0
  fi

  if ! command -v gh &>/dev/null; then
    mtx_create_local_git_commit_initial "$REPO_PATH" "${MTX_CREATE_CMD}: initialize ${REPO_NAME} from ${TEMPLATE_REPO}"
    warn "gh CLI not found. Local tree is ready at $REPO_PATH. Install gh, then from $REPO_PATH: gh repo create $GITHUB_ORG/$REPO_NAME --private --source=. --remote=origin --push"
    echoc dim "Local path: $REPO_PATH"
    mtx_create_print_server_json_snippet "$REPO_NAME" "$NEW_APP_NAME" "$APP_SLUG" "$GITHUB_ORG" "$REPO_NAME"
    exit 1
  fi

  ensure_gh_auth_create || { warn "gh authentication required for create/push."; exit 1; }

  mtx_create_ensure_github_org_reachable "$GITHUB_ORG" || exit 1

  if ! (
    set -e
    cd "$REPO_PATH"
    WANT_REMOTE="git@github.com:${GITHUB_ORG}/${REPO_NAME}.git"
    WANT_REMOTE_HTTPS="https://github.com/${GITHUB_ORG}/${REPO_NAME}.git"

    if [ ! -d .git ]; then
      git init -q
    fi
    git branch -M main

    if [ -n "$(git status --porcelain)" ]; then
      git add .
      git commit -q -m "${MTX_CREATE_CMD}: initialize ${REPO_NAME} from ${TEMPLATE_REPO}"
    fi

    # Ensure at least one commit for push (metadata should always dirty the tree once)
    if ! git rev-parse -q --verify HEAD >/dev/null; then
      git add -A
      git commit -q --allow-empty -m "${MTX_CREATE_CMD}: initialize ${REPO_NAME} from ${TEMPLATE_REPO}"
    fi

    if ! gh repo view "$GITHUB_ORG/$REPO_NAME" &>/dev/null; then
      echoc cyan "Creating GitHub repository $GITHUB_ORG/$REPO_NAME and pushing main..."
      git remote remove origin 2>/dev/null || true
      gh repo create "$GITHUB_ORG/$REPO_NAME" --private \
        --description "${MTX_KIND_LABEL} payload: $NEW_APP_NAME (from $TEMPLATE_REPO)" \
        --source=. --remote=origin --push
    else
      echoc cyan "GitHub repo exists; setting origin and pushing..."
      CURRENT_REMOTE=$(git remote get-url origin 2>/dev/null || true)
      if [ "$CURRENT_REMOTE" = "$WANT_REMOTE" ] || [ "$CURRENT_REMOTE" = "$WANT_REMOTE_HTTPS" ]; then
        :
      elif [ -n "$CURRENT_REMOTE" ]; then
        git remote set-url origin "$WANT_REMOTE"
      else
        git remote add origin "$WANT_REMOTE"
      fi
      git push -u origin main 2>/dev/null || git push origin main
    fi
  ); then
    warn "GitHub create or push failed. Check gh auth (gh auth login), org permissions, branch main, and write access to $GITHUB_ORG/$REPO_NAME."
    exit 1
  fi

  if ! gh repo view "$GITHUB_ORG/$REPO_NAME" &>/dev/null; then
    warn "Push finished but gh cannot resolve $GITHUB_ORG/$REPO_NAME (visibility lag or wrong org)."
    exit 1
  fi

  echo ""
  echoc green "Done. New repo: https://github.com/$GITHUB_ORG/$REPO_NAME"
  echoc dim "Local path: $REPO_PATH"
  mtx_create_print_server_json_snippet "$REPO_NAME" "$NEW_APP_NAME" "$APP_SLUG" "$GITHUB_ORG" "$REPO_NAME"
}
