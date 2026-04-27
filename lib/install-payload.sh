# shellcheck shell=bash
# Payload host wiring: add a payload source to the current host and register apps[].
# Canonical CLI: mtx payload install (see https://github.com/Meanwhile-Together/project-bridge/blob/main/docs/MTX_COMMAND_SURFACE.md).
# Sourced by payload/install.sh; call mtx_install_payload_main "$@".

mtx_install_payload_main() {
  nobanner=1
  set -e
  local _lib_dir
  _lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  MTX_ROOT="${MTX_ROOT:-$(cd "$_lib_dir/.." && pwd)}"
if [ -d "$MTX_ROOT/includes" ]; then
  # shellcheck disable=SC1091
  for f in "$MTX_ROOT"/includes/*.sh; do source "$f"; done
fi

# Fallbacks when run outside mtx wrapper/bootstrap.
declare -F echoc >/dev/null || echoc() { local _c="$1"; shift || true; echo "$*"; }
declare -F info >/dev/null || info() { echo "[INFO] $*"; }
declare -F warn >/dev/null || warn() { echo "[WARN] $*" >&2; }
declare -F error >/dev/null || error() { echo "[ERROR] $*" >&2; }
declare -F success >/dev/null || success() { echo "[SUCCESS] $*"; }
declare -F mtx_run >/dev/null || mtx_run() { "$@"; }

slugify() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/^-*\|-*$//g'
}

# Tailwind ownership tripwire (rule-of-law §1 2026-04-24 "Tailwind is framework-owned"):
# payloads must not ship their own tailwind.config.* / postcss.config.* / tailwindcss /
# @tailwindcss/* deps. The framework's @meanwhile-together/ui package owns the version
# pin, the @theme vocabulary, and the @tailwindcss/vite plugin. Drift in a payload would
# either silently double-load Tailwind (two versions in one bundle) or shadow the
# framework's tokens — both regressions we explicitly excluded by design. Refuse early
# instead of letting the offending payload land in a host's apps[] entry.
#
# Returns 0 when the directory is clean; emits an error and returns 2 when it isn't.
mtx_install_assert_no_payload_tailwind() {
  local d="$1"
  [ -d "$d" ] || return 0
  local stale=()
  for f in tailwind.config.js tailwind.config.ts tailwind.config.mjs tailwind.config.cjs \
           postcss.config.js postcss.config.ts postcss.config.mjs postcss.config.cjs; do
    [ -f "$d/$f" ] && stale+=("$f")
  done
  local pkg="$d/package.json"
  local dep_hits=""
  if [ -f "$pkg" ] && command -v node >/dev/null 2>&1; then
    dep_hits=$(node -e '
      const pkg = require(process.argv[1]);
      const blocks = ["dependencies", "devDependencies", "peerDependencies", "optionalDependencies"];
      const hits = [];
      for (const b of blocks) {
        const obj = pkg[b];
        if (!obj || typeof obj !== "object") continue;
        for (const name of Object.keys(obj)) {
          if (name === "tailwindcss" || name.startsWith("@tailwindcss/")) {
            hits.push(b + ":" + name);
          }
        }
      }
      process.stdout.write(hits.join(" "));
    ' "$pkg" 2>/dev/null || true)
  fi
  if [ "${#stale[@]}" -eq 0 ] && [ -z "$dep_hits" ]; then
    return 0
  fi
  error "Tailwind ownership violation in $(basename "$d") — payloads must not ship their own Tailwind plumbing."
  if [ "${#stale[@]}" -gt 0 ]; then
    echoc dim "  Stale config file(s): $(printf '%s ' "${stale[@]}")"
  fi
  if [ -n "$dep_hits" ]; then
    echoc dim "  Stale package.json deps: $dep_hits"
  fi
  echoc dim "  Fix: delete those files, drop those deps, and have src/styles.css (or src/index.css) read"
  echoc dim "       @import \"@meanwhile-together/ui/styles/framework.css\";"
  echoc dim "       Wire vite.config.ts via { mtFrameworkPlugins } from \"@meanwhile-together/ui/vite\"."
  echoc dim "  See project-bridge/docs/rule-of-law.md §1 2026-04-24."
  return 2
}

trim() {
  local v="$1"
  v="${v#"${v%%[![:space:]]*}"}"
  v="${v%"${v##*[![:space:]]}"}"
  echo "$v"
}

# Org payload repos (org-*) may host config/server.json for nested apps without project-bridge's config/app.json.
mtx_install_is_org_payload_root() {
  local d="$1"
  local base name
  base="$(basename "$d")"
  case "$base" in
    org-*) return 0 ;;
  esac
  if [ -f "$d/package.json" ] && command -v node >/dev/null 2>&1; then
    name=$(cd "$d" && node -p "require('./package.json').name" 2>/dev/null || true)
    case "$name" in
      @meanwhile-together/org-*) return 0 ;;
    esac
  fi
  return 1
}

find_project_root() {
  local walk
  walk="$(pwd)"
  while [ -n "$walk" ] && [ "$walk" != "/" ]; do
    if [ -f "$walk/package.json" ]; then
      if [ -d "$walk/config" ] || [ -f "$walk/config/app.json" ] || [ -f "$walk/server.json" ]; then
        echo "$walk"
        return 0
      fi
      if mtx_install_is_org_payload_root "$walk"; then
        echo "$walk"
        return 0
      fi
    fi
    walk="$(dirname "$walk")"
  done
  return 1
}

# Classify cwd: is it a single-app payload repo? (flat_payload_app context)
# Rules (any sufficient):
#   - directory basename is payload-*
#   - package.json .name is @meanwhile-together/payload-*
#   - file signature: config/app.json + index.html + vite.config.* + NO config/server.json
#     (fallback for legacy AI-Studio-shaped trees: metadata.json + index.html + vite.config.*)
# Template repos (template-*) are refused earlier by `mtx create payload` (c7a) — here we
# just decline to redirect from them, so the operator gets the normal "no project root" error.
#
# Rule-of-law §1 2026-04-20 (metadata.json retirement): payload identity now lives in
# config/app.json; metadata.json is legacy AI Studio boilerplate that the hoist script
# strips. We accept either signature so pre-hoist payloads still get redirected instead
# of silently treating project-bridge as the host.
mtx_install_cwd_is_payload_root() {
  local d="$1"
  local base name
  base="$(basename "$d")"
  case "$base" in
    payload-*) return 0 ;;
    template-*) return 1 ;;
  esac
  if [ -f "$d/package.json" ] && command -v node >/dev/null 2>&1; then
    name=$(cd "$d" && node -p "require('./package.json').name" 2>/dev/null || true)
    case "$name" in
      @meanwhile-together/payload-*) return 0 ;;
    esac
  fi
  # File-signature fallback (tree says "payload" even if name doesn't).
  if [ -f "$d/index.html" ] && [ ! -f "$d/config/server.json" ] && [ ! -f "$d/server.json" ]; then
    if ls "$d"/vite.config.* >/dev/null 2>&1; then
      # New shape (post-2026-04-20): payload identity lives in config/app.json.
      if [ -f "$d/config/app.json" ]; then return 0; fi
      # Legacy shape (pre-hoist AI Studio import): metadata.json at repo root.
      if [ -f "$d/metadata.json" ]; then return 0; fi
    fi
  fi
  return 1
}

# Derive the payload's canonical id (e.g. "payload-client-portal") from a payload repo dir.
mtx_install_derive_payload_id() {
  local d="$1"
  local base name id
  base="$(basename "$d")"
  case "$base" in
    payload-*) echo "$base"; return 0 ;;
  esac
  if [ -f "$d/package.json" ] && command -v node >/dev/null 2>&1; then
    name=$(cd "$d" && node -p "require('./package.json').name" 2>/dev/null || true)
    case "$name" in
      @meanwhile-together/payload-*) id="${name#@meanwhile-together/}"; echo "$id"; return 0 ;;
    esac
  fi
  return 1
}

# List sibling org-* dirs under a workspace root (each with a package.json).
mtx_install_list_org_siblings() {
  local ws="$1"
  local d
  [ -d "$ws" ] || return 0
  for d in "$ws"/org-*; do
    [ -d "$d" ] || continue
    [ -f "$d/package.json" ] || continue
    echo "$d"
  done
}

# List payload-* repo dirs under a workspace root (sibling to org-*, project-bridge, etc.).
# Emits one absolute path per line; only dirs that pass mtx_install_cwd_is_payload_root.
mtx_install_list_payload_siblings() {
  local ws="$1"
  local p
  [ -d "$ws" ] || return 0
  while IFS= read -r p; do
    [ -n "$p" ] && [ -d "$p" ] || continue
    mtx_install_cwd_is_payload_root "$p" || continue
    echo "$p"
  done < <(find "$ws" -mindepth 1 -maxdepth 1 -type d -name 'payload-*' 2>/dev/null | LC_ALL=C sort)
}

# When running from a host (not redirect from payload) with no payload id on the CLI, list
# sibling payload-* under the workspace and prompt to pick one. Sets PAYLOAD_ID and
# WORKSPACE_ROOT on success. Returns 0 when PAYLOAD_ID is set, 1 when not (caller should
# error). Exits 0 when all siblings are already registered (nothing to do, same as redirect
# org picker).
mtx_install_interactive_select_payload_id_for_host() {
  local host_path="$1"
  local workspace_root
  local -a all=() eligible=() already=() unreadable=()
  local d id rc selection i

  workspace_root="$(cd "$host_path/.." 2>/dev/null && pwd -P)" || return 1
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    all+=("$d")
  done < <(mtx_install_list_payload_siblings "$workspace_root")

  if [ "${#all[@]}" -eq 0 ]; then
    warn "No payload-* sibling repos under $workspace_root (expected alongside $(basename "$host_path"))."
    return 1
  fi

  if ! command -v jq >/dev/null 2>&1; then
    warn "jq is required to show which sibling payload repos are not yet on this host."
    return 1
  fi

  for d in "${all[@]}"; do
    id="$(mtx_install_derive_payload_id "$d" 2>/dev/null || true)"
    if [ -z "$id" ]; then
      unreadable+=("$(basename "$d")")
      continue
    fi
    rc=0
    mtx_install_org_has_payload "$host_path" "$id" || rc=$?
    case $rc in
      0) already+=("$(basename "$d")") ;;
      1) eligible+=("$d") ;;
      *) unreadable+=("$(basename "$d")") ;;
    esac
  done

  if [ "${#eligible[@]}" -eq 0 ]; then
    if [ "${#already[@]}" -gt 0 ] && [ "${#unreadable[@]}" -eq 0 ]; then
      echoc yellow "All ${#all[@]} sibling payload repo(s) are already on this host — nothing to install."
      for d in "${all[@]}"; do echoc dim "  - $(basename "$d")"; done
      exit 0
    fi
    if [ "${#unreadable[@]}" -gt 0 ] || [ "${#already[@]}" -gt 0 ]; then
      warn "Could not find a new sibling to install. Pass an explicit: mtx payload install <payload-id>"
    fi
    if [ "${#already[@]}" -gt 0 ]; then
      echoc dim "  already on host: $(printf '%s ' "${already[@]}")"
    fi
    if [ "${#unreadable[@]}" -gt 0 ]; then
      echoc dim "  skipped (id or config): $(printf '%s ' "${unreadable[@]}")"
    fi
    return 1
  fi

  if [ ! -t 0 ] || [ ! -t 1 ] || [ "${MTX_CREATE_NONINTERACTIVE:-}" = "1" ]; then
    return 1
  fi

  echo ""
  echoc bold "Install which payload into $(basename "$host_path")?"
  echoc dim  "(siblings already on this host are not listed; jq + readable server config required)"
  i=1
  for d in "${eligible[@]}"; do
    printf "  %2d) %s\n" "$i" "$(basename "$d")"
    i=$((i + 1))
  done
  if [ "${#already[@]}" -gt 0 ]; then
    echoc dim "  (already installed: $(printf '%s ' "${already[@]}"))"
  fi
  if [ "${#unreadable[@]}" -gt 0 ]; then
    echoc dim "  (skipped, id or config: $(printf '%s ' "${unreadable[@]}"))"
  fi
  echo ""
  read -rp "Choice [1]: " selection
  selection="${selection:-1}"
  if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt "${#eligible[@]}" ]; then
    error "Invalid selection: $selection"
    exit 2
  fi

  d="${eligible[$((selection - 1))]}"
  PAYLOAD_ID="$(mtx_install_derive_payload_id "$d" 2>/dev/null || true)"
  if [ -z "$PAYLOAD_ID" ]; then
    return 1
  fi
  WORKSPACE_ROOT="$workspace_root"
  echoc dim "Selected payload: $PAYLOAD_ID"
  return 0
}

# Check whether a given org already has a given payload registered in config/server.json.
# Match rules: id, slug, source.path (../<repo> | ./payloads/<slug>), source.package
# (@meanwhile-together/<repo>), source.git.url containing <repo>. Requires jq.
# Returns 0 if already registered, 1 if not, 2 on parse error / missing config.
mtx_install_org_has_payload() {
  local org_path="$1" payload_id="$2"
  local cfg payload_slug
  cfg="$org_path/config/server.json"
  [ -f "$cfg" ] || cfg="$org_path/server.json"
  [ -f "$cfg" ] || return 2
  command -v jq >/dev/null 2>&1 || return 2
  payload_slug="${payload_id#payload-}"
  jq -e \
    --arg id   "$payload_id" \
    --arg slug "$payload_slug" \
    --arg repo "$payload_id" \
    '
    def arr: (.apps // .payloads // []);
    def paths: [
      ("../" + $repo),
      ("../" + $repo + "/"),
      ("./payloads/" + $slug),
      ("./payloads/" + $slug + "/"),
      ("payloads/" + $slug),
      ("payloads/" + $slug + "/")
    ];
    [arr[]?
      | select(
          (.id    == $id) or (.id    == $repo) or
          (.slug  == $slug) or
          ((.source // {}) | (
            ((.path   // "") as $p | (paths | any(. == $p)))
            or ((.package // "") == ("@meanwhile-together/" + $repo))
            or ((.git // {} | .url // "") | test($repo; "i"))
          ))
        )
    ] | length > 0
    ' "$cfg" >/dev/null 2>&1
}

# If cwd is a payload root, flip `mtx payload install` into a redirect:
#   1. Derive payload id.
#   2. Find eligible target orgs (siblings that don't already have this payload).
#   3. Prompt (interactive) or honor MTX_TARGET_ORG / --target-org (non-interactive).
#   4. Export PROJECT_ROOT / CONFIG_PATH / REDIRECTED_FROM_PAYLOAD so the rest of the main
#      flow installs into the chosen org instead of walking up from cwd.
# Does NOT re-exec mtx (avoids the MTX_ROOT / sourcing tech debt called out in ROL §1 / §6).
# See project-bridge/docs/rule-of-law.md §1 2026-04-20 bullet.
mtx_install_resolve_target_host() {
  local cwd="$1" target_override="${2:-}"
  local workspace_root payload_id payload_path
  local -a candidates eligible

  mtx_install_cwd_is_payload_root "$cwd" || return 0

  payload_id="$(mtx_install_derive_payload_id "$cwd" 2>/dev/null || true)"
  if [ -z "$payload_id" ]; then
    warn "cwd looks like a payload but the payload id could not be derived (check directory name or package.json .name)."
    return 0
  fi
  payload_path="$cwd"
  workspace_root="$(cd "$cwd/.." && pwd -P)"

  echoc cyan "Detected payload repo: $(basename "$payload_path") — flipping to redirect mode."
  echoc dim "Payload id:     $payload_id"
  echoc dim "Workspace root: $workspace_root"

  if ! command -v jq >/dev/null 2>&1; then
    error "jq is required to scan org-* hosts for existing $payload_id registrations. Install jq and retry, or run from an org root directly."
    exit 2
  fi

  # Gather candidate org-* siblings and bucket them by install state.
  local -a all=() already=() unreadable=()
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    all+=("$d")
  done < <(mtx_install_list_org_siblings "$workspace_root")

  if [ "${#all[@]}" -eq 0 ]; then
    error "No org-* hosts found alongside $(basename "$payload_path") in $workspace_root."
    echoc dim "Scaffold one with: mtx create org    (then: cd org-<slug> && mtx payload install $payload_id)"
    exit 2
  fi

  local d rc
  for d in "${all[@]}"; do
    # `|| rc=$?` keeps this compatible with `set -e` in mtx_install_payload_main.
    rc=0
    mtx_install_org_has_payload "$d" "$payload_id" || rc=$?
    case $rc in
      0) already+=("$(basename "$d")") ;;
      1) eligible+=("$d") ;;
      *) unreadable+=("$(basename "$d")") ;;
    esac
  done

  # If operator pre-picked a target, honor it (even if already-installed — they know).
  if [ -n "$target_override" ]; then
    local match=""
    for d in "${all[@]}"; do
      if [ "$(basename "$d")" = "$target_override" ] || [ "$(basename "$d")" = "org-$target_override" ]; then
        match="$d"; break
      fi
    done
    if [ -z "$match" ]; then
      error "--target-org '$target_override' not found under $workspace_root."
      echoc dim "Available org-* siblings: $(printf '%s ' "${all[@]##*/}")"
      exit 2
    fi
    PROJECT_ROOT="$match"
    REDIRECTED_FROM_PAYLOAD=1
    REDIRECTED_PAYLOAD_ID="$payload_id"
    REDIRECTED_PAYLOAD_CWD="$payload_path"
    WORKSPACE_ROOT="$workspace_root"
    echoc dim "Target host (override): $(basename "$PROJECT_ROOT")"
    return 0
  fi

  if [ "${#eligible[@]}" -eq 0 ]; then
    echoc yellow "All $(printf '%d' "${#all[@]}") org-* host(s) already register $payload_id — nothing to do."
    if [ "${#already[@]}" -gt 0 ]; then
      echoc dim "  already installed: $(printf '%s ' "${already[@]}")"
    fi
    if [ "${#unreadable[@]}" -gt 0 ]; then
      echoc dim "  skipped (no readable server config): $(printf '%s ' "${unreadable[@]}")"
    fi
    exit 0
  fi

  # Interactive prompt. Standing disclaimer prints ABOVE the list so absence has a reason.
  local selection=""
  if [ -t 0 ] && [ -t 1 ] && [ "${MTX_CREATE_NONINTERACTIVE:-}" != "1" ]; then
    echo ""
    echoc bold "Install $payload_id into which org?"
    echoc dim  "(orgs already registering $payload_id are hidden — if yours isn't listed, it's already installed there)"
    local i=1
    for d in "${eligible[@]}"; do
      printf "  %2d) %s\n" "$i" "$(basename "$d")"
      i=$((i+1))
    done
    if [ "${#already[@]}" -gt 0 ]; then
      echoc dim "  (already installed: $(printf '%s ' "${already[@]}"))"
    fi
    if [ "${#unreadable[@]}" -gt 0 ]; then
      echoc dim "  (skipped, no readable config: $(printf '%s ' "${unreadable[@]}"))"
    fi
    echo ""
    read -rp "Choice [1]: " selection
    selection="${selection:-1}"
    if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt "${#eligible[@]}" ]; then
      error "Invalid selection: $selection"
      exit 2
    fi
  else
    error "Running non-interactively from a payload repo with no --target-org / MTX_TARGET_ORG set."
    echoc dim "Eligible orgs (missing $payload_id):"
    for d in "${eligible[@]}"; do echoc dim "  - $(basename "$d")"; done
    echoc dim "Re-run with: MTX_TARGET_ORG=<org-name> mtx payload install $payload_id"
    exit 2
  fi

  PROJECT_ROOT="${eligible[$((selection-1))]}"
  REDIRECTED_FROM_PAYLOAD=1
  REDIRECTED_PAYLOAD_ID="$payload_id"
  REDIRECTED_PAYLOAD_CWD="$payload_path"
  WORKSPACE_ROOT="$workspace_root"
  echoc cyan "Target host: $(basename "$PROJECT_ROOT")"
  return 0
}

