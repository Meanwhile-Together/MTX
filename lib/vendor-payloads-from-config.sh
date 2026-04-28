#!/usr/bin/env bash
# MTX: vendor path payloads from config/server.json into ./payloads/<slug>/ and write server.json.railway.
# Invoked by MTX build.sh before project/prepare-railway-artifact.sh (mtx build server / mtx deploy).
#
# Requires: jq, rsync, perl (File::Spec for relpaths), bash.
# Env: MTX_SKIP_PAYLOAD_VENDOR=1 — no-op.
#      MTX_VENDOR_FAIL_ON_ERROR=1 — exit 1 if any payload build failed (default: exit 0 after all attempts).
#      MTX_VENDOR_PROGRESS=0 — plain one-line start/end (no growing dots on /dev/tty).
#      MTX_VENDOR_DOT_SEC=1 — seconds between extra dots (default 1) while vendoring.
# Arg: org repo root (default: cwd).
#
# On npm install/build failure: stderr banner, sleep 5s, continue (skip rsync for that app).
set -euo pipefail

BANNER_WIDTH=78

ROOT="$(cd "${1:-.}" && pwd)"
# Monorepo parent: sibling of $ROOT that contains project-bridge/. Used when rewriting
# `../project-bridge/...` inside in-repo payloads whose configs still assume sibling layout.
org_parent="$(cd "$ROOT/.." && pwd)"
CONFIG_DIR="$ROOT/config"
SERVER_JSON="$CONFIG_DIR/server.json"
RAILWAY_JSON="$CONFIG_DIR/server.json.railway"

MTX_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
MTX_ROOT="$(cd "$MTX_LIB_DIR/.." && pwd)"
# shellcheck source=mtx-vendor-pinned.sh
[ -f "$MTX_LIB_DIR/mtx-vendor-pinned.sh" ] && source "$MTX_LIB_DIR/mtx-vendor-pinned.sh"
# shellcheck source=../includes/mtx-run.sh
[ -f "$MTX_ROOT/includes/mtx-run.sh" ] && source "$MTX_ROOT/includes/mtx-run.sh"
[ -z "${MTX_VERBOSE+x}" ] && mtx_run() { "$@"; }
declare -F mtx_run &>/dev/null || mtx_run() { "$@"; }

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

# One-line “Vendoring 'slug' …” with growing dots on /dev/tty (visible even if stderr is muted).
# MTX_VENDOR_PROGRESS=0 — plain one-line messages, no animation. MTX_VENDOR_DOT_SEC=1 — seconds between dots.
mtx_vendor_progress_tty() {
  # `[ -w /dev/tty ]` can lie in some CI / IDE terminals; a real append probe is authoritative.
  # Prefer tty for interactive visibility; fall back to stderr, then discard (background jobs may
  # lose tty and bash would otherwise print "No such device or address" on open).
  if { : >>/dev/tty; } 2>/dev/null; then
    printf '%s\n' /dev/tty
  elif { : >>/dev/stderr; } 2>/dev/null; then
    printf '%s\n' /dev/stderr
  else
    printf '%s\n' /dev/null
  fi
}

MTX_VENDOR_VPROG_PID=""
MTX_VENDOR_VPROG_SLUG=""
MTX_VENDOR_VPROG_T=""

mtx_vendor_vprog_stop() {
  if [ -n "${MTX_VENDOR_VPROG_PID:-}" ]; then
    kill "$MTX_VENDOR_VPROG_PID" 2>/dev/null || true
    wait "$MTX_VENDOR_VPROG_PID" 2>/dev/null || true
  fi
  MTX_VENDOR_VPROG_PID=""
}

