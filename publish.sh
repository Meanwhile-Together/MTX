#!/usr/bin/env bash
# Normative: mtx publish — create the GitHub remote for a local payload-*/org-*/template-* repo.
# Narrow, idempotent verb: acts only when the remote does NOT yet exist on GitHub.
# Classification is path-based (CWD or the first positional arg) — a single repo root must resolve
# to exactly one kind (payload / org / template). The repo name on GitHub mirrors the directory
# basename; there is no rename step. See rule-of-law.md §1 (config triad) for the kind signatures.
#
# Design notes (don't regress):
#   - Refuses to run when `gh repo view $org/$name` succeeds — `mtx publish` is not an update tool.
#     Operators who want to push updates use plain `git push`; `mtx create …` owns the scaffold flow.
#   - Private by default (matches `mtx create`); `--public` flips it. Description defaults to
#     `package.json.description`, with a kind-specific fallback.
#   - Works without MTX_ROOT set in the environment: resolves its own install path from BASH_SOURCE.
#     This script intentionally does NOT source lib/install-payload.sh (payload detection is tiny
#     and inlined below); it does source lib/create-from-template.sh to reuse the gh auth / org
#     reachability / initial-commit helpers (those are plain function definitions, idempotent).
desc="Publish a payload-*/org-*/template-* repo to GitHub (only when the remote does not yet exist)"
nobanner=1
set -e

MTX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/create-from-template.sh
source "$MTX_ROOT/lib/create-from-template.sh"

mtx_publish_usage() {
  cat <<EOF
Usage: mtx publish [options] [path]

  Publishes the repo at <path> (default: current directory) to GitHub
  at \$MTX_GITHUB_ORG/<basename> (default org: Meanwhile-Together).
  Acts only when the GitHub repo does not already exist.

Options:
  --public              Create as a public repo (default: private)
  --private             Create as a private repo (default)
  --description "..."   Repo description (default: package.json description
                        or a kind-specific fallback)
  --force-origin        Overwrite an existing 'origin' remote that points elsewhere
  --dry-run, -n         Classify + check remote existence; do not mutate anything
  -h, --help            This message

Detection (path is classified as ONE of):
  template  basename template-*  OR  package.json "@meanwhile-together/template-*"
  payload   basename payload-*   OR  package.json "@meanwhile-together/payload-*"
            OR file signature: index.html + vite.config.* + config/app.json
               (or legacy metadata.json), no config/server.json
  org       basename org-*       OR  package.json "@meanwhile-together/org-*"
            OR file signature: config/org.json + payloads/ + terraform/

Environment:
  MTX_GITHUB_ORG        Target GitHub org/user (default: Meanwhile-Together)
EOF
}

# --- argument parsing ---
REPO_PATH=""
VISIBILITY="--private"
DESCRIPTION=""
DRY_RUN=0
FORCE_ORIGIN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --public)  VISIBILITY="--public";  shift ;;
    --private) VISIBILITY="--private"; shift ;;
    --description|--desc)
      [ $# -ge 2 ] || { error "Missing value for $1"; exit 2; }
      DESCRIPTION="$2"; shift 2 ;;
    --description=*|--desc=*) DESCRIPTION="${1#*=}"; shift ;;
    --force-origin) FORCE_ORIGIN=1; shift ;;
    --dry-run|-n)   DRY_RUN=1;      shift ;;
    -h|--help)      mtx_publish_usage; exit 0 ;;
    --) shift; [ -n "${1:-}" ] && REPO_PATH="$1"; break ;;
    -*)
      error "Unknown flag: $1"
      echoc dim "Run 'mtx publish --help' for usage."
      exit 2 ;;
    *)
      if [ -z "$REPO_PATH" ]; then
        REPO_PATH="$1"; shift
      else
        error "Unexpected argument: $1 (already have path '$REPO_PATH')"
        exit 2
      fi
      ;;
  esac
done

[ -z "$REPO_PATH" ] && REPO_PATH="$(pwd)"
_resolved="$(cd "$REPO_PATH" 2>/dev/null && pwd -P)" || _resolved=""
if [ -z "$_resolved" ]; then
  error "Path not found or not a directory: $REPO_PATH"
  exit 1
fi
REPO_PATH="$_resolved"
unset _resolved

REPO_NAME="$(basename "$REPO_PATH")"
GITHUB_ORG="${MTX_GITHUB_ORG:-Meanwhile-Together}"