show_help() {
  cat <<'EOF'
Usage:
  mtx payload install <payload-id> [--target-org <org-name>]   (from an org-* / host repo)
  mtx payload install [<payload-id>] [--target-org <org-name>]  (from a payload-* repo)

Installs a payload package/source into a host repo's config/server.json (idempotent apps[] entry).

Where it runs from determines behavior:
  * Inside an org-* host (or project-bridge dev tree):
      <payload-id> is optional in an interactive TTY: the command walks up, finds the host, then
      lists sibling payload-* dirs under the workspace (same parent as the host) and prompts
      for one to install. Skip the list by passing the id, e.g. payload-vibe-check. Non-TTY
      and MTX_CREATE_NONINTERACTIVE=1 require an explicit id. Listing needs jq and a
      readable server config to hide payloads already in apps[].
  * Inside a payload-* repo:
      Flips direction. <payload-id> is optional (default: inferred from the repo / cwd).
      Scans sibling org-* hosts, filters out orgs that already register this payload
      (id / slug / source.path / source.package / source.git.url match), and prompts for a
      target org. If your org isn't in the list, the payload is already registered there.
      With --target-org <name> or MTX_TARGET_ORG=<name>, the prompt is skipped. Source
      defaults to path=../<payload-id> in this mode. See project-bridge/docs/rule-of-law.md
      §1 2026-04-20.

<payload-id> is the app entry id (e.g. payload-client-portal); required from a host repo,
optional in redirect mode (auto-filled from cwd). Default npm package is
@meanwhile-together/<payload-id>.

Environment:
  MTX_TARGET_ORG        Pre-select target org for redirect mode (skips interactive prompt).
EOF
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  show_help
  exit 0
fi

# Parse args: [payload-id] [--target-org <name>] (order-flexible).
PAYLOAD_ID=""
TARGET_ORG="${MTX_TARGET_ORG:-}"
while [ $# -gt 0 ]; do
  case "$1" in
    --target-org)
      shift
      TARGET_ORG="${1:-}"
      [ -n "$TARGET_ORG" ] || { error "--target-org requires a value."; exit 1; }
      ;;
    --target-org=*)
      TARGET_ORG="${1#--target-org=}"
      [ -n "$TARGET_ORG" ] || { error "--target-org= requires a value."; exit 1; }
      ;;
    --*)
      error "Unknown flag: $1"; exit 1
      ;;
    *)
      if [ -z "$PAYLOAD_ID" ]; then
        PAYLOAD_ID="$1"
      else
        error "Unexpected positional argument: $1"; exit 1
      fi
      ;;
  esac
  shift