# args: slug
mtx_vendor_vprog_begin() {
  local slug="$1"
  mtx_vendor_vprog_stop
  MTX_VENDOR_VPROG_SLUG="$slug"
  MTX_VENDOR_VPROG_T="$(mtx_vendor_progress_tty)"
  # Background dot progress runs in a subshell; /dev/tty may be unusable there even when the
  # parent probe passed (agent/CI). Prefer stderr or discard for the animation worker only.
  if [ "${MTX_VENDOR_PROGRESS:-1}" != "0" ] && [ "${MTX_VENDOR_VPROG_T:-}" = "/dev/tty" ]; then
    if { : >>/dev/stderr; } 2>/dev/null; then
      MTX_VENDOR_VPROG_T=/dev/stderr
    else
      MTX_VENDOR_VPROG_T=/dev/null
    fi
  fi
  if [ "${MTX_VENDOR_PROGRESS:-1}" = "0" ]; then
    MTX_VENDOR_VPROG_SLUG="$slug"
    MTX_VENDOR_VPROG_T="$(mtx_vendor_progress_tty)"
    printf "  Vendoring '%s'…\n" "$slug" >>"${MTX_VENDOR_VPROG_T}" 2>/dev/null || printf "  Vendoring '%s'…\n" "$slug" >&2
    return 0
  fi
  (
    local sec="${MTX_VENDOR_DOT_SEC:-1}"
    local dots="..."
    while :; do
      sleep "$sec"
      dots="${dots}."
      printf "\r\033[0K  Vendoring '%s' %s" "$slug" "$dots" >>"${MTX_VENDOR_VPROG_T}" 2>/dev/null || true
    done
  ) &
  MTX_VENDOR_VPROG_PID=$!
  printf "\r\033[0K  Vendoring '%s' ..." "$slug" >>"${MTX_VENDOR_VPROG_T}" 2>/dev/null || printf "\r\033[0K  Vendoring '%s' ..." "$slug" >&2
}

