#!/usr/bin/env bash
# MTX: vendor path payloads from config/server.json into ./payloads/<slug>/ and write server.json.railway.
# Invoked by MTX build.sh before org "npm run prepare:railway" (mtx build server / mtx deploy).
#
# Requires: jq, rsync, perl (File::Spec for relpaths), bash.
# Env: MTX_SKIP_PAYLOAD_VENDOR=1 — no-op.
#      MTX_VENDOR_FAIL_ON_ERROR=1 — exit 1 if any payload build failed (default: exit 0 after all attempts).
# Arg: org repo root (default: cwd).
#
# On npm install/build failure: stderr banner, sleep 5s, continue (skip rsync for that app).
set -euo pipefail

BANNER_WIDTH=78

ROOT="$(cd "${1:-.}" && pwd)"
CONFIG_DIR="$ROOT/config"
SERVER_JSON="$CONFIG_DIR/server.json"
RAILWAY_JSON="$CONFIG_DIR/server.json.railway"

MTX_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
MTX_ROOT="$(cd "$MTX_LIB_DIR/.." && pwd)"
# shellcheck source=mtx-vendor-pinned.sh
[ -f "$MTX_LIB_DIR/mtx-vendor-pinned.sh" ] && source "$MTX_LIB_DIR/mtx-vendor-pinned.sh"

mtx_vendor_normalize_payload_dir() {
  local dir="$1"
  [ -d "$dir" ] || return 0
  [ -f "$MTX_ROOT/includes/mtx-predeploy.sh" ] || return 0
  if [ "${MTX_VENDOR_PREDEPLOY_LOADED:-}" != 1 ]; then
    # Loads fixes/root-paths-lib.sh (HTML / Vite base normalization for path-prefixed mounts).
    # shellcheck disable=SC1091
    source "$MTX_ROOT/includes/mtx-predeploy.sh"
    MTX_VENDOR_PREDEPLOY_LOADED=1
  fi
  mtx_predeploy_normalize_payload_dir "$dir" || return 1
}

mtx_vendor_clip() {
  local s="$1" max="$2"
  s="$(echo "$s" | tr -s '[:space:]' ' ')"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  if [ "${#s}" -le "$max" ]; then
    printf '%s' "$s"
  else
    printf '%s…' "${s:0:max-1}"
  fi
}

mtx_vendor_banner_row() {
  local inner=$((BANNER_WIDTH - 4))
  local text
  text="$(mtx_vendor_clip "$1" "$inner")"
  printf '# %-*s #\n' "$inner" "$text"
}

mtx_vendor_print_failure_banner() {
  local label="$1" dir="$2" msg="$3"
  local bar
  bar="$(printf '%*s' "$BANNER_WIDTH" '' | tr ' ' '#')"
  echo "" >&2
  echo "$bar" >&2
  mtx_vendor_banner_row "PAYLOAD BUILD FAILED — vendor will CONTINUE after a 5 second pause" >&2
  mtx_vendor_banner_row "" >&2
  mtx_vendor_banner_row "$label" >&2
  mtx_vendor_banner_row "$dir" >&2
  mtx_vendor_banner_row "$msg" >&2
  echo "$bar" >&2
  echo "" >&2
}

mtx_vendor_relpath() {
  local from="$1" base="$2"
  perl -e 'use File::Spec; print File::Spec->abs2rel($ARGV[0], $ARGV[1]), "\n"' "$from" "$base"
}

# Resolve rel (relative to projectRoot) to an absolute directory path.
mtx_vendor_resolve_path() {
  local projectRoot="$1" rel="$2"
  (cd "$projectRoot" && test -e "$rel" && cd "$rel" && pwd) || return 1
}

mtx_vendor_safe_slug() {
  local id="$1" slug="$2" idx="$3"
  local s="${slug:-${id:-}}"
  [ -n "$s" ] || s="app-$idx"
  s="$(printf '%s' "$s" | tr -cs 'a-zA-Z0-9_-' '-')"
  s="${s#-}"
  s="${s%-}"
  [ -n "$s" ] || s="app-$idx"
  printf '%s' "$s"
}

mtx_vendor_resolve_build_dir() {
  local resolved="$1" slug="$2"
  local nested="$resolved/payloads/$slug"
  if [ -f "$nested/package.json" ] && jq -e '.scripts.build | type == "string"' "$nested/package.json" >/dev/null 2>&1; then
    echo "[vendor-payloads] nested build dir: $nested" >&2
    echo "$nested"
  else
    echo "$resolved"
  fi
}

