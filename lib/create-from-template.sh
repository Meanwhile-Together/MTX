# Shared: scaffold a GitHub repo from a template with a fixed name prefix (payload-, org-, or template-).
# Loaded only from mtx create <payload|org|template> entrypoints (create/*.sh or create.sh legacy path) — NOT from includes/ (mtx auto-sources includes/*.sh at boot).
# Callers must set MTX_ROOT to the MTX repo root before sourcing this file.
# Callers set: MTX_REPO_PREFIX, MTX_TEMPLATE_REPO, MTX_KIND_LABEL, MTX_CREATE_CMD, MTX_CREATE_VARIANT (org|payload)
# Repo prefixes: payload-, org-, template- (`template-*` = forkable snapshots from `mtx create template`; see https://github.com/Meanwhile-Together/project-bridge/blob/main/docs/MTX_SCAFFOLDING_MODEL.md).
# Optional: MTX_WORKSPACE_ROOT, MTX_GITHUB_ORG, MTX_CREATE_SKIP_GITHUB=1 (local git + snippet only; no gh).
# Standalone migration (payload flow): disabled when cwd is under workspace sibling `payload-*` or `org-*`
# (avoids migrating the wrong app when `mtx create payload` is run from inside another repo). Override with
# MTX_CREATE_ALLOW_STANDALONE_MIGRATE=1. Each successful apply writes `.mtx-from-template` for tooling.
# Optional CLI name: mtx_create_from_template_run "$@" — if any args are given, they are joined with
# spaces (trimmed): payload flow uses that as the app display name; org flow uses it as a plain-English
# organization title (slugified to org-* for the repo; leading org- stripped first so it is never doubled).
# Otherwise the script prompts interactively (org: plain-English name; payload: display name).
# Org (org-*): host config (app.json / server.json placeholders, URLs, owner) is filled from the org repo id and
# MTX_GITHUB_ORG — no TTY prompts for those fields. Override any field with MTX_ORG_DISPLAY_NAME, MTX_ORG_APP_SLUG,
# MTX_ORG_OWNER, MTX_ORG_VERSION, MTX_ORG_DEV_PORT, MTX_ORG_DEV_URL, MTX_ORG_STAGING_PORT, MTX_ORG_STAGING_URL,
# MTX_ORG_PROD_PORT, MTX_ORG_PROD_URL, MTX_ORG_DEPLOY_PROJECT_ID, MTX_ORG_SERVER_PORT, MTX_ORG_PROJECT_ROOT,
# MTX_ORG_STATE_DIR. Non-interactive org create: set MTX_ORG_REPO_NAME (plain English or slug; optional org-
# prefix, never doubled) or pass the same on the command line; optional MTX_ORG_DISPLAY_NAME overrides app.json name.
# Secrets stay in backend.example.json / .env — not prompted.
# Default clone sources: template-payload (`mtx create payload`), template-org (`mtx create org`, replacing the legacy template-basic on 2026-04-20 — rule-of-law §1 Config triad). Override with MTX_PAYLOAD_TEMPLATE_REPO / MTX_ORG_TEMPLATE_REPO. MTX_TEMPLATE_SOURCE_REPO is documented for pointing `mtx create payload` at a custom template-* snapshot.
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

# Export: MTX_CREATE_RUN_CONTEXT — workspace_root | mtx_repo | org_tree | flat_payload_app | other
mtx_create_classify_run_context() {
  local cwd="$1" ws="$2" mtx_r="$3"
  if ! cwd="$(cd "$cwd" && pwd -P 2>/dev/null)"; then
    MTX_CREATE_RUN_CONTEXT="other"
    return 0
  fi
  ws="$(cd "$ws" && pwd -P)"
  mtx_r="$(cd "$mtx_r" && pwd -P)"
  if [ "$cwd" = "$ws" ]; then
    MTX_CREATE_RUN_CONTEXT="workspace_root"
  elif [ "$cwd" = "$mtx_r" ]; then
    MTX_CREATE_RUN_CONTEXT="mtx_repo"
  elif [[ "$cwd" == "$ws"/org-* ]]; then
    MTX_CREATE_RUN_CONTEXT="org_tree"
  elif [[ "$cwd" == "$ws"/payload-* ]]; then
    MTX_CREATE_RUN_CONTEXT="flat_payload_app"
  else
    MTX_CREATE_RUN_CONTEXT="other"
  fi
}