# arg: ok | fail
mtx_vendor_vprog_end() {
  local st="${1:-ok}"
  local t="${MTX_VENDOR_VPROG_T:-$(mtx_vendor_progress_tty)}"
  local slug="${MTX_VENDOR_VPROG_SLUG:-}"
  mtx_vendor_vprog_stop
  local tail="Finished"
  [ "$st" = "fail" ] && tail="Finished (build failed)"
  if [ "${MTX_VENDOR_PROGRESS:-1}" = "0" ]; then
    printf "  Vendoring '%s' — %s\n" "$slug" "$tail" >>"$t" 2>/dev/null || printf "  Vendoring '%s' — %s\n" "$slug" "$tail" >&2
  else
    printf "\r\033[0K  Vendoring '%s' ... %s\n" "$slug" "$tail" >>"$t" 2>/dev/null || printf "\r\033[0K  Vendoring '%s' ... %s\n" "$slug" "$tail" >&2
  fi
  MTX_VENDOR_VPROG_SLUG=""
  MTX_VENDOR_VPROG_T=""
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

# Rewrite relative monorepo paths inside a vendored payload. The source lives next to
# `project-bridge/` (so it uses `../project-bridge/...`), but once rsync'd into
# $ROOT/payloads/<slug>/ those relpaths escape the org tree. Compute the correct relpath
# from the new dest to each known sibling monorepo dir and update package.json / tsconfig.json
# / vite.config.*. Without this, npm install creates broken file:../project-bridge symlinks
# and vite fails with "Cannot find base config file ../project-bridge/tsconfig.json".
#
# Also applies to in-repo payloads that were committed alongside a sibling-layout template
# (e.g. org-project-bridge/payloads/admin/ inherited `../project-bridge/...` from a time when
# the payload lived as a sibling of project-bridge). The generic rule: whatever depth the
# payload ends up at under the org root, rewrite `../project-bridge` to the relpath from
# the payload dir to the monorepo parent (`$org_root/..`).
mtx_vendor_rewrite_monorepo_paths() {
  local dest="$1" src="$2" org_root="$3" override_new_rel="${4:-}"
  [ -d "$dest" ] || return 0
  [ -n "$org_root" ] || return 0

  local src_parent new_rel
  if [ -n "$override_new_rel" ]; then
    new_rel="$override_new_rel"
  else
    [ -d "$src" ] || return 0
    src_parent="$(cd "$src" && cd .. && pwd)"
    new_rel="$(mtx_vendor_relpath "$src_parent" "$dest")"
  fi
  [ -n "$new_rel" ] || return 0
  # Guard: only rewrite when the relpath actually changed (out-of-repo vend, dest nested).
  case "$new_rel" in ".."|"..") ;; "../"*) ;; *) return 0 ;; esac
  [ "$new_rel" != ".." ] || return 0

  # We're rewriting token "../<sibling>" → "$new_rel/<sibling>" inside the payload.
  # `..` is the token emitted by source payloads that live as siblings of the monorepo.
  export MTX_NEW_REL="$new_rel"

  local pkg="$dest/package.json"
  if [ -f "$pkg" ]; then
    local tmp
    tmp="$(mktemp)"
    # Only touch `file:..` deps (the pattern npm uses for local file links).
    perl -pe 's{"file:\.\./}{"file:$ENV{MTX_NEW_REL}/}g' <"$pkg" >"$tmp" || { rm -f "$tmp"; unset MTX_NEW_REL; return 0; }
    if ! cmp -s "$pkg" "$tmp"; then
      mv -f "$tmp" "$pkg"
      echo "[vendor-payloads] rewrote monorepo file: paths in $(basename "$dest")/package.json (→ $new_rel/)"
    else
      rm -f "$tmp"
    fi
    # Drop stale package-lock so npm re-resolves with new file: targets (old lock pins the
    # broken "../project-bridge/..." resolution and causes npm to recreate broken symlinks).
    [ -f "$dest/package-lock.json" ] && rm -f "$dest/package-lock.json"
  fi

  local tsc="$dest/tsconfig.json"
  if [ -f "$tsc" ]; then
    local tmp
    tmp="$(mktemp)"
    perl -pe 's{"\.\./project-bridge}{"$ENV{MTX_NEW_REL}/project-bridge}g' <"$tsc" >"$tmp" || { rm -f "$tmp"; unset MTX_NEW_REL; return 0; }
    if ! cmp -s "$tsc" "$tmp"; then
      mv -f "$tmp" "$tsc"
      echo "[vendor-payloads] rewrote ../project-bridge in $(basename "$dest")/tsconfig.json"
    else
      rm -f "$tmp"
    fi
  fi

  local vc
  for vc in "$dest/vite.config.ts" "$dest/vite.config.mts" "$dest/vite.config.js" "$dest/vite.config.mjs"; do
    [ -f "$vc" ] || continue
    local tmp
    tmp="$(mktemp)"
    perl -pe "s{(['\"])\\.\\./project-bridge}{\$1\$ENV{MTX_NEW_REL}/project-bridge}g" <"$vc" >"$tmp" || { rm -f "$tmp"; continue; }
    if ! cmp -s "$vc" "$tmp"; then
      mv -f "$tmp" "$vc"
      echo "[vendor-payloads] rewrote ../project-bridge in $(basename "$dest")/$(basename "$vc")"
    else
      rm -f "$tmp"
    fi
  done

  # Tailwind/PostCSS configs embed content globs that reference sibling monorepo dirs
  # (e.g. `'../project-bridge/engine/**/*.{ts,tsx}'`). Without this rewrite, Tailwind JIT
  # sees an empty content set for engine/ui, silently strips every class used only there
  # (bg-bg-primary, text-text-primary, the whole Layout/Auth/Sidebar ensemble), and ships
  # an ~8 KB CSS file instead of ~22 KB. Symptom: perfectly-laid-out React tree with
  # invisible/washed-out text and a blank main pane. Keep this in sync with the vite/tsconfig
  # rewrites above.
  local cfg
  for cfg in "$dest/tailwind.config.js" "$dest/tailwind.config.mjs" "$dest/tailwind.config.cjs" "$dest/tailwind.config.ts" "$dest/postcss.config.js" "$dest/postcss.config.mjs" "$dest/postcss.config.cjs"; do
    [ -f "$cfg" ] || continue
    local tmp
    tmp="$(mktemp)"
    perl -pe "s{(['\"])\\.\\./project-bridge}{\$1\$ENV{MTX_NEW_REL}/project-bridge}g" <"$cfg" >"$tmp" || { rm -f "$tmp"; continue; }
    if ! cmp -s "$cfg" "$tmp"; then
      mv -f "$tmp" "$cfg"
      echo "[vendor-payloads] rewrote ../project-bridge in $(basename "$dest")/$(basename "$cfg")"
    else
      rm -f "$tmp"
    fi
  done

  unset MTX_NEW_REL

  return 0
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
  if [ "${MTX_VERBOSE:-1}" -ge 2 ]; then
    echo "[vendor-payloads] npm install in $dir" >&2
  fi
  (cd "$dir" && mtx_run npm install) || return 1
  if jq -e '.scripts.build | type == "string"' "$dir/package.json" >/dev/null 2>&1; then
    if [ "${MTX_VERBOSE:-1}" -ge 2 ]; then
      echo "[vendor-payloads] npm run build in $dir" >&2
    fi
    (cd "$dir" && mtx_run npm run build) || return 1
  else
    echo "[vendor-payloads] no \"build\" script in $dir; expected dist/ may be missing" >&2
  fi
  return 0
}

