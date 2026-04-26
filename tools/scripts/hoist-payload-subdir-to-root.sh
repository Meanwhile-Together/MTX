#!/usr/bin/env bash
# Hoist payloads/<slug>/ to repo root and delete all other top-level files (except .git).
# End state matches payload-admin / template-payload: single SPA at repo root.
#
# Usage:
#   ./hoist-payload-subdir-to-root.sh /abs/path/to/payload-foo          # dry-run
#   ./hoist-payload-subdir-to-root.sh /abs/path/to/payload-foo --apply
#   ./hoist-payload-subdir-to-root.sh --all-workspace /path/to/MT [--apply]
set -euo pipefail

hoist_one() {
  local REPO="$1"
  local APPLY="${2:-0}"

  REPO=$(cd "$REPO" && pwd)
  local base slug inner stage
  base=$(basename "$REPO")
  case "$base" in
    payload-*) ;;
    *) echo "error: repo folder must be payload-* (got $base)" >&2; return 1 ;;
  esac
  slug=${base#payload-}
  inner="$REPO/payloads/$slug"
  if [[ ! -d "$inner" ]]; then
    echo "error: missing app dir $inner" >&2
    return 1
  fi

  if [[ "$APPLY" != "1" ]]; then
    echo "[dry-run] $base: delete all top-level except .git under $REPO, hoist $inner/ -> root (rsync excludes node_modules,dist,.git from copy)."
    return 0
  fi

  stage=$(mktemp -d)
  trap 'rm -rf "$stage"' EXIT

  rsync -a \
    --exclude node_modules \
    --exclude dist \
    --exclude build \
    --exclude .next \
    --exclude .turbo \
    --exclude .git \
    "$inner/" "$stage/"

  # Config triad (rule-of-law §1 2026-04-20): every payload ships its own config/app.json as
  # identity. When hoisting a sub-app that didn't have one (the common legacy case — identity was
  # declared in the outer org's server.json.apps[N].app), scaffold one here from whatever
  # derivable data we have. §5 forbids regressing to the 2026-04-19 hoist that blanket-deleted
  # config/ without preserving this file.
  #
  # metadata.json retirement (rule-of-law §1 2026-04-20): AI Studio-imported payloads carry a
  # metadata.json { name, description, requestFramePermissions, majorCapabilities } at the staged
  # root. We fold `name` / `description` / `requestFramePermissions` into the scaffolded
  # config/app.json.app block (majorCapabilities is discarded — dead boilerplate) and delete
  # metadata.json before the hoist completes so the resulting repo matches template-payload shape.
  local meta_name="" meta_desc="" meta_perms_json="[]"
  if command -v jq &>/dev/null && [[ -f "$stage/metadata.json" ]]; then
    meta_name=$(jq -r '.name // empty' "$stage/metadata.json" 2>/dev/null || true)
    meta_desc=$(jq -r '.description // empty' "$stage/metadata.json" 2>/dev/null || true)
    meta_perms_json=$(jq -c '.requestFramePermissions // []' "$stage/metadata.json" 2>/dev/null || echo '[]')
  fi

  if [[ ! -f "$stage/config/app.json" ]]; then
    mkdir -p "$stage/config"
    local derived_name derived_ver esc_desc
    derived_name="$meta_name"
    if [[ -z "${derived_name:-}" ]]; then
      # Title-case the slug: "aigotchi" → "Aigotchi"; "ai-alarm-clock" → "Ai Alarm Clock".
      derived_name=$(printf '%s' "$slug" | sed -E 's/-+/ /g' | awk '{
        for (i=1; i<=NF; i++) $i = toupper(substr($i,1,1)) tolower(substr($i,2));
        print
      }')
    fi
    derived_ver="1.0.0"
    if command -v jq &>/dev/null && [[ -f "$stage/package.json" ]]; then
      local pv
      pv=$(jq -r '.version // empty' "$stage/package.json" 2>/dev/null || true)
      [[ -n "$pv" ]] && derived_ver="$pv"
    fi
    # Escape description for safe JSON embedding (quotes, backslashes, etc.).
    # Use `jq -n --arg` so we don't pick up stray newlines from here-strings.
    if command -v jq &>/dev/null; then
      esc_desc=$(jq -n --arg s "${meta_desc}" '$s')
    else
      esc_desc="\"${meta_desc//\"/\\\"}\""
    fi
    cat > "$stage/config/app.json" <<JSON
{
  "app": {
    "name": "$derived_name",
    "slug": "$slug",
    "version": "$derived_ver",
    "description": ${esc_desc},
    "requestFramePermissions": ${meta_perms_json}
  },
  "ai": { "inferenceMode": "local", "enableLogging": false },
  "chatbots": [],
  "development": { "port": 3001, "url": "http://localhost" },
  "staging":     { "port": 3001, "url": "https://staging.example.com" },
  "production":  { "port": 3001, "url": "https://api.example.com" }
}
JSON
    echo "[hoist] $base: scaffolded config/app.json (name=$derived_name, slug=$slug, version=$derived_ver, desc=${meta_desc:+yes}, perms=${meta_perms_json})"
  elif [[ -n "$meta_name$meta_desc" || "$meta_perms_json" != "[]" ]] && command -v jq &>/dev/null; then
    # app.json already existed but metadata.json carried fields — fold any missing ones in.
    jq --arg name "$meta_name" \
       --arg desc "$meta_desc" \
       --argjson perms "$meta_perms_json" '
      .app = (.app // {})
      | (if (.app.name // "") == "" and $name != "" then .app.name = $name else . end)
      | (if (.app.description // "") == "" and $desc != "" then .app.description = $desc else . end)
      | (if ((.app.requestFramePermissions // []) | length) == 0 and ($perms | length) > 0
         then .app.requestFramePermissions = $perms else . end)
    ' "$stage/config/app.json" >"$stage/config/app.json.tmp" && mv "$stage/config/app.json.tmp" "$stage/config/app.json"
    echo "[hoist] $base: merged metadata.json fields into existing config/app.json"
  fi

  # metadata.json has been absorbed (or was empty) — strip it so the hoisted repo has no
  # retired-format leftovers.
  if [[ -f "$stage/metadata.json" ]]; then
    rm -f "$stage/metadata.json"
  fi

  cd "$REPO"
  shopt -s dotglob nullglob
  local p b
  for p in ./* ./.[!.]* ./..?*; do
    [[ -e "$p" ]] || continue
    b=$(basename "$p")
    case "$b" in .|..|.git) continue ;; esac
    rm -rf "$p"
  done
  shopt -u dotglob nullglob

  rsync -a "$stage/" "$REPO/"
  rm -rf "$stage"
  trap - EXIT

  if command -v jq &>/dev/null && [[ -f "$REPO/package.json" ]]; then
    jq --arg n "@meanwhile-together/${base}" \
      --arg d "Payload ${slug} — single-app SPA (hoisted from payloads/${slug}; org bundle removed)." \
      '.name=$n | .description=$d' "$REPO/package.json" >"$REPO/package.json.tmp" && mv "$REPO/package.json.tmp" "$REPO/package.json"
  fi

  if [[ ! -f "$REPO/.gitignore" ]]; then
    cat >"$REPO/.gitignore" <<'EOF'
node_modules/
dist/
.DS_Store
*.log
.env
.env.*
!.env.example
EOF
  fi

  echo "[apply] $base hoisted; run: cd \"$REPO\" && npm install && npm run build"
}

apply=0
repo=""
all_ws=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply)
      apply=1
      shift
      ;;
    --all-workspace)
      shift
      all_ws=$(cd "${1:?workspace root}" && pwd)
      shift
      ;;
    *)
      if [[ -n "$repo" ]]; then
        echo "error: unexpected extra arg: $1" >&2
        exit 1
      fi
      repo="$1"
      shift
      ;;
  esac
done

if [[ -n "$all_ws" ]]; then
  n=0
  for d in "$all_ws"/payload-*; do
    [[ -d "$d" ]] || continue
    base=$(basename "$d")
    [[ "$base" == payload-* ]] || continue
    slug=${base#payload-}
    [[ -d "$d/payloads/$slug" ]] || continue
    hoist_one "$d" "$apply" || echo "[warn] $base" >&2
    n=$((n + 1))
  done
  echo "[all-workspace] touched $n candidate repos under $all_ws (apply=$apply)"
  exit 0
fi

if [[ -z "$repo" ]]; then
  echo "usage: $0 <path/to/payload-foo> [--apply]" >&2
  echo "       $0 --all-workspace <path/to/MT> [--apply]" >&2
  exit 1
fi

hoist_one "$repo" "$apply"