mtx_vendor_run_build() {
  local dir="$1"
  if [ ! -f "$dir/package.json" ]; then
    echo "[vendor-payloads] no package.json in $dir" >&2
    return 1
  fi
  echo "[vendor-payloads] npm install in $dir"
  (cd "$dir" && npm install) || return 1
  if jq -e '.scripts.build | type == "string"' "$dir/package.json" >/dev/null 2>&1; then
    echo "[vendor-payloads] npm run build in $dir"
    (cd "$dir" && npm run build) || return 1
  else
    echo "[vendor-payloads] no \"build\" script in $dir; expected dist/ may be missing" >&2
  fi
  return 0
}

# Returns 0 on success, 1 on failure (after banner + sleep).
mtx_vendor_run_build_or_banner() {
  local dir="$1" label="$2"
  if mtx_vendor_run_build "$dir"; then
    return 0
  fi
  mtx_vendor_print_failure_banner "$label" "$dir" "npm install or npm run build failed (see output above)"
  echo "[vendor-payloads] pausing 5 seconds before continuing with remaining payloads…" >&2
  sleep 5
  return 1
}

if [ "${MTX_SKIP_PAYLOAD_VENDOR:-}" = "1" ]; then
  echo "vendor-payloads-from-config: MTX_SKIP_PAYLOAD_VENDOR=1, skip"
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "❌ vendor-payloads-from-config: jq is required" >&2
  exit 1
fi
if ! command -v perl >/dev/null 2>&1; then
  echo "❌ vendor-payloads-from-config: perl is required" >&2
  exit 1
fi

if [ ! -f "$SERVER_JSON" ]; then
  echo "vendor-payloads-from-config: no config/server.json, skip"
  [ ! -f "$RAILWAY_JSON" ] || rm -f "$RAILWAY_JSON"
  exit 0
fi

if declare -F mtx_vendor_is_pinned &>/dev/null && mtx_vendor_is_pinned "$ROOT" payloads; then
  if declare -F mtx_vendor_console_log_pinned &>/dev/null; then
    mtx_vendor_console_log_pinned "$ROOT" payloads ""
  fi
  echo "vendor-payloads-from-config: payloads pinned — skipping path payload vendor (see line above)." >&2
  exit 0
fi

APP_KEY=""
if jq -e '.apps | type == "array"' "$SERVER_JSON" >/dev/null 2>&1; then
  APP_KEY=apps
elif jq -e '.payloads | type == "array"' "$SERVER_JSON" >/dev/null 2>&1; then
  APP_KEY=payloads
else
  echo "vendor-payloads-from-config: no apps[] or payloads[], skip"
  exit 0
fi

WORK="$(mktemp)"
OUT="$(mktemp)"
trap 'rm -f "${WORK:-}" "${OUT:-}"' EXIT