# --- kind detection (path-only; no MTX_CREATE_* env coupling) ---
# Precedence: directory basename prefix > package.json scoped name > tree file-signature.
# Returns kind on stdout; exits 1 if nothing matches.
mtx_publish_detect_kind() {
  local d="$1" base name
  base="$(basename "$d")"
  case "$base" in
    template-*) echo template; return 0 ;;
    payload-*)  echo payload;  return 0 ;;
    org-*)      echo org;      return 0 ;;
  esac
  if [ -f "$d/package.json" ] && command -v node >/dev/null 2>&1; then
    name="$(cd "$d" && node -p "require('./package.json').name || ''" 2>/dev/null || true)"
    case "$name" in
      @meanwhile-together/template-*) echo template; return 0 ;;
      @meanwhile-together/payload-*)  echo payload;  return 0 ;;
      @meanwhile-together/org-*)      echo org;      return 0 ;;
    esac
  fi
  # Payload file signature — matches install-payload.sh:mtx_install_cwd_is_payload_root (rule-of-law §1 2026-04-20).
  if [ -f "$d/index.html" ] \
     && [ ! -f "$d/config/server.json" ] && [ ! -f "$d/server.json" ] \
     && ls "$d"/vite.config.* >/dev/null 2>&1 \
     && { [ -f "$d/config/app.json" ] || [ -f "$d/metadata.json" ]; }; then
    echo payload; return 0
  fi
  # Org file signature — canonical post-2026-04-20 triad shape.
  if [ -f "$d/config/org.json" ] && [ -d "$d/payloads" ] && [ -d "$d/terraform" ]; then
    echo org; return 0
  fi
  return 1
}

if ! KIND="$(mtx_publish_detect_kind "$REPO_PATH")"; then
  error "Cannot classify '$REPO_PATH' as a payload-*, org-*, or template-* repo."
  echoc dim "Expected one of:"
  echoc dim "  - basename starting with payload- / org- / template-"
  echoc dim "  - package.json name @meanwhile-together/{payload,org,template}-*"
  echoc dim "  - payload tree: index.html + vite.config.* + config/app.json (no config/server.json)"
  echoc dim "  - org tree: config/org.json + payloads/ + terraform/"
  exit 1
fi

# Validate basename matches the detected kind's canonical prefix.
expected_prefix=""
case "$KIND" in
  template) expected_prefix="template-" ;;
  payload)  expected_prefix="payload-"  ;;
  org)      expected_prefix="org-"      ;;
esac
case "$REPO_NAME" in
  "$expected_prefix"*) ;;
  *)
    warn "Directory '$REPO_NAME' does not start with '$expected_prefix' (kind inferred from package.json or file signature)."
    echoc dim "GitHub repo name will be '$REPO_NAME' as-is. If you want the canonical prefix, rename the directory first (and re-run)."
    ;;
esac

echoc cyan "Publishing $KIND repo"
echoc dim  "  Source:     $REPO_PATH"
echoc dim  "  Target:     https://github.com/$GITHUB_ORG/$REPO_NAME"
echoc dim  "  Visibility: ${VISIBILITY#--}"

# --- description defaulting ---
if [ -z "$DESCRIPTION" ] && [ -f "$REPO_PATH/package.json" ] && command -v node >/dev/null 2>&1; then
  DESCRIPTION="$(cd "$REPO_PATH" && node -p "require('./package.json').description || ''" 2>/dev/null || true)"
fi
if [ -z "$DESCRIPTION" ]; then
  case "$KIND" in
    template) DESCRIPTION="Meanwhile-Together template scaffold ($REPO_NAME)" ;;
    payload)  DESCRIPTION="Meanwhile-Together payload ($REPO_NAME)" ;;
    org)      DESCRIPTION="Meanwhile-Together org host ($REPO_NAME)" ;;
  esac
fi
echoc dim "  Description: $DESCRIPTION"

# --- gh preconditions ---
if ! command -v gh >/dev/null 2>&1; then
  error "gh CLI is required for mtx publish. Install: https://cli.github.com/"
  exit 1
fi

if [ "$DRY_RUN" -ne 1 ]; then
  ensure_gh_auth_create || { error "gh authentication required for publish."; exit 1; }
  mtx_create_ensure_github_org_reachable "$GITHUB_ORG" || exit 1
fi

# --- remote-existence gate (the whole point of this command) ---
if gh auth status &>/dev/null && gh repo view "$GITHUB_ORG/$REPO_NAME" &>/dev/null; then
  warn "Remote already exists: https://github.com/$GITHUB_ORG/$REPO_NAME"
  echoc dim "mtx publish only acts when the remote does not yet exist."
  echoc dim "To push updates, use plain 'git push' from $REPO_PATH."
  exit 0