done

# If cwd is a payload repo, flip direction (pick target org, set PROJECT_ROOT).
# See rule-of-law §1 2026-04-20 bullet. Does not re-exec mtx.
REDIRECTED_FROM_PAYLOAD=0
REDIRECTED_PAYLOAD_ID=""
REDIRECTED_PAYLOAD_CWD=""
WORKSPACE_ROOT=""
mtx_install_resolve_target_host "$(pwd)" "$TARGET_ORG"

# Rule-of-law §1 2026-04-24: enforce framework-owned Tailwind on the redirected payload
# source. We only have a disk path to inspect when redirecting (or when --target-org
# pointed us at a payload sibling); the path-source check below covers the explicit case.
if [ "${REDIRECTED_FROM_PAYLOAD:-0}" = "1" ] && [ -n "${REDIRECTED_PAYLOAD_CWD:-}" ]; then
  mtx_install_assert_no_payload_tailwind "$REDIRECTED_PAYLOAD_CWD" || exit $?
fi

# Auto-fill payload id from the redirect if the operator didn't pass one.
if [ "$REDIRECTED_FROM_PAYLOAD" = "1" ] && [ -z "$PAYLOAD_ID" ]; then
  PAYLOAD_ID="$REDIRECTED_PAYLOAD_ID"
  echoc dim "Payload id (from cwd): $PAYLOAD_ID"
