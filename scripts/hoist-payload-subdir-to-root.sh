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