fi

# --- local origin sanity (don't silently stomp a remote that points elsewhere) ---
WANT_SSH="git@github.com:${GITHUB_ORG}/${REPO_NAME}.git"
WANT_HTTPS="https://github.com/${GITHUB_ORG}/${REPO_NAME}.git"
CURRENT_REMOTE=""
if [ -d "$REPO_PATH/.git" ]; then
  CURRENT_REMOTE="$(git -C "$REPO_PATH" remote get-url origin 2>/dev/null || true)"
fi
if [ -n "$CURRENT_REMOTE" ] \
  && [ "$CURRENT_REMOTE" != "$WANT_SSH" ] \
  && [ "$CURRENT_REMOTE" != "$WANT_HTTPS" ] \
  && [ "$FORCE_ORIGIN" -ne 1 ]; then
  error "Existing 'origin' points at: $CURRENT_REMOTE"
  echoc dim "Expected $WANT_SSH (or $WANT_HTTPS)."
  echoc dim "Re-run with --force-origin to overwrite, or fix the remote manually."
  exit 1
fi

if [ "$DRY_RUN" -eq 1 ]; then
  echo ""
  echoc yellow "[dry-run] Would now:"
  echoc dim   "  1. git init / branch -M main / commit (if needed)"
  echoc dim   "  2. gh repo create $GITHUB_ORG/$REPO_NAME $VISIBILITY \\"
  echoc dim   "       --description \"$DESCRIPTION\" --source=. --remote=origin --push"
  echoc dim   "  3. verify https://github.com/$GITHUB_ORG/$REPO_NAME resolves"
  exit 0
fi

# --- init + initial commit (idempotent helper) ---
mtx_create_local_git_commit_initial "$REPO_PATH" "mtx publish: initial publish of $REPO_NAME ($KIND)"

# --- create remote + push ---
echoc cyan "Creating GitHub repository $GITHUB_ORG/$REPO_NAME and pushing main..."
if ! (
  set -e
  cd "$REPO_PATH"
  git branch -M main 2>/dev/null || true

  # Guarantee HEAD before gh repo create --source=. --push.
  if ! git rev-parse -q --verify HEAD >/dev/null; then
    git add -A
    git commit -q --allow-empty -m "mtx publish: initial publish of $REPO_NAME ($KIND)"
  fi

  # `gh repo create --remote=origin` fails if origin already exists; drop any prior origin
  # (safe: the sanity check above refused a mismatched origin without --force-origin).
  git remote remove origin 2>/dev/null || true

  gh repo create "$GITHUB_ORG/$REPO_NAME" $VISIBILITY \
    --description "$DESCRIPTION" \
    --source=. --remote=origin --push
); then
  error "gh repo create or push failed for $GITHUB_ORG/$REPO_NAME."
  echoc dim "Common fixes:"
  echoc dim "  - gh auth setup-git   (so git push uses the gh token)"
  echoc dim "  - gh auth refresh     (expired token)"
  echoc dim "  - SAML orgs: authorize SSO at github.com/settings/applications"
  echoc dim "  - Confirm you have write access to $GITHUB_ORG"
  exit 1
fi

# --- verify ---
if ! gh repo view "$GITHUB_ORG/$REPO_NAME" &>/dev/null; then
  warn "Push reported success but gh cannot yet resolve $GITHUB_ORG/$REPO_NAME (visibility lag)."
fi

echo ""
echoc green "Published $KIND repo: https://github.com/$GITHUB_ORG/$REPO_NAME"
echoc dim   "Local path: $REPO_PATH"

# --- kind-specific follow-up hints ---
echo ""
case "$KIND" in
  payload)
    echoc cyan "Next steps (payload):"
    echoc dim  "  - From $REPO_PATH, run 'mtx payload install' to wire this payload into a sibling org-*"
    echoc dim  "  - Add '$REPO_NAME' to MTX/includes/workspace-repos.sh so 'mtx workspace' / 'mtx pull' track it"
    ;;
  org)
    echoc cyan "Next steps (org):"
    echoc dim  "  - Configure Railway (mtx prepare) then 'mtx deploy staging' / 'mtx deploy production'"
    echoc dim  "  - Add '$REPO_NAME' to MTX/includes/workspace-repos.sh"
    ;;
  template)
    echoc cyan "Next steps (template):"
    echoc dim  "  - 'mtx create payload' / 'mtx create org' clone from GitHub when no local sibling exists"
    echoc dim  "  - Add '$REPO_NAME' to MTX/includes/workspace-repos.sh if it should be cloned into workspaces"
    ;;
esac