fi

# From a host with no <payload-id> on the CLI, resolve project root and prompt for a
# sibling payload-* to install (same workspace; requires TTY, jq, readable server config).
if [ -z "$PAYLOAD_ID" ] && [ "${REDIRECTED_FROM_PAYLOAD:-0}" != "1" ]; then
  if [ -z "${PROJECT_ROOT:-}" ]; then
    PROJECT_ROOT="$(find_project_root || true)"
  fi
  if [ -n "$PROJECT_ROOT" ]; then
    mtx_install_interactive_select_payload_id_for_host "$PROJECT_ROOT" || true
  fi
fi

if [ -z "$PAYLOAD_ID" ]; then
  error "Missing payload id."
  if [ -t 0 ] && [ -t 1 ] && [ -z "${CI:-}" ]; then
    echoc dim "From a host: pass mtx payload install <id>, or run in a TTY (with sibling payload-* under the workspace) for an interactive list."
  fi
  echo ""
  show_help
  exit 1
fi

# When redirected, the host is already picked; otherwise walk up from cwd as usual.
if [ -z "${PROJECT_ROOT:-}" ]; then
  PROJECT_ROOT="$(find_project_root || true)"
fi
if [ -z "$PROJECT_ROOT" ]; then
  error "Could not find a project root from current directory."
  warn "Expected package.json plus config/server.json (or server.json) in current directory or a parent."
  exit 1