# Return 0 if standalone→payloads/<slug> migration is allowed; 1 to skip (safe default inside workspace org/payload trees).
mtx_create_payload_migrate_standalone_ok() {
  local cwd="$1" ws="$2"
  case "${MTX_CREATE_ALLOW_STANDALONE_MIGRATE:-}" in
    1 | true | yes) return 0 ;;
  esac
  cwd="$(cd "$cwd" && pwd -P)"
  ws="$(cd "$ws" && pwd -P)"
  case "$cwd" in
    "$ws"/payload-* | "$ws"/org-*)
      return 1
      ;;
  esac
  return 0
}

mtx_create_write_scaffold_marker() {
  local repo_path="$1" ts ctx
  repo_path="$(cd "$repo_path" && pwd -P)"
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u +%Y-%m-%dT%H:%MZ)"
  ctx="${MTX_CREATE_RUN_CONTEXT:-}"
  cat > "$repo_path/.mtx-from-template" <<EOF
# MTX scaffold marker — mtx create applied template/snapshot metadata here. Importers may treat absence as
# "never bootstrapped by MTX" and presence as "first-pass naming/README/package updates already applied".
MTX_SCAFFOLD=1
MTX_SCAFFOLD_AT=$ts
MTX_REPO_NAME=$REPO_NAME
MTX_TEMPLATE_REPO=$TEMPLATE_REPO
MTX_CREATE_CMD=$MTX_CREATE_CMD
MTX_REPO_PREFIX=$MTX_REPO_PREFIX
MTX_CREATE_RUN_CONTEXT=$ctx
EOF
}

mtx_detect_standalone_react_root() {
  local root="$1"
  local pkg="$root/package.json"
  [ -f "$pkg" ] || return 1
  # Must look like a React app root.
  if ! grep -qE '"react"\s*:' "$pkg"; then
    return 1
  fi
  # Exclude already-standard host/payload roots.
  [ -d "$root/config" ] && [ -f "$root/config/app.json" ] && return 1
  [ -d "$root/terraform" ] && return 1
  [ -d "$root/payloads" ] && return 1
  return 0
}