# Ensure admin entry (same object shape as Node implementation).
jq --arg k "$APP_KEY" '
  . as $r |
  ($r[$k]) as $arr |
  if ($arr | any(((.id // "") | ascii_downcase) == "admin" or ((.slug // "") | ascii_downcase) == "admin")) then $r
  else
    $r | .[$k] = ([{
      "id": "admin",
      "name": "Admin",
      "slug": "admin",
      "pathPrefix": "/",
      "staticDir": "dist",
      "apiPrefix": "/api",
      "runAsMaster": false,
      "app": {"name": "Admin", "slug": "admin", "version": "1.0.0"},
      "source": {"path": "../payload-admin"}
    }] + $arr)
  end
' "$SERVER_JSON" >"$WORK"

projectRoot="$(jq -r '.server.projectRoot // "."' "$WORK")"
if [[ "$projectRoot" != /* ]]; then
  projectRoot="$(cd "$CONFIG_DIR/$projectRoot" && pwd)"
else
  projectRoot="$(cd "$projectRoot" && pwd)"
fi

cp -f "$WORK" "$OUT"

rewrote=false
vendor_build_failures=0
n="$(jq --arg k "$APP_KEY" '.[$k] | length' "$WORK")"

for ((i = 0; i < n; i++)); do
  src_path="$(jq -r --argjson i "$i" --arg k "$APP_KEY" '.[$k][$i].source.path // empty' "$WORK")"
  [ -n "$src_path" ] || continue
  rel="${src_path#"${src_path%%[![:space:]]*}"}"
  rel="${rel%"${rel##*[![:space:]]}"}"
  case "$rel" in '' | '.' | './') continue ;; esac

  entry_id="$(jq -r --argjson i "$i" --arg k "$APP_KEY" '.[$k][$i].id // empty' "$WORK")"
  if ! resolved="$(mtx_vendor_resolve_path "$projectRoot" "$rel")"; then
    echo "[vendor-payloads] skip \"$entry_id\": could not resolve path under $projectRoot: $rel" >&2
    continue
  fi

  if [ ! -d "$resolved" ]; then
    echo "[vendor-payloads] skip \"$entry_id\": path does not exist: $resolved" >&2
    continue
  fi
  if [ ! -f "$resolved/package.json" ]; then
    echo "[vendor-payloads] skip \"$entry_id\": no package.json under $resolved" >&2
    continue
  fi

  slug="$(mtx_vendor_safe_slug \
    "$(jq -r --argjson i "$i" --arg k "$APP_KEY" '.[$k][$i].id // empty' "$WORK")" \
    "$(jq -r --argjson i "$i" --arg k "$APP_KEY" '.[$k][$i].slug // empty' "$WORK")" \
    "$i")"

  build_dir="$(mtx_vendor_resolve_build_dir "$resolved" "$slug")"

  rel_to_org="$(mtx_vendor_relpath "$resolved" "$ROOT" || true)"
  in_repo=false
  case "$rel_to_org" in
    payloads|payloads/*|./payloads|./payloads/*) in_repo=true ;;
  esac
  if [ "$in_repo" = true ]; then
    echo "[vendor-payloads] build in-repo payload $build_dir"
    if mtx_vendor_run_build_or_banner "$build_dir" "in-repo \"$entry_id\""; then
      mtx_vendor_normalize_payload_dir "$build_dir" || true
    else
      vendor_build_failures=$((vendor_build_failures + 1))
    fi
    continue
  fi

  dest="$ROOT/payloads/$slug"
  echo "[vendor-payloads] build + vendor \"$entry_id\" ($resolved -> $dest)"
  if ! mtx_vendor_run_build_or_banner "$build_dir" "payload \"$entry_id\""; then
    vendor_build_failures=$((vendor_build_failures + 1))
    echo "[vendor-payloads] skipping rsync for \"$entry_id\" (build failed); not updating server.json.railway path for this app" >&2
    continue
  fi

  mkdir -p "$(dirname "$dest")"
  rsync -a --delete --exclude node_modules --exclude .git "$resolved/" "$dest/"
  mtx_vendor_normalize_payload_dir "$dest" || true

  rel_out="./payloads/$slug"
  TMP="$(mktemp)"
  jq --argjson idx "$i" --arg k "$APP_KEY" --arg p "$rel_out" '(.[$k][$idx].source.path) = $p' "$OUT" >"$TMP"
  mv -f "$TMP" "$OUT"
  rewrote=true
done

if [ "$rewrote" = true ]; then
  jq '.' "$OUT" >"$RAILWAY_JSON"
  echo "[vendor-payloads] wrote $(basename "$RAILWAY_JSON")"
elif [ -f "$RAILWAY_JSON" ]; then
  rm -f "$RAILWAY_JSON"
  echo "[vendor-payloads] removed stale server.json.railway (nothing to rewrite)"
fi

if [ "$vendor_build_failures" -gt 0 ]; then
  bar="$(printf '%*s' "$BANNER_WIDTH" '' | tr ' ' '#')"
  echo "" >&2
  echo "$bar" >&2
  mtx_vendor_banner_row "vendor-payloads: $vendor_build_failures payload build(s) failed (see banners above)." >&2
  mtx_vendor_banner_row "Artifact may be incomplete for those apps; remaining payloads were processed." >&2
  mtx_vendor_banner_row "Set MTX_VENDOR_FAIL_ON_ERROR=1 to exit with code 1." >&2
  echo "$bar" >&2
  echo "" >&2
  if [ "${MTX_VENDOR_FAIL_ON_ERROR:-}" = "1" ]; then
    exit 1
  fi
fi

exit 0