# Reap stale sibling compile outputs under a sibling project-bridge BEFORE any
# payload bundler (vite/rollup) runs against it. Payloads import from
# @meanwhile-together/shared via the root tsconfig `paths` → `shared/src/*.ts`;
# bundlers do exact-extension lookup first, so a stale `shared/src/foo.js` next
# to `foo.ts` wins silently and the payload build surfaces with "export X not
# found" or a snapshot of last-build exports. See project-bridge/docs/rule-of-law.md
# §1 2026-04-22 "Stale sibling .js shadow trap".
#
# Runs once per vendor pass, before the per-payload build loop. Uses the
# project-bridge reaper script when available (authoritative target list); falls
# back to an inline sweep when vendoring against a pinned/cached project-bridge
# that lacks the script. Never fails the vendor pass — debris removal is fire-
# and-forget; the payload build that follows surfaces any remaining issue.
mtx_vendor_reap_project_bridge_stale() {
  local projectRoot="$1"
  [ -n "$projectRoot" ] || return 0
  local pb=""
  local cand
  for cand in \
    "$projectRoot/../project-bridge" \
    "$projectRoot/vendor/project-bridge" \
    "${PROJECT_BRIDGE_ROOT:-}"
  do
    [ -n "$cand" ] || continue
    if [ -f "$cand/package.json" ] && [ -d "$cand/shared/src" ]; then
      pb="$(cd "$cand" && pwd)"
      break
    fi
  done
  [ -n "$pb" ] || return 0

  if [ -x "$pb/scripts/reap-stale-compiled.sh" ]; then
    PB_ROOT="$pb" bash "$pb/scripts/reap-stale-compiled.sh" || true
    return 0
  fi

  # Fallback: inline sweep (keep in sync with scripts/reap-stale-compiled.sh).
  local found=0 rel dir
  for rel in shared/src shared/types shared/config engine/src ui/src demo/src admin/src; do
    dir="$pb/$rel"
    [ -d "$dir" ] || continue
    local hits
    hits="$(find "$dir" \
      \( -name '*.js' -o -name '*.js.map' -o -name '*.d.ts.map' \
         -o \( -name '*.d.ts' ! -name '*-env.d.ts' \) \) \
      -type f 2>/dev/null | wc -l | tr -d ' ')"
    [ "$hits" -gt 0 ] 2>/dev/null || continue
    find "$dir" \
      \( -name '*.js' -o -name '*.js.map' -o -name '*.d.ts.map' \
         -o \( -name '*.d.ts' ! -name '*-env.d.ts' \) \) \
      -type f -delete 2>/dev/null || true
    echo "[vendor-payloads] reaped $hits stale compile output(s) under project-bridge/$rel/" >&2
    found=$((found + hits))
  done
  if [ "$found" -gt 0 ]; then
    echo "[vendor-payloads] removed $found stale sibling .js/.d.ts/.map file(s) under $pb" >&2
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
  rm -f "$ROOT/.mtx/path-vendored-payload-slugs"
  exit 0
fi

if declare -F mtx_vendor_is_pinned &>/dev/null && mtx_vendor_is_pinned "$ROOT" payloads; then
  if declare -F mtx_vendor_console_log_pinned &>/dev/null; then
    mtx_vendor_console_log_pinned "$ROOT" payloads ""
  fi
  echo "vendor-payloads-from-config: payloads pinned — skipping path payload vendor (see line above)." >&2
  rm -f "$ROOT/.mtx/path-vendored-payload-slugs"
  exit 0
fi

APP_KEY=""
if jq -e '.apps | type == "array"' "$SERVER_JSON" >/dev/null 2>&1; then
  APP_KEY=apps
elif jq -e '.payloads | type == "array"' "$SERVER_JSON" >/dev/null 2>&1; then
  APP_KEY=payloads
else
  echo "vendor-payloads-from-config: no apps[] or payloads[], skip"
  rm -f "$ROOT/.mtx/path-vendored-payload-slugs"
  exit 0
fi

WORK="$(mktemp)"
OUT="$(mktemp)"
trap 'mtx_vendor_vprog_stop; rm -f "${WORK:-}" "${OUT:-}"' EXIT

# Ensure admin entry (same object shape as Node implementation).
# Detect an existing admin by: id|slug|name == "admin" (case-insensitive) OR id|name
# contains "admin" OR source.path resolves to a dir named "payload-admin" / "admin".
# Without the broader check, orgs that list admin as id="payload-admin" (slug null) get a
# duplicate synthesized entry, which the unified server flags as "Duplicate API prefix /api".
#
# Invariant enforced here (rule-of-law 2026-04-22): admin is always root-mounted — never
# under `/admin` — so any EXISTING admin entry whose pathPrefix isn't "/" or "" gets
# rewritten in-place. Mirrors `shared/src/server/config.ts :: applyServerEnvOverrides`
# so runtime + vendored config agree even when one runs without the other (e.g. Railway
# build step vendors without booting the server). The eventual `default:true` tag on
# apps[] will replace this special-case; until then this is the single source of truth.
jq --arg k "$APP_KEY" '
  def norm: if . == null then "" else (tostring | ascii_downcase) end;
  def _basename(p): (p | norm | sub("/+$"; "") | split("/") | last // "");
  def is_admin:
    ((.id | norm) == "admin")
    or ((.slug | norm) == "admin")
    or ((.name | norm) == "admin")
    or ((.id | norm) | test("(^|[-_/])(admin|payload-admin)($|[-_/])"))
    or ((.name | norm) | test("(^|[-_/])(admin|payload-admin)($|[-_/])"))
    or (_basename(.source.path // "") | IN("admin", "payload-admin"));
  # Orgs ship a placeholder ./payloads/admin in server.json so the mux shape is obvious, but the
  # real tree lives once in the workspace as ../payload-admin (sibling of the org repo). mtx deploy
  # vendors from that single checkout — no per-org fork of admin to maintain.
  def admin_path_placeholder(p):
    if p == null then true
    else
      (p | tostring | sub("^\\s+|\\s+$"; "")) as $t
      | ($t == "" or $t == "./payloads/admin" or $t == "payloads/admin"
         or $t == "./payloads/admin/" or $t == "payloads/admin/"
         or ($t | test("^\\.?/?payloads/admin/?$")))
    end;
  def normalize_admin_entry:
    (. + {"pathPrefix": "/"}) as $e
    | if ($e.source | type) != "object" then
        $e | .source = {"path": "../payload-admin"}
      elif admin_path_placeholder($e.source.path) then
        $e | .source = ($e.source + {"path": "../payload-admin"})
      else
        $e
      end;
  # Same pattern as admin: orgs often commit ./payloads/vibe-check with only config/ + package.json.
  # The real Vite app lives once as ../payload-vibe-check (sibling of the org). Building the stub
  # dir fails with "Could not resolve entry module index.html".
  def is_vibe_check:
    ((.id | norm) == "payload-vibe-check")
    or ((.slug | norm) == "vibe-check")
    or ((.name | norm) == "vibe check");
  def vibe_check_path_placeholder(p):
    if p == null then true
    else
      (p | tostring | sub("^\\s+|\\s+$"; "")) as $t
      | ($t == "" or $t == "./payloads/vibe-check" or $t == "payloads/vibe-check"
         or $t == "./payloads/vibe-check/" or $t == "payloads/vibe-check/"
         or ($t | test("^\\.?/?payloads/vibe-check/?$")))
    end;
  def normalize_vibe_check_entry:
    if is_vibe_check then
      if (.source | type) != "object" then
        .source = {"path": "../payload-vibe-check"}
      elif vibe_check_path_placeholder(.source.path) then
        .source = (.source + {"path": "../payload-vibe-check"})
      else
        .
      end
    else
      .
    end;
  . as $r |
  ($r[$k]) as $arr |
  if ($arr | any(is_admin)) then
    $r | .[$k] = ($arr | map(if is_admin then normalize_admin_entry else . end | normalize_vibe_check_entry))
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
    }] + $arr | map(normalize_vibe_check_entry))
  end
' "$SERVER_JSON" >"$WORK"

projectRoot="$(jq -r '.server.projectRoot // "."' "$WORK")"
if [[ "$projectRoot" != /* ]]; then
  projectRoot="$(cd "$CONFIG_DIR/$projectRoot" && pwd)"
else
  projectRoot="$(cd "$projectRoot" && pwd)"
fi

cp -f "$WORK" "$OUT"

# One-shot: clear any stale sibling .js/.d.ts/.map debris under the sibling
# project-bridge before the per-payload bundlers resolve its sources. Silent
# when the tree is clean; loud (to stderr, never fails the vendor pass) when
# it finds debris. See mtx_vendor_reap_project_bridge_stale comment.
mtx_vendor_reap_project_bridge_stale "$projectRoot"

# Slugs rsync'd to ./payloads/<slug>/ (path payloads only). mtx deploy removes these after upload;
# cleared here so a fresh vendor pass records only current path payloads.
mkdir -p "$ROOT/.mtx"
rm -f "$ROOT/.mtx/path-vendored-payload-slugs"

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
    mtx_vendor_vprog_begin "$slug"
    # Committed in-repo payloads (e.g. org-project-bridge/payloads/admin) were often copied
    # from a sibling-layout template and still carry `../project-bridge/...` in their configs.
    # From `$ROOT/payloads/<slug>/` that resolves to `$ROOT/payloads/project-bridge/` which
    # doesn't exist, so npm install creates broken file: symlinks, tsconfig extends fails,
    # and (worst of all, because vite doesn't abort on it) Tailwind silently emits a stub
    # ~8 KB CSS with none of the engine/ui classes → invisible text, blank main pane.
    # Rewrite to `$(relpath $ROOT/.. $build_dir)/project-bridge` where `$ROOT/..` is the
    # monorepo root that actually contains `project-bridge/`.
    in_repo_rel="$(mtx_vendor_relpath "$org_parent" "$build_dir" 2>/dev/null || true)"
    if [ -n "$in_repo_rel" ]; then
      mtx_vendor_rewrite_monorepo_paths "$build_dir" "" "$ROOT" "$in_repo_rel" || true
    fi
    if mtx_vendor_run_build_or_banner "$build_dir" "in-repo \"$entry_id\""; then
      mtx_vendor_normalize_payload_dir "$build_dir" || true
      mtx_vendor_vprog_end ok
    else
      vendor_build_failures=$((vendor_build_failures + 1))
      mtx_vendor_vprog_end fail
    fi
    continue
  fi

  dest="$ROOT/payloads/$slug"
  mtx_vendor_vprog_begin "$slug"
  if ! mtx_vendor_run_build_or_banner "$build_dir" "payload \"$entry_id\""; then
    vendor_build_failures=$((vendor_build_failures + 1))
    echo "[vendor-payloads] skipping rsync for \"$entry_id\" (build failed); not updating server.json.railway path for this app" >&2
    mtx_vendor_vprog_end fail
    continue
  fi

  mkdir -p "$(dirname "$dest")"
  # Vended payload tree = runtime surface only. The server reads exactly these
  # paths from a payload dir at Railway runtime (traced through
  # project-bridge/targets/server/src/payload-enrichment.ts + shared/src/server/config.ts):
  #
  #   dist/                              built SPA (index.html + assets/*) and
  #                                      optional api.js / views.js loaded by
  #                                      loadPayloadFromPath
  #   dist/_errors/*.html                payload-level error pages
  #   config/app.json                    payload identity (name/slug/version)
  #                                      read by mergePayloadIdentity
  #   package.json                       loadPayloadModule inspects "type" to
  #                                      decide ESM vs CJS when requiring dist/api
  #
  # Everything else a payload carries — raw .ts[x]/.css, the dev root index.html
  # (references ./src/main.tsx; the exact file that served 496 bytes of white
  # page across every staging org on 2026-04-22, rule-of-law "Admin is always
  # root-mounted"), vite/tsconfig/tailwind/postcss configs, per-payload
  # lockfiles, dev .env, READMEs, tests, editor cruft, flat-layout source dirs
  # (App.tsx, components/, hooks/, pages/, utils/, types/, styles/ … the taxonomy
  # is open-ended) — is not read by anything on Railway (the payload was already
  # built above; Railway runs `npm install --omit=dev --ignore-scripts && node
  # targets/server/dist/index.js`, period).
  #
  # We use an **allowlist** here instead of chasing a blocklist of every new
  # source-layout flavor that walks through the door. Rule: ship what the server
  # reads, strip everything else. If a payload genuinely needs a new runtime-read
  # directory, it goes in the allowlist (and the server side that reads it goes
  # in rule-of-law). `--delete-excluded` is mandatory so a prior vendor run's
  # stale dev files (written before this allowlist existed) get purged on the
  # next vend — without it, rsync treats excludes as "not in view" on both sides
  # and pre-existing debris survives. Defense in depth with
  # template-org/.railwayignore's `payloads/*/` rules covers in-repo payloads
  # the vendor never rsyncs (those dirs are git-tracked; we can't prune them on
  # disk — the upload filter does).
  rsync -a --delete --delete-excluded \
    --include='/dist/***' \
    --include='/config/***' \
    --include='/public/***' \
    --include='/_errors/***' \
    --include='/package.json' \
    --include='/.env.example' \
    --exclude='*' \
    "$resolved/" "$dest/"
  # Rewrite relative monorepo paths (package.json file:, tsconfig extends, vite resolve)
  # so that the vendored tree under $ROOT/payloads/$slug/ resolves to the monorepo again.
  # The source repo lives beside project-bridge/, so it ships with "../project-bridge/..."
  # paths — those escape the org tree after rsync. See mtx_vendor_rewrite_monorepo_paths.
  mtx_vendor_rewrite_monorepo_paths "$dest" "$resolved" "$ROOT" || true
  mtx_vendor_normalize_payload_dir "$dest" || true
  printf '%s\n' "$slug" >> "$ROOT/.mtx/path-vendored-payload-slugs"
  mtx_vendor_vprog_end ok

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