mtx_payload_migrate_standalone_into_repo() {
  local src="$1" repo_path="$2" app_slug="$3"
  local target="$repo_path/payloads/$app_slug"
  local move_source="${MTX_CREATE_MOVE_SOURCE:-1}"
  mkdir -p "$target"
  if command -v rsync &>/dev/null; then
    rsync -a --delete \
      --exclude=.git \
      --exclude=node_modules \
      --exclude=dist \
      --exclude=build \
      --exclude=.next \
      --exclude=coverage \
      --exclude=.turbo \
      --exclude=.mtx-import \
      "$src/" "$target/"
  else
    warn "rsync not found; using cp fallback for payload migration."
    shopt -s dotglob nullglob
    local p base
    for p in "$src"/* "$src"/.[!.]* "$src"/..?*; do
      [ -e "$p" ] || continue
      base=$(basename "$p")
      case "$base" in .git|node_modules|dist|build|.next|coverage|.turbo|.mtx-import) continue ;; esac
      cp -a "$p" "$target/"
    done
    shopt -u dotglob nullglob
  fi

  cat > "$target/README.mtx-migrated.md" <<EOF
# Migrated by mtx create payload

This payload content was migrated from standalone React app root:
\`$src\`

Target payload path:
\`payloads/$app_slug\`
EOF

  # Default behavior is to move source content after successful migration.
  # Set MTX_CREATE_MOVE_SOURCE=0 to keep original app root untouched.
  if [ "$move_source" = "1" ] || [ "$move_source" = "true" ]; then
    if [ -d "$src" ] && [ "$src" != "$repo_path" ]; then
      shopt -s dotglob nullglob
      local p base
      for p in "$src"/* "$src"/.[!.]* "$src"/..?*; do
        [ -e "$p" ] || continue
        base=$(basename "$p")
        case "$base" in .|..|.git) continue ;; esac
        rm -rf "$p"
      done
      shopt -u dotglob nullglob
      cat > "$src/README.mtx-moved.md" <<EOF
# App moved by mtx create payload

This standalone app was moved into:
\`$repo_path/payloads/$app_slug\`

Set \`MTX_CREATE_MOVE_SOURCE=0\` before running create if you prefer copy-only behavior.
EOF
    fi
  fi
}

slugify() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/-\{2,\}/-/g' | sed 's/^-*\|-*$//g'
}

# Strip leading org- (case-insensitive), repeatedly, so org-org-hello → hello (repo becomes org-hello).
mtx_strip_leading_org_prefix() {
  local s="$1" lower
  while [ -n "$s" ]; do
    lower=$(printf '%s' "$s" | tr '[:upper:]' '[:lower:]')
    case "$lower" in
      org-*) s="${s:4}" ;;
      *) break ;;
    esac
  done
  printf '%s' "$s"
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
    # gh repo create --push uses git over HTTPS; without this, git may not use gh's token → "Repository not found".
    if ! gh auth setup-git &>/dev/null; then
      echoc dim "gh auth setup-git skipped or failed (git may still work if credentials are configured)."
    fi
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
      gh auth setup-git &>/dev/null || true
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
  # (Org-shape refusal for payload flow happens after this returns — see mtx_create_payload_refuse_org_shaped_template.)

  echoc yellow "No local template at: $local_path"
  echoc dim "Expected a sibling of MTX: $ws/$repo (clone the template repo there; for orgs the default is 'template-org' — legacy 'template-basic' still works via MTX_ORG_TEMPLATE_REPO=template-basic), or set MTX_WORKSPACE_ROOT."
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

# Refuse an org-shaped template when the caller is `mtx create payload`.
# Root cause: historical misuse of `template-basic` / `template-org` (org-shaped) as MTX_PAYLOAD_TEMPLATE_REPO
# produced 25+ org-shaped `payload-*` repos with `payloads/`, `prepare:railway`, unified-server wiring
# (rule-of-law §1 2026-04-18 bullet). Detect the org markers up front and exit before scaffolding.
# Markers we refuse on (any one is enough):
#   - config/            (host has config/, payload does not)
#   - payloads/          (org ships payloads/, payload is itself a single app)
#   - terraform/         (deploy root only)
#   - package.json with scripts.prepare:railway (host deploy wiring)
# This tripwire intentionally does NOT run for `mtx create org` (org templates MUST have these).
# Stamp identity into a freshly-created payload's config/app.json (rule-of-law §1 2026-04-20
# — config triad: payload identity lives in the payload's own config/app.json).
# If the template did not ship config/app.json, scaffold a minimal one.
mtx_payload_stamp_identity() {
  local repo_path="$1" repo_name="$2" app_slug="$3" app_display_name="$4"
  if ! command -v jq &>/dev/null; then
    warn "jq is required to stamp payload identity into config/app.json (install jq)."
    return 1
  fi
  mkdir -p "$repo_path/config"
  local app_json="$repo_path/config/app.json"
  if [ ! -f "$app_json" ]; then
    warn "Template did not ship config/app.json; scaffolding a minimal one."
    cat > "$app_json" <<'JSON'
{
  "app": { "name": "Payload", "slug": "payload", "version": "1.0.0" },
  "ai": { "inferenceMode": "local", "enableLogging": false },
  "chatbots": [],
  "development": { "port": 3001, "url": "http://localhost" },
  "staging":     { "port": 3001, "url": "https://staging.example.com" },
  "production":  { "port": 3001, "url": "https://api.example.com" }
}
JSON
  fi
  local ver
  ver=$(jq -r '.version // "1.0.0"' "$repo_path/package.json" 2>/dev/null || echo "1.0.0")
  [ -z "$ver" ] && ver="1.0.0"
  jq \
    --arg name "$app_display_name" \
    --arg slug "$app_slug" \
    --arg ver "$ver" \
    '
    .app.name = $name
    | .app.slug = $slug
    | .app.version = $ver
    ' "$app_json" > "${app_json}.tmp" && mv "${app_json}.tmp" "$app_json"
  echoc dim "Stamped payload identity in $app_json (name=$app_display_name, slug=$app_slug, version=$ver)."
  return 0
}

mtx_create_payload_refuse_org_shaped_template() {
  [ "${MTX_CREATE_VARIANT:-}" = "payload" ] || return 0
  local tpl_path="$1" tpl_repo="$2"
  [ -d "$tpl_path" ] || return 0
  local -a offenders=()
  # Config triad (rule-of-law §1 2026-04-20): a payload MAY ship config/app.json (its own identity)
  # but MUST NOT ship org-only config files. Flag specific offenders, not the config/ dir itself.
  [ -f "$tpl_path/config/org.json" ] && offenders+=("config/org.json")
  [ -f "$tpl_path/config/server.json" ] && offenders+=("config/server.json")
  [ -f "$tpl_path/config/server.json.example" ] && offenders+=("config/server.json.example")
  [ -f "$tpl_path/config/backend.json" ] && offenders+=("config/backend.json")
  [ -f "$tpl_path/config/backend.example.json" ] && offenders+=("config/backend.example.json")
  [ -f "$tpl_path/config/deploy.json" ] && offenders+=("config/deploy.json")
  [ -f "$tpl_path/config/deploy.example.json" ] && offenders+=("config/deploy.example.json")
  [ -f "$tpl_path/config/admin-grants.json" ] && offenders+=("config/admin-grants.json")
  [ -f "$tpl_path/config/admin-grants.example.json" ] && offenders+=("config/admin-grants.example.json")
  [ -d "$tpl_path/payloads" ] && offenders+=("payloads/")
  [ -d "$tpl_path/terraform" ] && offenders+=("terraform/")
  if [ -f "$tpl_path/package.json" ] && command -v jq &>/dev/null; then
    if jq -e '.scripts["prepare:railway"] // empty' "$tpl_path/package.json" &>/dev/null; then
      offenders+=("package.json scripts.\"prepare:railway\"")
    fi
  fi
  [ "${#offenders[@]}" -eq 0 ] && return 0
  error "Refusing to scaffold a payload from org-shaped template '$tpl_repo' (found: ${offenders[*]})."
  echoc dim "Payload templates are single-app SPAs (vite.config at root, staticDir: dist). A payload MAY have config/app.json (its own identity) but NOT server.json/org.json/backend.json/deploy.json, payloads/, terraform/, or prepare:railway — if you meant to scaffold an org, run: mtx create org"
  echoc dim "To scaffold a payload, set MTX_PAYLOAD_TEMPLATE_REPO to a real payload template (default: template-payload), or snapshot an existing payload with: mtx create template"
  echoc dim "See project-bridge/docs/rule-of-law.md §1 2026-04-18 (Org-shaped payload-*) and §1 2026-04-20 (config triad)."
  exit 1
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
  echoc cyan "Compatibility hints (wave1 validation/router baseline):"
  echo "  - Declare payload contract exports in payload-manifest entries (exports.views/api)."
  echo "  - Keep app routes deterministic; avoid dynamic wildcard patterns in manifest paths unless intentionally reviewed."
  echo "  - For protected views, use shared AuthContext gating helpers (canAccessView / useViewAuthorization)."
  echo "  - Enable strict startup checks in hosted environments with PAYLOAD_MANIFEST_STRICT=1."
  echo ""
}

# Org host config merged into template config files (secrets never prompted — use backend.example.json / env).
# Sets ORG_CFG_* and APP_SLUG from the org repo id and workspace GitHub org. No TTY prompts — override with MTX_ORG_* only.
# app.json name/slug/version are host placeholders until per-payload metadata exists (org repos are not a single app).
mtx_org_collect_host_config() {
  local repo_name="$1" github_org="$2"
  local default_slug
  default_slug=$(slugify "${repo_name#org-}")
  [ -z "$default_slug" ] && default_slug=$(slugify "$repo_name")

  ORG_CFG_DISPLAY_NAME="${MTX_ORG_DISPLAY_NAME:-$repo_name}"
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

  export ORG_CFG_DISPLAY_NAME ORG_CFG_APP_SLUG ORG_CFG_OWNER ORG_CFG_VERSION
  export ORG_CFG_DEV_PORT ORG_CFG_DEV_URL ORG_CFG_STAGING_PORT ORG_CFG_STAGING_URL ORG_CFG_PROD_PORT ORG_CFG_PROD_URL
  export ORG_CFG_DEPLOY_PROJECT_ID ORG_CFG_SERVER_PORT ORG_CFG_PROJECT_ROOT ORG_CFG_STATE_DIR
  APP_SLUG="$ORG_CFG_APP_SLUG"
}

# Org repos: same config surface as project-bridge (from template) + terraform/ vendored from sibling project-bridge.
mtx_org_scaffold_deploy_config_surface() {
  local repo_path="$1" repo_name="$2" workspace_root="$3"
  local tf_src gitignore app_base deploy_base server_base

  if ! command -v jq &>/dev/null; then
    warn "jq is required to merge org host config (install jq)."
    return 1
  fi

  mkdir -p "$repo_path/config"
  workspace_root="$(cd "$workspace_root" && pwd -P)"

  # Config triad (rule-of-law §1 2026-04-20): org identity lives in config/org.json.
  # If the template still ships legacy config/app.json, rename it in-place to config/org.json
  # (converting top-level "app" key → "org"), then stamp the new org's identity.
  local org_base="$repo_path/config/org.json"
  local legacy_app_base="$repo_path/config/app.json"
  if [ ! -f "$org_base" ] && [ -f "$legacy_app_base" ]; then
    warn "Template ${MTX_TEMPLATE_REPO:-<unknown>} ships legacy config/app.json (expected config/org.json). Converting in place."
    jq 'if .app then . + {org: .app} | del(.app) else . end' "$legacy_app_base" > "$org_base" \
      && rm -f "$legacy_app_base"
  fi
  if [ ! -f "$org_base" ]; then
    error "Template ${MTX_TEMPLATE_REPO:-<unknown>} has no config/org.json. Org templates must ship a neutral org.json (org.{name,slug,owner,version}, env blocks, ai, chatbots)."
    echoc dim "Fix: add config/org.json to the org template (${MTX_ORG_TEMPLATE_REPO:-template-org}; legacy alias: template-basic). Reference: project-bridge/config/org.json.example."
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
    .org.name = $name
    | .org.slug = $slug
    | .org.owner = $owner
    | .org.version = $ver
    | .development.port = $devp
    | .development.url = $devu
    | .staging.port = $stp
    | .staging.url = $stu
    | .production.port = $prp
    | .production.url = $pru
    ' "$org_base" > "${org_base}.tmp" && mv "${org_base}.tmp" "$org_base"

  deploy_base="$repo_path/config/deploy.json"
  # Templates own their config/. No bridge fallback (see rule-of-law §1/§5/§6).
  # deploy.json is optional — the org can fill it in later once it has a Railway project.
  if [ -f "$deploy_base" ]; then
    jq --arg pid "$ORG_CFG_DEPLOY_PROJECT_ID" '.projectId = $pid' "$deploy_base" > "${deploy_base}.tmp" && mv "${deploy_base}.tmp" "$deploy_base"
  else
    echoc dim "Template has no config/deploy.json — skipped (operator can add one later to pin a Railway projectId)."
  fi

  server_base="$repo_path/config/server.json.example"
  # Templates own their config/ schema. No bridge fallback (see rule-of-law §1/§5/§6).
  # Config triad (§1 2026-04-20): server.json is pure routing — no .app blocks in apps[];
  # host mount lives at server.host; host identity is in config/org.json (written above).
  if [ -f "$server_base" ]; then
    jq \
      --argjson sp "${ORG_CFG_SERVER_PORT:-3001}" \
      --arg proot "$ORG_CFG_PROJECT_ROOT" \
      --arg sdir "$ORG_CFG_STATE_DIR" \
      '
      .server.port = $sp
      | .server.projectRoot = $proot
      | .server.stateDir = $sdir
      ' "$server_base" > "$repo_path/config/server.json"
  else
    error "Template ${MTX_TEMPLATE_REPO:-<unknown>} has no config/server.json.example. Org templates must ship a neutral server.json.example with server.host set and apps[] as a pure payload registry."
    echoc dim "Fix: add config/server.json.example to the org template. Reference shape: project-bridge/config/server.json.example."
    return 1
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
    if [ -f "$MTX_ROOT/lib/vendor-terraform-from-bridge.sh" ]; then
      bash "$MTX_ROOT/lib/vendor-terraform-from-bridge.sh" --write-digest "$repo_path" || true
    fi
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
      echo "terraform/.mtx-bridge-terraform.sha256"
    } >> "$gitignore"
  fi
  if [ -f "$gitignore" ] && ! grep -qF 'terraform/.mtx-bridge-terraform.sha256' "$gitignore" 2>/dev/null; then
    printf '\n# MTX: bridge terraform fingerprint (local; do not commit)\nterraform/.mtx-bridge-terraform.sha256\n' >> "$gitignore"
  fi
  if [ -f "$gitignore" ] && ! grep -q 'targets/server/runtime' "$gitignore" 2>/dev/null; then
    {
      echo ""
      echo "# Legacy: mirrored node_modules (older prepare:railway)"
      echo "targets/server/runtime/"
    } >> "$gitignore"
  fi
  if [ -f "$gitignore" ] && ! grep -qE '^\.env$|^\.env\.\*$' "$gitignore" 2>/dev/null; then
    {
      echo ""
      echo "# Local secrets (Railway / JWT / DB URLs — mtx deploy reads .env)"
      echo ".env"
      echo ".env.*"
      echo "!.env.example"
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
      | .deploy.startCommand = "PROJECT_ROOT=/app DISABLE_BROWSER_AUTOMATION=1 node targets/server/dist/index.js"
    ' "$pb/railway.json" > "$repo_path/railway.json"
  else
    jq -n \
      --arg schema "https://railway.app/railway.schema.json" \
      '{
        "$schema": $schema,
        build: { builder: "RAILPACK", buildCommand: "bash scripts/railway-build.sh" },
        deploy: { startCommand: "PROJECT_ROOT=/app DISABLE_BROWSER_AUTOMATION=1 node targets/server/dist/index.js", restartPolicyType: "ON_FAILURE", restartPolicyMaxRetries: 10 }
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
  mtx_create_write_scaffold_marker "$REPO_PATH"
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
    warn "GitHub create or push failed. The repo may exist empty on GitHub while the local push failed."
    echoc dim "Common fixes: gh auth setup-git (so git push uses your gh token); gh auth refresh; for SAML orgs authorize SSO at github.com/settings/applications; confirm write access to $GITHUB_ORG/$REPO_NAME."
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
  export TEMPLATE_REPO="${MTX_PAYLOAD_TEMPLATE_REPO:-template-payload}"

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
  mtx_create_classify_run_context "$PAYLOAD_ROOT" "$WORKSPACE_ROOT" "$MTX_ROOT"
  echoc dim "Run context: ${MTX_CREATE_RUN_CONTEXT:-unknown} (cwd: $PAYLOAD_ROOT)"
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
  local NEW_APP_NAME APP_SLUG REPO_PATH CREATE_CWD
  local MIGRATE_STANDALONE=0

  : "${MTX_REPO_PREFIX:?Set MTX_REPO_PREFIX (payload-, org-, or template-)}"
  : "${MTX_TEMPLATE_REPO:?Set MTX_TEMPLATE_REPO}"
  : "${MTX_KIND_LABEL:?Set MTX_KIND_LABEL}"
  : "${MTX_CREATE_CMD:?Set MTX_CREATE_CMD}"

  CREATE_CWD="$(pwd -P)"
  WORKSPACE_ROOT="${MTX_WORKSPACE_ROOT:-$(cd "$MTX_ROOT/.." && pwd)}"
  WORKSPACE_ROOT="$(cd "$WORKSPACE_ROOT" && pwd -P)"
  GITHUB_ORG="${MTX_GITHUB_ORG:-Meanwhile-Together}"
  TEMPLATE_REPO="$MTX_TEMPLATE_REPO"
  TEMPLATE_URL="https://github.com/${GITHUB_ORG}/${TEMPLATE_REPO}.git"
  LOCAL_TEMPLATE_PATH="$WORKSPACE_ROOT/$TEMPLATE_REPO"

  mtx_create_classify_run_context "$CREATE_CWD" "$WORKSPACE_ROOT" "$MTX_ROOT"

  if ! command -v git &>/dev/null; then
    warn "git is required for mtx create (template clone and commits)."
    exit 1
  fi

  mtx_create_ensure_template_available "$LOCAL_TEMPLATE_PATH" "$TEMPLATE_URL" "$TEMPLATE_REPO" "$WORKSPACE_ROOT"
  mtx_create_payload_refuse_org_shaped_template "$LOCAL_TEMPLATE_PATH" "$TEMPLATE_REPO"

  echoc cyan "Create new $(echo "$MTX_KIND_LABEL" | tr '[:upper:]' '[:lower:]') repo (${MTX_REPO_PREFIX}*)"
  echo ""
  NEW_APP_NAME=""
  if [ $# -gt 0 ]; then
    NEW_APP_NAME=$(printf '%s' "$(echo "$*" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')")
  fi
  if [ -z "$NEW_APP_NAME" ]; then
    if mtx_create_is_org_flow; then
      if [ "${MTX_CREATE_NONINTERACTIVE:-}" = "1" ] || [ ! -t 0 ] || [ ! -t 1 ]; then
        NEW_APP_NAME="${MTX_ORG_REPO_NAME:-}"
        if [ -z "$NEW_APP_NAME" ]; then
          warn "Non-interactive org create needs MTX_ORG_REPO_NAME or a plain-English / slug name on the command line."
          exit 1
        fi
      else
        echo ""
        echoc dim "GitHub and folder name will be org- plus a slug from your title (e.g. \"Hello World!\" → org-hello-world)."
        echoc dim "If you already type org- at the start, it is stripped once so it is never doubled."
        read -rp "$(echo -e "${bold:-}Organization name (plain English, e.g. Hello World!):${reset:-} ")" NEW_APP_NAME
      fi
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
    if mtx_create_is_org_flow; then
      echoc dim "Organization title (from command line): $(color yellow "$NEW_APP_NAME")"
    else
      echoc dim "Display name (from command line): $(color yellow "$NEW_APP_NAME")"
    fi
    echo ""
  fi

  if mtx_create_is_org_flow; then
    local org_slug_base
    org_slug_base=$(slugify "$(mtx_strip_leading_org_prefix "$NEW_APP_NAME")")
    if [ -z "$org_slug_base" ]; then
      warn "After slugifying the name, the repo slug was empty. Use letters or numbers in the organization title."
      exit 1
    fi
    REPO_NAME=$(ensure_mtx_repo_prefix "$org_slug_base" "org-")
    export MTX_ORG_DISPLAY_NAME="${MTX_ORG_DISPLAY_NAME:-$(mtx_strip_leading_org_prefix "$NEW_APP_NAME")}"
    mtx_org_collect_host_config "$REPO_NAME" "$GITHUB_ORG"
  else
    APP_SLUG=$(slugify "$NEW_APP_NAME")
    [ -z "$APP_SLUG" ] && APP_SLUG="app"
    REPO_NAME=$(ensure_mtx_repo_prefix "$APP_SLUG" "$MTX_REPO_PREFIX")
    if [ "${MTX_CREATE_VARIANT:-}" = "payload" ] && mtx_detect_standalone_react_root "$CREATE_CWD"; then
      if mtx_create_payload_migrate_standalone_ok "$CREATE_CWD" "$WORKSPACE_ROOT"; then
        MIGRATE_STANDALONE=1
        echoc cyan "Detected standalone React app root at $CREATE_CWD"
        echoc dim "Will migrate app into payloads/$APP_SLUG in the new payload repo."
        echo ""
      else
        echoc yellow "Standalone React app root detected at $CREATE_CWD, but migration into payloads/$APP_SLUG is disabled (cwd is under workspace payload-* or org-*)."
        echoc dim "The new repo is created from $TEMPLATE_REPO only. To force migration from this directory, set MTX_CREATE_ALLOW_STANDALONE_MIGRATE=1."
        echo ""
      fi
    fi
  fi
  REPO_PATH="$WORKSPACE_ROOT/$REPO_NAME"

  echo ""
  echoc cyan "Workspace: $WORKSPACE_ROOT"
  echoc cyan "Template: $TEMPLATE_REPO"
  echoc cyan "New repo: $(color yellow "$REPO_NAME")"
  echoc dim "Command: $MTX_CREATE_CMD"
  echoc dim "Run context: ${MTX_CREATE_RUN_CONTEXT:-unknown} (cwd: $CREATE_CWD)"
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
        warn "Template clone failed. Check local template '$LOCAL_TEMPLATE_PATH' or remote '$TEMPLATE_URL' (org default: template-org (legacy alias template-basic still accepted via MTX_ORG_TEMPLATE_REPO=template-basic); payload default: template-payload — see https://github.com/Meanwhile-Together/project-bridge/blob/main/docs/MTX_SCAFFOLDING_MODEL.md)."
        exit 1
      fi
    fi
    (cd "$REPO_PATH" && git remote rename origin upstream 2>/dev/null || true)
    echo ""
  fi

  unset MTX_TEMPLATE_SNAPSHOT_FROM
  export MTX_CREATE_SOURCE_NOTE="$TEMPLATE_REPO"

  if [ "$MIGRATE_STANDALONE" = "1" ]; then
    echoc cyan "Migrating standalone app into $REPO_PATH/payloads/$APP_SLUG ..."
    mtx_payload_migrate_standalone_into_repo "$CREATE_CWD" "$REPO_PATH" "$APP_SLUG"
    if [ "${MTX_CREATE_MOVE_SOURCE:-1}" = "0" ] || [ "${MTX_CREATE_MOVE_SOURCE:-1}" = "false" ]; then
      echoc dim "Migration complete (source preserved): $CREATE_CWD"
    else
      echoc dim "Migration complete (source moved): $CREATE_CWD -> $REPO_PATH/payloads/$APP_SLUG"
    fi
    echo ""
  fi

  if mtx_create_is_org_flow; then
    mtx_org_scaffold_deploy_config_surface "$REPO_PATH" "$REPO_NAME" "$WORKSPACE_ROOT" || {
      warn "Org deploy config scaffold had warnings; check config/ and terraform/."
    }
    mtx_org_merge_host_into_package_json "$REPO_PATH" "$WORKSPACE_ROOT" || {
      warn "Could not wire package.json to project-bridge (jq or scripts/org-build-server.sh missing)."
    }
  elif [ "${MTX_CREATE_VARIANT:-}" = "payload" ]; then
    mtx_payload_stamp_identity "$REPO_PATH" "$REPO_NAME" "$APP_SLUG" "$NEW_APP_NAME" || {
      warn "Could not stamp payload identity into config/app.json; operator should verify."
    }
  fi

  mtx_create_apply_metadata_and_github_publish
}
