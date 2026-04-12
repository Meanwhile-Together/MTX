# Shared: scaffold a GitHub repo from a template with a fixed name prefix (payload-, org-, or template-).
# Loaded only from mtx create/payload|org|template, payload/template create (legacy), or top-level create — NOT from includes/ (mtx auto-sources includes/*.sh at boot).
# Callers must set MTX_ROOT to the MTX repo root before sourcing this file.
# Callers set: MTX_REPO_PREFIX, MTX_TEMPLATE_REPO, MTX_KIND_LABEL, MTX_CREATE_CMD, MTX_CREATE_VARIANT (org|payload)
# Repo prefixes: payload-, org-, template- (`template-*` = payload templates only; see docs/MTX_SCAFFOLDING_MODEL.md).
# Optional: MTX_WORKSPACE_ROOT, MTX_GITHUB_ORG, MTX_CREATE_SKIP_GITHUB=1 (local git + snippet only; no gh).
# Optional CLI name: mtx_create_from_template_run "$@" — if any args are given, they are joined with
# spaces (trimmed) and used as the display name; otherwise the script prompts interactively.
# Org (org-*): prompts for repo name, app slug, owner, URLs, deploy projectId, server.json paths (defaults always shown).
#   Non-interactive: MTX_CREATE_NONINTERACTIVE=1 or no TTY — use MTX_ORG_REPO_NAME, MTX_ORG_DISPLAY_NAME,
#   MTX_ORG_APP_SLUG, MTX_ORG_OWNER, MTX_ORG_VERSION, MTX_ORG_DEV_PORT, MTX_ORG_DEV_URL, MTX_ORG_STAGING_PORT,
#   MTX_ORG_STAGING_URL, MTX_ORG_PROD_PORT, MTX_ORG_PROD_URL, MTX_ORG_DEPLOY_PROJECT_ID, MTX_ORG_SERVER_PORT,
#   MTX_ORG_PROJECT_ROOT, MTX_ORG_STATE_DIR (secrets stay in backend.example.json / .env — not prompted).
# Default clone source repo name: template-basic (override with MTX_PAYLOAD_TEMPLATE_REPO / MTX_ORG_TEMPLATE_REPO / MTX_TEMPLATE_SOURCE_REPO).
# With gh: new repos use `gh repo create org/repo --source=. --remote=origin --push`; existing repos get origin + git push.

: "${MTX_ROOT:?Set MTX_ROOT to the MTX repository root before sourcing lib/create-from-template.sh}"