fi

CONFIG_PATH="$PROJECT_ROOT/config/server.json"
[ -f "$CONFIG_PATH" ] || CONFIG_PATH="$PROJECT_ROOT/server.json"

if [ ! -f "$CONFIG_PATH" ]; then
  info "No server config found; bootstrapping one now..."
  if [ -f "$PROJECT_ROOT/config/server-multi-app.example.json" ]; then
    cp "$PROJECT_ROOT/config/server-multi-app.example.json" "$PROJECT_ROOT/config/server.json"
    CONFIG_PATH="$PROJECT_ROOT/config/server.json"
    success "Created config/server.json from config/server-multi-app.example.json"
  elif [ -f "$PROJECT_ROOT/config/server.json.example" ]; then
    cp "$PROJECT_ROOT/config/server.json.example" "$PROJECT_ROOT/config/server.json"
    CONFIG_PATH="$PROJECT_ROOT/config/server.json"
    success "Created config/server.json from config/server.json.example"
  elif [ -f "$PROJECT_ROOT/server.json.example" ]; then
    cp "$PROJECT_ROOT/server.json.example" "$PROJECT_ROOT/server.json"
    CONFIG_PATH="$PROJECT_ROOT/server.json"
    success "Created server.json from server.json.example"
  else
    CONFIG_PATH="$PROJECT_ROOT/config/server.json"
    mkdir -p "$PROJECT_ROOT/config"
    printf '{\n  "apps": []\n}\n' > "$CONFIG_PATH"
    warn "No server config template found; created minimal config/server.json with apps[]."
  fi
fi

if ! command -v node >/dev/null 2>&1; then
  error "node is required."
  exit 1
fi

if ! command -v npm >/dev/null 2>&1; then
  error "npm is required."
  exit 1
fi

PAYLOAD_SLUG="$(slugify "$PAYLOAD_ID")"
PAYLOAD_SLUG="${PAYLOAD_SLUG#payload-}"
PAYLOAD_SLUG="${PAYLOAD_SLUG#org-}"
PAYLOAD_SLUG="${PAYLOAD_SLUG#template-}"
[ -n "$PAYLOAD_SLUG" ] || PAYLOAD_SLUG="app"

DEFAULT_NAME="$(echo "$PAYLOAD_ID" | sed 's/[-_]/ /g')"
# Friendlier default label for org-* repos (mtx create org → org-<slug>-…)
case "$PAYLOAD_ID" in
  org-*)
    _org_rest="${PAYLOAD_ID#org-}"
    DEFAULT_NAME="Organization $(echo "$_org_rest" | sed 's/[-_]/ /g')"
    ;;
  template-*)
    _trest="${PAYLOAD_ID#template-}"
    DEFAULT_NAME="Payload template $(echo "$_trest" | sed 's/[-_]/ /g')"
    ;;
esac
DEFAULT_PACKAGE="@meanwhile-together/$PAYLOAD_ID"
if [[ "$PAYLOAD_ID" == @*/* ]]; then
  DEFAULT_PACKAGE="$PAYLOAD_ID"
fi

# Config triad (rule-of-law §1 2026-04-20): pre-fill name/slug from the payload's own config/app.json
# when we can see the payload source on disk (redirect-from-payload case, or a sibling path). Identity
# is the payload's property — the org's server.json entry only carries routing.
mtx_install_prefill_from_payload_app() {
  local payload_root=""
  if [ "${REDIRECTED_FROM_PAYLOAD:-0}" = "1" ] && [ -n "${REDIRECTED_PAYLOAD_CWD:-}" ]; then
    payload_root="$REDIRECTED_PAYLOAD_CWD"
  else
    local sibling="$WORKSPACE_ROOT/$PAYLOAD_ID"
    [ -d "$sibling" ] && payload_root="$sibling"
  fi
  [ -n "$payload_root" ] || return 0
  local app_json="$payload_root/config/app.json"
  if [ ! -f "$app_json" ]; then
    warn "Payload $PAYLOAD_ID has no config/app.json — identity will default from the repo name."
    echoc dim "Consider adding $app_json with {\"app\":{\"name\":\"…\",\"slug\":\"…\",\"version\":\"1.0.0\"}} so orgs mount it with accurate identity."
    return 0
  fi
  command -v jq >/dev/null 2>&1 || return 0
  local pn ps
  pn=$(jq -r '.app.name // empty' "$app_json" 2>/dev/null || true)
  ps=$(jq -r '.app.slug // empty' "$app_json" 2>/dev/null || true)
  if [ -n "${pn:-}" ] && [ "$pn" != "null" ]; then DEFAULT_NAME="$pn"; fi
  if [ -n "${ps:-}" ] && [ "$ps" != "null" ]; then PAYLOAD_SLUG="$ps"; fi
  echoc dim "Prefilled from $app_json: name=\"$DEFAULT_NAME\", slug=\"$PAYLOAD_SLUG\"."
}
mtx_install_prefill_from_payload_app

echo ""
echoc cyan "Install payload into project"
echoc dim "Project root: $PROJECT_ROOT"
echoc dim "Config file:  $CONFIG_PATH"
echo ""

read -rp "$(echo -e "${bold:-}Display name:${reset:-} [${DEFAULT_NAME}] ")" INPUT_NAME
INPUT_NAME="$(trim "${INPUT_NAME:-$DEFAULT_NAME}")"
[ -n "$INPUT_NAME" ] || INPUT_NAME="$DEFAULT_NAME"

read -rp "$(echo -e "${bold:-}Slug:${reset:-} [${PAYLOAD_SLUG}] ")" INPUT_SLUG
INPUT_SLUG="$(slugify "$(trim "${INPUT_SLUG:-$PAYLOAD_SLUG}")")"
[ -n "$INPUT_SLUG" ] || INPUT_SLUG="$PAYLOAD_SLUG"

# When redirected from a payload, defaults shift: the payload lives as a sibling repo, so
# source.path = ../<payload-id> is the canonical reference (see rule-of-law §1 2026-04-20).
DEFAULT_SRC_CHOICE="1"
DEFAULT_SIBLING_PATH=""
if [ "${REDIRECTED_FROM_PAYLOAD:-0}" = "1" ]; then
  DEFAULT_SRC_CHOICE="2"
  DEFAULT_SIBLING_PATH="../$PAYLOAD_ID"
fi

echo ""
echo "Payload source type:"
echo "  1) package (npm install)"
echo "  2) path"
echo "  3) git"
read -rp "Choice [${DEFAULT_SRC_CHOICE}]: " SRC_CHOICE
SRC_CHOICE="${SRC_CHOICE:-$DEFAULT_SRC_CHOICE}"

SOURCE_KIND="package"
SOURCE_VALUE=""
SOURCE_REF=""
case "$SRC_CHOICE" in
  1|package)
    SOURCE_KIND="package"
    read -rp "Package name [${DEFAULT_PACKAGE}]: " SOURCE_VALUE
    SOURCE_VALUE="$(trim "${SOURCE_VALUE:-$DEFAULT_PACKAGE}")"
    [ -n "$SOURCE_VALUE" ] || SOURCE_VALUE="$DEFAULT_PACKAGE"
    ;;
  2|path)
    SOURCE_KIND="path"
    if [ -n "$DEFAULT_SIBLING_PATH" ]; then
      read -rp "Path (relative to project root, or absolute) [${DEFAULT_SIBLING_PATH}]: " SOURCE_VALUE
      SOURCE_VALUE="$(trim "${SOURCE_VALUE:-$DEFAULT_SIBLING_PATH}")"
    else
      read -rp "Path (relative to project root, or absolute): " SOURCE_VALUE
      SOURCE_VALUE="$(trim "$SOURCE_VALUE")"
    fi
    [ -n "$SOURCE_VALUE" ] || { error "Path source requires a value."; exit 1; }
    ;;
  3|git)
    SOURCE_KIND="git"
    read -rp "Git URL (https://... or git@...): " SOURCE_VALUE
    SOURCE_VALUE="$(trim "$SOURCE_VALUE")"
    [ -n "$SOURCE_VALUE" ] || { error "Git source requires URL."; exit 1; }
    read -rp "Git ref [main]: " SOURCE_REF
    SOURCE_REF="$(trim "${SOURCE_REF:-main}")"
    ;;
  *)
    error "Invalid source choice."
    exit 1
    ;;
esac

echo ""
read -rp "Set as default/fallback app for unmatched hosts? [y/N]: " MAKE_DEFAULT
MAKE_DEFAULT="$(echo "${MAKE_DEFAULT:-n}" | tr '[:upper:]' '[:lower:]')"

ROUTE_PATH_PREFIX=""
DOMAINS_CSV=""
if [ "$MAKE_DEFAULT" = "y" ] || [ "$MAKE_DEFAULT" = "yes" ]; then
  ROUTE_PATH_PREFIX=""
else
  read -rp "Route path prefix (empty for root, e.g. /portal): " ROUTE_PATH_PREFIX
  ROUTE_PATH_PREFIX="$(trim "$ROUTE_PATH_PREFIX")"
  if [ -n "$ROUTE_PATH_PREFIX" ] && [ "$ROUTE_PATH_PREFIX" != "/" ] && [[ "$ROUTE_PATH_PREFIX" != /* ]]; then
    ROUTE_PATH_PREFIX="/$ROUTE_PATH_PREFIX"
  fi
  [ "$ROUTE_PATH_PREFIX" = "/" ] && ROUTE_PATH_PREFIX=""
  read -rp "Domains/hosts (comma-separated, optional): " DOMAINS_CSV
  DOMAINS_CSV="$(trim "$DOMAINS_CSV")"
fi

read -rp "API prefix (blank = default /api/<slug>): " API_PREFIX
API_PREFIX="$(trim "$API_PREFIX")"
if [ -n "$API_PREFIX" ] && [[ "$API_PREFIX" != /* ]]; then
  API_PREFIX="/$API_PREFIX"
fi

if [ "$SOURCE_KIND" = "path" ]; then
  # Rule-of-law §1 2026-04-24: enforce framework-owned Tailwind on the path source the
  # operator picked. Resolve relative to the host project root, the same way the host
  # would later read this entry. We deliberately don't try to enforce on package sources
  # (no on-disk tree to inspect at install time) — the source-of-truth payload repos are
  # already gated by the redirect-mode check above.
  _payload_src_dir=""
  if [[ "$SOURCE_VALUE" == /* ]]; then
    _payload_src_dir="$SOURCE_VALUE"
  else
    _payload_src_dir="$(cd "$PROJECT_ROOT" 2>/dev/null && cd "$SOURCE_VALUE" 2>/dev/null && pwd -P || true)"
  fi
  if [ -n "$_payload_src_dir" ] && [ -d "$_payload_src_dir" ]; then
    mtx_install_assert_no_payload_tailwind "$_payload_src_dir" || exit $?
  fi
  unset _payload_src_dir
fi

if [ "$SOURCE_KIND" = "package" ]; then
  echo ""
  info "Installing package in $PROJECT_ROOT ..."
  (
    cd "$PROJECT_ROOT"
    mtx_run npm install "$SOURCE_VALUE"
  )
  success "Installed package: $SOURCE_VALUE"
fi

echo ""
info "Updating $CONFIG_PATH ..."

PAYLOAD_ID="$PAYLOAD_ID" \
APP_NAME="$INPUT_NAME" \
APP_SLUG="$INPUT_SLUG" \
SOURCE_KIND="$SOURCE_KIND" \
SOURCE_VALUE="$SOURCE_VALUE" \
SOURCE_REF="$SOURCE_REF" \
ROUTE_PATH_PREFIX="$ROUTE_PATH_PREFIX" \
DOMAINS_CSV="$DOMAINS_CSV" \
API_PREFIX="$API_PREFIX" \
CONFIG_PATH="$CONFIG_PATH" \
node <<'EOF'
const fs = require("fs");

const configPath = process.env.CONFIG_PATH;
const payloadId = process.env.PAYLOAD_ID;
const appName = process.env.APP_NAME;
const appSlug = process.env.APP_SLUG;
const sourceKind = process.env.SOURCE_KIND;
const sourceValue = process.env.SOURCE_VALUE;
const sourceRef = process.env.SOURCE_REF;
const routePathPrefix = process.env.ROUTE_PATH_PREFIX || "";
const domainsCsv = process.env.DOMAINS_CSV || "";
const apiPrefix = process.env.API_PREFIX || "";

const raw = fs.readFileSync(configPath, "utf8");
const json = JSON.parse(raw);

if (!json || typeof json !== "object") {
  throw new Error("Invalid server config JSON.");
}

const appsKey = Array.isArray(json.apps) ? "apps" : (Array.isArray(json.payloads) ? "payloads" : "apps");
if (!Array.isArray(json[appsKey])) json[appsKey] = [];

let source;
if (sourceKind === "package") {
  source = { package: sourceValue };
} else if (sourceKind === "path") {
  source = { path: sourceValue };
} else if (sourceKind === "git") {
  source = { git: { url: sourceValue, ref: sourceRef || "main" } };
} else {
  throw new Error(`Unsupported source kind: ${sourceKind}`);
}

const domainList = domainsCsv
  .split(",")
  .map((s) => s.trim().toLowerCase())
  .filter(Boolean);

const nextEntry = {
  id: payloadId,
  name: appName,
  slug: appSlug,
  source
};

nextEntry.pathPrefix = routePathPrefix;
if (domainList.length > 0) nextEntry.domains = domainList;
if (apiPrefix) nextEntry.apiPrefix = apiPrefix;

const idx = json[appsKey].findIndex((e) => e && typeof e === "object" && e.id === payloadId);
if (idx >= 0) {
  const prev = json[appsKey][idx] || {};
  const merged = {
    ...prev,
    ...nextEntry,
    source: nextEntry.source,
  };
  if (domainList.length === 0) delete merged.domains;
  if (!apiPrefix) delete merged.apiPrefix;
  json[appsKey][idx] = merged;
} else {
  json[appsKey].push(nextEntry);
}

fs.writeFileSync(configPath, JSON.stringify(json, null, 2) + "\n");
EOF

success "Updated payload entry '$PAYLOAD_ID' in $(basename "$CONFIG_PATH")"

# App Bridge type emitter — regenerate bridge/app/generated.d.ts so that newly-
# installed payloads autocomplete on bridge.app.<slug>.* before the next client
# build. Safe to skip silently when the emitter script isn't present (e.g.
# freshly-cloned host pre-dating project-bridge's App Bridge chunk-9 wiring),
# or when tsx isn't installed yet (payload install can precede npm install on
# the very first bootstrap).
if [ -f "$PROJECT_ROOT/shared/scripts/emit-app-bridge-types.ts" ]; then
  if (cd "$PROJECT_ROOT" && npx --no-install tsx shared/scripts/emit-app-bridge-types.ts >/dev/null 2>&1); then
    success "Regenerated engine/src/bridge/app/generated.d.ts (App Bridge typings)."
  else
    warn "App Bridge type emit skipped (tsx unavailable; run 'npm run emit:app-bridge-types' after deps install)."
  fi
fi

echo ""
echo "Next steps:"
echo "  1) Build host/server:"
echo "     npm run build:server"
echo "  2) Restart local server or redeploy:"
echo "     npm run dev:server"
echo "     # or: mtx deploy staging|production"
echo "  3) Verify routes:"
echo "     - UI route host/path matches domains + pathPrefix"
echo "     - API route uses ${API_PREFIX:-/api/$INPUT_SLUG} (or payload default)"
}