# When sourced outside mtx wrapper, load helpers and define safe fallbacks.
if [ -d "$MTX_ROOT/includes" ]; then
  # shellcheck disable=SC1091
  for f in "$MTX_ROOT"/includes/*.sh; do source "$f"; done
fi
declare -F echoc >/dev/null || echoc() { local _c="$1"; shift || true; echo "$*"; }
declare -F info >/dev/null || info() { echo "[INFO] $*"; }
declare -F warn >/dev/null || warn() { echo "[WARN] $*" >&2; }
declare -F error >/dev/null || error() { echo "[ERROR] $*" >&2; }
declare -F success >/dev/null || success() { echo "[SUCCESS] $*"; }
declare -F mtx_run >/dev/null || mtx_run() { "$@"; }

slugify() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/^-*\|-*$//g'
}

# Set MTX_CREATE_VARIANT to org|payload from create/*.sh entrypoints; avoids mixing flows if prefix alone is ambiguous.
mtx_create_is_org_flow() {
  case "${MTX_CREATE_VARIANT:-}" in
    org) return 0 ;;
    payload) return 1 ;;
  esac
  [ "${MTX_REPO_PREFIX}" = "org-" ]
}

# Ensure repo name starts with required prefix (payload-, org-, template-, …).
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
  echoc dim "Expected a sibling of MTX: $ws/$repo (clone or copy template-basic there), or set MTX_WORKSPACE_ROOT."
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

# Interactive defaults for org host config (secrets never prompted — use backend.example.json / env).
# Sets ORG_CFG_* and APP_SLUG. Non-interactive: MTX_ORG_* env vars or defaults only.
mtx_org_collect_host_config() {
  local repo_name="$1" display_name="$2" github_org="$3"
  local default_slug
  default_slug=$(slugify "${repo_name#org-}")
  [ -z "$default_slug" ] && default_slug=$(slugify "$repo_name")

  ORG_CFG_DISPLAY_NAME="${MTX_ORG_DISPLAY_NAME:-$display_name}"
  ORG_CFG_APP_SLUG="${MTX_ORG_APP_SLUG:-$default_slug}"
  ORG_CFG_OWNER=$(printf '%s' "${MTX_ORG_OWNER:-$github_org}" | tr '[:upper:]' '[:lower:]')
  ORG_CFG_VERSION="${MTX_ORG_VERSION:-1.0.0}"
  ORG_CFG_DEV_PORT="${MTX_ORG_DEV_PORT:-3001}"
  ORG_CFG_DEV_URL="${MTX_ORG_DEV_URL:-http://localhost:3001}"
  ORG_CFG_STAGING_PORT="${MTX_ORG_STAGING_PORT:-3001}"
  ORG_CFG_STAGING_URL="${MTX_ORG_STAGING_URL:-https://staging-api.example.com}"
  ORG_CFG_PROD_PORT="${MTX_ORG_PROD_PORT:-3001}"
  ORG_CFG_PROD_URL="${MTX_ORG_PROD_URL:-https://api.example.com}"
  ORG_CFG_DEPLOY_PROJECT_ID="${MTX_ORG_DEPLOY_PROJECT_ID:-}"
  ORG_CFG_SERVER_PORT="${MTX_ORG_SERVER_PORT:-3001}"
  ORG_CFG_PROJECT_ROOT="${MTX_ORG_PROJECT_ROOT:-..}"
  ORG_CFG_STATE_DIR="${MTX_ORG_STATE_DIR:-.state}"

  if [ -t 0 ] && [ -t 1 ] && [ "${MTX_CREATE_NONINTERACTIVE:-}" != "1" ]; then
    echo ""
    echoc cyan "Org repo — host & deploy (Enter = keep default):"
    local _v
    read -rp "  Display name (app.json / UI) [$ORG_CFG_DISPLAY_NAME]: " _v
    [ -n "$_v" ] && ORG_CFG_DISPLAY_NAME="$_v"
    read -rp "  Slug (config + Railway) [$ORG_CFG_APP_SLUG]: " _v
    [ -n "$_v" ] && ORG_CFG_APP_SLUG="$(slugify "$_v")"
    [ -z "$ORG_CFG_APP_SLUG" ] && ORG_CFG_APP_SLUG="$default_slug"
    read -rp "  Railway / workspace owner (GitHub org name) [$ORG_CFG_OWNER]: " _v
    [ -n "$_v" ] && ORG_CFG_OWNER=$(printf '%s' "$_v" | tr '[:upper:]' '[:lower:]')
    read -rp "  App version [$ORG_CFG_VERSION]: " _v
    [ -n "$_v" ] && ORG_CFG_VERSION="$_v"
    read -rp "  Development port [$ORG_CFG_DEV_PORT]: " _v
    [ -n "$_v" ] && ORG_CFG_DEV_PORT="$_v"
    read -rp "  Development URL [$ORG_CFG_DEV_URL]: " _v
    [ -n "$_v" ] && ORG_CFG_DEV_URL="$_v"
    read -rp "  Staging URL [$ORG_CFG_STAGING_URL]: " _v
    [ -n "$_v" ] && ORG_CFG_STAGING_URL="$_v"
    read -rp "  Production URL [$ORG_CFG_PROD_URL]: " _v
    [ -n "$_v" ] && ORG_CFG_PROD_URL="$_v"
    read -rp "  Railway deploy.json projectId (optional) [$ORG_CFG_DEPLOY_PROJECT_ID]: " _v
    ORG_CFG_DEPLOY_PROJECT_ID="${_v:-$ORG_CFG_DEPLOY_PROJECT_ID}"
    read -rp "  server.json — HTTP port [$ORG_CFG_SERVER_PORT]: " _v
    [ -n "$_v" ] && ORG_CFG_SERVER_PORT="$_v"
    read -rp "  server.json — projectRoot (unified server) [$ORG_CFG_PROJECT_ROOT]: " _v
    [ -n "$_v" ] && ORG_CFG_PROJECT_ROOT="$_v"
    read -rp "  server.json — stateDir [$ORG_CFG_STATE_DIR]: " _v
    [ -n "$_v" ] && ORG_CFG_STATE_DIR="$_v"
    echo ""
  fi

  export ORG_CFG_DISPLAY_NAME ORG_CFG_APP_SLUG ORG_CFG_OWNER ORG_CFG_VERSION
  export ORG_CFG_DEV_PORT ORG_CFG_DEV_URL ORG_CFG_STAGING_PORT ORG_CFG_STAGING_URL ORG_CFG_PROD_PORT ORG_CFG_PROD_URL
  export ORG_CFG_DEPLOY_PROJECT_ID ORG_CFG_SERVER_PORT ORG_CFG_PROJECT_ROOT ORG_CFG_STATE_DIR
  APP_SLUG="$ORG_CFG_APP_SLUG"
}

# Org repos: same config surface as project-bridge (from template) + terraform/ vendored from sibling project-bridge.
mtx_org_scaffold_deploy_config_surface() {
  local repo_path="$1" repo_name="$2" _display_name="$3" workspace_root="$4" github_org="$5"
  local tf_src gitignore app_base deploy_base server_base

  if ! command -v jq &>/dev/null; then
    warn "jq is required to merge org host config (install jq)."
    return 1
  fi

  mkdir -p "$repo_path/config"
  workspace_root="$(cd "$workspace_root" && pwd -P)"
  app_base="$repo_path/config/app.json"
  if [ ! -f "$app_base" ] && [ -f "$workspace_root/project-bridge/config/app.json" ]; then
    echoc dim "Using project-bridge config/app.json as base (template had no app.json)."
    cp -a "$workspace_root/project-bridge/config/app.json" "$app_base"
  fi
  if [ ! -f "$app_base" ]; then
    warn "No config/app.json in template and no project-bridge sibling; cannot scaffold org host config."
    return 1
  fi

  jq \
    --arg name "$ORG_CFG_DISPLAY_NAME" \
    --arg slug "$ORG_CFG_APP_SLUG" \
    --arg owner "$ORG_CFG_OWNER" \
    --arg ver "$ORG_CFG_VERSION" \
    --argjson devp "${ORG_CFG_DEV_PORT:-3001}" \
    --arg devu "$ORG_CFG_DEV_URL" \
    --argjson stp "${ORG_CFG_STAGING_PORT:-3001}" \
    --arg stu "$ORG_CFG_STAGING_URL" \
    --argjson prp "${ORG_CFG_PROD_PORT:-3001}" \
    --arg pru "$ORG_CFG_PROD_URL" \
    '
    .app.name = $name
    | .app.slug = $slug
    | .app.owner = $owner
    | .app.version = $ver
    | .development.port = $devp
    | .development.url = $devu
    | .staging.port = $stp
    | .staging.url = $stu
    | .production.port = $prp
    | .production.url = $pru
    ' "$app_base" > "${app_base}.tmp" && mv "${app_base}.tmp" "$app_base"

  deploy_base="$repo_path/config/deploy.json"
  if [ ! -f "$deploy_base" ] && [ -f "$workspace_root/project-bridge/config/deploy.json" ]; then
    cp -a "$workspace_root/project-bridge/config/deploy.json" "$deploy_base"
  fi
  if [ -f "$deploy_base" ]; then
    jq --arg pid "$ORG_CFG_DEPLOY_PROJECT_ID" '.projectId = $pid' "$deploy_base" > "${deploy_base}.tmp" && mv "${deploy_base}.tmp" "$deploy_base"
  fi

  server_base="$repo_path/config/server.json.example"
  if [ ! -f "$server_base" ] && [ -f "$workspace_root/project-bridge/config/server.json.example" ]; then
    cp -a "$workspace_root/project-bridge/config/server.json.example" "$server_base"
  fi
  if [ -f "$server_base" ]; then
    jq \
      --arg id "$repo_name" \
      --arg pname "$ORG_CFG_DISPLAY_NAME" \
      --arg pslug "$ORG_CFG_APP_SLUG" \
      --arg ver "$ORG_CFG_VERSION" \
      --argjson sp "${ORG_CFG_SERVER_PORT:-3001}" \
      --arg proot "$ORG_CFG_PROJECT_ROOT" \
      --arg sdir "$ORG_CFG_STATE_DIR" \
      '
      .server.port = $sp
      | .server.projectRoot = $proot
      | .server.stateDir = $sdir
      | .apps[0].id = $id
      | .apps[0].name = $pname
      | .apps[0].slug = $pslug
      | .apps[0].app.name = $pname
      | .apps[0].app.slug = $pslug
      | .apps[0].app.version = $ver
      | .apps[0].source = { "path": "." }
      ' "$server_base" > "$repo_path/config/server.json"
  else
    warn "No server.json.example in template; skipped config/server.json."
  fi

  tf_src="$workspace_root/project-bridge/terraform"
  if [ -f "$tf_src/main.tf" ]; then
    echoc cyan "Vendoring project-bridge/terraform → $repo_path/terraform (for mtx deploy)..."
    mkdir -p "$repo_path/terraform"
    if command -v rsync &>/dev/null; then
      rsync -a \
        --exclude='.terraform' \
        --exclude='.terraform.lock.hcl' \
        --exclude='terraform.tfstate' \
        --exclude='terraform.tfstate.*' \
        --exclude='*.backup' \
        "$tf_src/" "$repo_path/terraform/"
    else
      cp -a "$tf_src/." "$repo_path/terraform/"
      rm -rf "$repo_path/terraform/.terraform" 2>/dev/null || true
      rm -f "$repo_path/terraform/terraform.tfstate" "$repo_path/terraform"/terraform.tfstate.* 2>/dev/null || true
    fi
    echoc dim "terraform/ uses ../config/app.json — run terraform init on first mtx deploy."
  else
    echoc yellow "Sibling project-bridge/terraform not found at $tf_src — skipped. Place a project-bridge checkout next to this workspace to vendor terraform/."
  fi

  gitignore="$repo_path/.gitignore"
  if [ -f "$gitignore" ] && ! grep -qE '^\.terraform/?$|terraform/terraform\.tfstate' "$gitignore" 2>/dev/null; then
    {
      echo ""
      echo "# Terraform (mtx deploy — local state; do not commit)"
      echo ".terraform/"
      echo ".terraform.lock.hcl"
      echo "terraform/.terraform/"
      echo "terraform/terraform.tfstate"
      echo "terraform/terraform.tfstate.*"
    } >> "$gitignore"
  fi
  if [ -f "$gitignore" ] && ! grep -q 'targets/server/dist' "$gitignore" 2>/dev/null; then
    {
      echo ""
      echo "# Unified server dist (mirrored from project-bridge by npm run build:server)"
      echo "targets/server/dist/"
    } >> "$gitignore"
  fi
  if [ -f "$gitignore" ] && ! grep -q 'targets/server/npm-packs' "$gitignore" 2>/dev/null; then
    {
      echo ""
      echo "# Packed workspace tarballs (npm run prepare:railway); upload with railway up"
      echo "targets/server/npm-packs/"
    } >> "$gitignore"
  fi
  if [ -f "$gitignore" ] && ! grep -q 'targets/server/runtime' "$gitignore" 2>/dev/null; then
    {
      echo ""
      echo "# Legacy: mirrored node_modules (older prepare:railway)"
      echo "targets/server/runtime/"
    } >> "$gitignore"
  fi
}

# Wire package.json + railway.json so org repos run the full unified server build via sibling (or vendor) project-bridge.
mtx_org_merge_host_into_package_json() {
  local repo_path="$1" workspace_root="$2"
  local pkg="$repo_path/package.json" pb
  workspace_root="$(cd "$workspace_root" && pwd -P)"
  pb="$workspace_root/project-bridge"
  [ -f "$pkg" ] || return 0
  if [ ! -f "$repo_path/scripts/org-build-server.sh" ]; then
    warn "scripts/org-build-server.sh missing from template; cannot wire build:server."
    return 1
  fi
  if [ ! -f "$repo_path/scripts/org-dev-server.sh" ]; then
    warn "scripts/org-dev-server.sh missing from template; cannot wire dev."
    return 1
  fi
  if [ ! -f "$repo_path/scripts/railway-build.sh" ]; then
    warn "scripts/railway-build.sh missing from template."
    return 1
  fi
  if [ ! -f "$repo_path/scripts/prepare-railway-artifact.sh" ] || [ ! -f "$repo_path/scripts/generate-railway-deploy-manifest.sh" ]; then
    warn "scripts/prepare-railway-artifact.sh or generate-railway-deploy-manifest.sh missing from template."
    return 1
  fi
  if [ ! -f "$repo_path/scripts/railway-ci-install.sh" ]; then
    warn "scripts/railway-ci-install.sh missing from template."
    return 1
  fi
  if [ ! -f "$repo_path/package.deploy.json" ] || [ ! -f "$repo_path/package-lock.deploy.json" ]; then
    warn "package.deploy.json or package-lock.deploy.json missing from template."
    return 1
  fi
  chmod +x "$repo_path/scripts/org-build-server.sh" "$repo_path/scripts/org-dev-server.sh" \
    "$repo_path/scripts/railway-build.sh" \
    "$repo_path/scripts/railway-ci-install.sh" \
    "$repo_path/scripts/prepare-railway-artifact.sh" \
    "$repo_path/scripts/generate-railway-deploy-manifest.sh"
  if ! command -v jq &>/dev/null; then
    warn "jq required to merge org host into package.json"
    return 1
  fi
  jq \
    '
    .dependencies = ((.dependencies // {}) | del(.projectb))
    | .dependencies["@meanwhile-together/shared"] = "file:../project-bridge/shared"
    | .dependencies["@meanwhile-together/ui"] = "file:../project-bridge/ui"
    | .devDependencies = ((.devDependencies // {}) + {"@meanwhile-together/engine": "file:../project-bridge/engine"})
    | .scripts["prepare:railway"] = "bash scripts/prepare-railway-artifact.sh"
    | .scripts["dev"] = "bash scripts/org-dev-server.sh"
    | .scripts["build:server"] = "bash scripts/org-build-server.sh"
    | .scripts["build:backend-server"] = "npm run build:server"
    | .scripts = ((.scripts // {}) | del(.preinstall))
    ' "$pkg" > "${pkg}.tmp" && mv "${pkg}.tmp" "$pkg"

  if [ -f "$pb/railway.json" ]; then
    jq '
      .build.buildCommand = "bash scripts/railway-build.sh"
      | .deploy.startCommand = "node targets/server/dist/index.js"
    ' "$pb/railway.json" > "$repo_path/railway.json"
  else
    jq -n \
      --arg schema "https://railway.app/railway.schema.json" \
      '{
        "$schema": $schema,
        build: { builder: "RAILPACK", buildCommand: "bash scripts/railway-build.sh" },
        deploy: { startCommand: "node targets/server/dist/index.js", restartPolicyType: "ON_FAILURE", restartPolicyMaxRetries: 10 }
      }' > "$repo_path/railway.json"
  fi
}

update_repo_metadata_from_template() {
  local dir="$1"
  local pkg_json="$dir/package.json"
  local readme="$dir/README.md"
  local desc_line readme_intro next_extra step3
  desc_line="${MTX_REPO_PACKAGE_DESC:-${MTX_KIND_LABEL} payload: ${NEW_APP_NAME} (repo ${REPO_NAME}, template ${TEMPLATE_REPO})}"
  readme_intro="${MTX_KIND_LABEL} payload for **$NEW_APP_NAME**."
  next_extra=""
  step3="3. Register in project-bridge \`config/server.json\` (top-level \`apps\` array) with \`source.git\` pointing at this repo."

  case "${MTX_REPO_PREFIX:-}" in
    template-*)
      readme_intro="Forkable **payload template** repo (\`template-*\` is for payload scaffolds only). Point \`MTX_PAYLOAD_TEMPLATE_REPO\` or \`MTX_TEMPLATE_SOURCE_REPO\` here so \`mtx create payload\` clones from your scaffold."
      ;;
    org-*)
      readme_intro="Organization product repo (**org-***): includes \`config/app.json\`, \`config/deploy.json\`, and (when a sibling \`project-bridge\` exists) \`terraform/\` so \`mtx deploy\` can provision Railway from this tree."
      step3="3. **Shared host (optional):** Add this repo to a central project-bridge \`config/server.json\` with \`source.git\` if you are not deploying this tree as the unified server."
      next_extra="

4. **Local dev** — \`npm run dev\` runs **project-bridge**’s \`npm run dev\` with this repo’s \`config/\` synced in; project-bridge \`config/\` is **restored** when dev exits (Ctrl+C).  
5. **Standalone deploy** — Same local project-bridge checkout as above. \`mtx deploy\` runs \`npm run prepare:railway\` automatically (unified server dist, npm-packs, deploy manifests) before \`railway up\`. You can still run \`npm run prepare:railway\` alone to verify the bundle."
      ;;
  esac

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

  local created_line
  if [ -n "${MTX_TEMPLATE_SNAPSHOT_FROM:-}" ]; then
    created_line="Snapshotted from payload working tree at \`${MTX_TEMPLATE_SNAPSHOT_FROM}\` via \`${MTX_CREATE_CMD}\` (run from that payload root)."
  else
    created_line="Created by \`${MTX_CREATE_CMD}\` from template \`${TEMPLATE_REPO}\`."
  fi

  cat > "$readme" <<EOF
# $REPO_NAME

$readme_intro

$created_line

## Next steps

1. Install dependencies:
   \`\`\`bash
   npm install
   \`\`\`
2. Build:
   \`\`\`bash
   npm run build
   \`\`\`
$step3$next_extra
EOF
}

# Snapshot a payload working tree into a new directory (fresh template-* repo contents).
mtx_create_copy_payload_snapshot_to() {
  local src="$1" dst="$2"
  mkdir -p "$dst"
  if command -v rsync &>/dev/null; then
    rsync -a --delete \
      --exclude=.git \
      --exclude=node_modules \
      --exclude=dist \
      --exclude=build \
      --exclude=.next \
      --exclude=coverage \
      --exclude=.turbo \
      "$src/" "$dst/"
  else
    warn "rsync not found; using cp with manual excludes (install rsync for more reliable snapshots)."
    mkdir -p "$dst"
    shopt -s dotglob nullglob
    local p base
    for p in "$src"/* "$src"/.[!.]* "$src"/..?*; do
      [ -e "$p" ] || continue
      base=$(basename "$p")
      case "$base" in .git|node_modules|dist|build|.next|coverage|.turbo) continue ;; esac
      cp -a "$p" "$dst/"
    done
    shopt -u dotglob nullglob
  fi
}

# Shared: set package description, rewrite README/package.json, GitHub push, snippet.
# Expects globals: REPO_PATH REPO_NAME NEW_APP_NAME APP_SLUG GITHUB_ORG MTX_CREATE_CMD MTX_KIND_LABEL
# MTX_REPO_PREFIX TEMPLATE_REPO; optional MTX_TEMPLATE_SNAPSHOT_FROM, MTX_CREATE_SOURCE_NOTE.
mtx_create_apply_metadata_and_github_publish() {
  export MTX_REPO_PACKAGE_DESC=""
  case "${MTX_REPO_PREFIX}" in
    template-*)
      if [ -n "${MTX_TEMPLATE_SNAPSHOT_FROM:-}" ]; then
        MTX_REPO_PACKAGE_DESC="Forkable payload template: ${NEW_APP_NAME} (repo ${REPO_NAME}; snapshotted from ${MTX_TEMPLATE_SNAPSHOT_FROM})"
      else
        MTX_REPO_PACKAGE_DESC="Forkable payload template: ${NEW_APP_NAME} (repo ${REPO_NAME}; scaffolded from ${TEMPLATE_REPO})"
      fi
      ;;
    *)
      MTX_REPO_PACKAGE_DESC="${MTX_KIND_LABEL} payload: ${NEW_APP_NAME} (repo ${REPO_NAME}, template ${TEMPLATE_REPO})"
      ;;
  esac
  export MTX_REPO_PACKAGE_DESC

  local ref_note="${MTX_CREATE_SOURCE_NOTE:-$TEMPLATE_REPO}"

  echoc cyan "Applying package name and metadata..."
  update_repo_metadata_from_template "$REPO_PATH"
  echo ""

  if [ "${MTX_CREATE_SKIP_GITHUB:-}" = "1" ]; then
    mtx_create_local_git_commit_initial "$REPO_PATH" "${MTX_CREATE_CMD}: initialize ${REPO_NAME} from ${ref_note} (local only)"
    echoc yellow "Skipped GitHub (MTX_CREATE_SKIP_GITHUB=1). Push from $REPO_PATH when the remote exists."
    echoc dim "Local path: $REPO_PATH"
    mtx_create_print_server_json_snippet "$REPO_NAME" "$NEW_APP_NAME" "$APP_SLUG" "$GITHUB_ORG" "$REPO_NAME"
    exit 0
  fi

  if ! command -v gh &>/dev/null; then
    mtx_create_local_git_commit_initial "$REPO_PATH" "${MTX_CREATE_CMD}: initialize ${REPO_NAME} from ${ref_note}"
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
      git commit -q -m "${MTX_CREATE_CMD}: initialize ${REPO_NAME} from ${ref_note}"
    fi

    if ! git rev-parse -q --verify HEAD >/dev/null; then
      git add -A
      git commit -q --allow-empty -m "${MTX_CREATE_CMD}: initialize ${REPO_NAME} from ${ref_note}"
    fi

    if ! gh repo view "$GITHUB_ORG/$REPO_NAME" &>/dev/null; then
      echoc cyan "Creating GitHub repository $GITHUB_ORG/$REPO_NAME and pushing main..."
      git remote remove origin 2>/dev/null || true
      gh repo create "$GITHUB_ORG/$REPO_NAME" --private \
        --description "${MTX_REPO_PACKAGE_DESC}" \
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

mtx_create_template_from_payload_run() {
  local WORKSPACE_ROOT GITHUB_ORG NEW_APP_NAME APP_SLUG REPO_PATH PAYLOAD_ROOT REPO_NAME MTX_ABS
  : "${MTX_REPO_PREFIX:?Set MTX_REPO_PREFIX (template-)}"
  : "${MTX_KIND_LABEL:?Set MTX_KIND_LABEL}"
  : "${MTX_CREATE_CMD:?Set MTX_CREATE_CMD}"

  PAYLOAD_ROOT="$(pwd -P)"
  if [ ! -f "$PAYLOAD_ROOT/package.json" ]; then
    error "mtx create template must be run from a payload repo root (no package.json in $PAYLOAD_ROOT)."
    exit 1
  fi

  MTX_ABS="$(cd "$MTX_ROOT" && pwd -P)"
  if [ "$PAYLOAD_ROOT" = "$MTX_ABS" ]; then
    error "Run from a payload directory, not the MTX repo root."
    exit 1
  fi

  if ! command -v git &>/dev/null; then
    warn "git is required."
    exit 1
  fi

  WORKSPACE_ROOT="${MTX_WORKSPACE_ROOT:-$(cd "$MTX_ROOT/.." && pwd)}"
  GITHUB_ORG="${MTX_GITHUB_ORG:-Meanwhile-Together}"
  export TEMPLATE_REPO="${MTX_PAYLOAD_TEMPLATE_REPO:-template-basic}"

  echoc cyan "Create template-* repo from current payload tree"
  echoc dim "Payload root: $PAYLOAD_ROOT"
  echo ""

  NEW_APP_NAME=""
  if [ $# -gt 0 ]; then
    NEW_APP_NAME=$(printf '%s' "$(echo "$*" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')")
  fi
  if [ -z "$NEW_APP_NAME" ]; then
    read -rp "$(echo -e "${bold:-}Name for the new template (display name):${reset:-} ")" NEW_APP_NAME
    NEW_APP_NAME="${NEW_APP_NAME#"${NEW_APP_NAME%%[![:space:]]*}"}"
    NEW_APP_NAME="${NEW_APP_NAME%"${NEW_APP_NAME##*[![:space:]]}"}"
    if [ -z "$NEW_APP_NAME" ]; then
      warn "No name entered. Exiting."
      exit 0
    fi
  else
    echoc dim "Template name (from command line): $(color yellow "$NEW_APP_NAME")"
    echo ""
  fi

  APP_SLUG=$(slugify "$NEW_APP_NAME")
  [ -z "$APP_SLUG" ] && APP_SLUG="app"
  REPO_NAME=$(ensure_mtx_repo_prefix "$APP_SLUG" "$MTX_REPO_PREFIX")
  WORKSPACE_ROOT="$(cd "$WORKSPACE_ROOT" && pwd -P)"
  REPO_PATH="$WORKSPACE_ROOT/$REPO_NAME"

  if [ "$PAYLOAD_ROOT" = "$REPO_PATH" ]; then
    error "New template path would be the same as the current directory. Choose a different name or run from another payload."
    exit 1
  fi

  echo ""
  echoc cyan "Workspace: $WORKSPACE_ROOT"
  echoc cyan "New template repo: $(color yellow "$REPO_NAME")"
  echoc dim "Command: $MTX_CREATE_CMD"
  echo ""

  if [ -d "$REPO_PATH" ] && [ -f "$REPO_PATH/package.json" ]; then
    echoc cyan "Updating existing directory at $REPO_PATH (re-snapshot from payload)."
  elif [ -d "$REPO_PATH" ]; then
    warn "Directory $REPO_PATH exists but has no package.json. Remove it or choose another name."
    exit 1
  fi

  echoc cyan "Copying payload tree into $REPO_PATH (excluding .git, node_modules, dist, …)..."
  mtx_create_copy_payload_snapshot_to "$PAYLOAD_ROOT" "$REPO_PATH"
  rm -rf "$REPO_PATH/.git"
  echo ""

  export MTX_TEMPLATE_SNAPSHOT_FROM="$PAYLOAD_ROOT"
  export MTX_CREATE_SOURCE_NOTE="payload at $PAYLOAD_ROOT"
  mtx_create_apply_metadata_and_github_publish
}

mtx_create_from_template_run() {
  local WORKSPACE_ROOT GITHUB_ORG TEMPLATE_REPO TEMPLATE_URL LOCAL_TEMPLATE_PATH
  local NEW_APP_NAME APP_SLUG REPO_PATH

  : "${MTX_REPO_PREFIX:?Set MTX_REPO_PREFIX (payload-, org-, or template-)}"
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

  echoc cyan "Create new $(echo "$MTX_KIND_LABEL" | tr '[:upper:]' '[:lower:]') repo (${MTX_REPO_PREFIX}*)"
  echo ""
  NEW_APP_NAME=""
  if [ $# -gt 0 ]; then
    NEW_APP_NAME=$(printf '%s' "$(echo "$*" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')")
  fi
  if [ -z "$NEW_APP_NAME" ]; then
    if mtx_create_is_org_flow; then
      read -rp "$(echo -e "${bold:-}Organization / product display name:${reset:-} ")" NEW_APP_NAME
    else
      read -rp "$(echo -e "${bold:-}App display name (new payload repo):${reset:-} ")" NEW_APP_NAME
    fi
    NEW_APP_NAME="${NEW_APP_NAME#"${NEW_APP_NAME%%[![:space:]]*}"}"
    NEW_APP_NAME="${NEW_APP_NAME%"${NEW_APP_NAME##*[![:space:]]}"}"
    if [ -z "$NEW_APP_NAME" ]; then
      warn "No name entered. Exiting."
      exit 0
    fi
  else
    echoc dim "Display name (from command line): $(color yellow "$NEW_APP_NAME")"
    echo ""
  fi

  if mtx_create_is_org_flow; then
    local default_org_repo
    default_org_repo=$(ensure_mtx_repo_prefix "$(slugify "$NEW_APP_NAME")" "org-")
    if [ -t 0 ] && [ -t 1 ] && [ "${MTX_CREATE_NONINTERACTIVE:-}" != "1" ]; then
      read -rp "$(echo -e "${bold:-}Repository name (org-* folder + GitHub repo) [${default_org_repo}]:${reset:-} ")" _org_repo_in
      _org_repo_in="${_org_repo_in:-$default_org_repo}"
      REPO_NAME=$(ensure_mtx_repo_prefix "$(slugify "${_org_repo_in#org-}")" "org-")
    else
      REPO_NAME="${MTX_ORG_REPO_NAME:-$default_org_repo}"
      REPO_NAME=$(ensure_mtx_repo_prefix "$(slugify "${REPO_NAME#org-}")" "org-")
    fi
    mtx_org_collect_host_config "$REPO_NAME" "$NEW_APP_NAME" "$GITHUB_ORG"
  else
    APP_SLUG=$(slugify "$NEW_APP_NAME")
    [ -z "$APP_SLUG" ] && APP_SLUG="app"
    REPO_NAME=$(ensure_mtx_repo_prefix "$APP_SLUG" "$MTX_REPO_PREFIX")
  fi
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

  unset MTX_TEMPLATE_SNAPSHOT_FROM
  export MTX_CREATE_SOURCE_NOTE="$TEMPLATE_REPO"

  if mtx_create_is_org_flow; then
    mtx_org_scaffold_deploy_config_surface "$REPO_PATH" "$REPO_NAME" "$NEW_APP_NAME" "$WORKSPACE_ROOT" "$GITHUB_ORG" || {
      warn "Org deploy config scaffold had warnings; check config/ and terraform/."
    }
    mtx_org_merge_host_into_package_json "$REPO_PATH" "$WORKSPACE_ROOT" || {
      warn "Could not wire package.json to project-bridge (jq or scripts/org-build-server.sh missing)."
    }
  fi

  mtx_create_apply_metadata_and_github_publish
}
