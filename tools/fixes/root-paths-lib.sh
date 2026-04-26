#!/usr/bin/env bash
# MTX library: normalize root-absolute HTML asset URLs and Vite base for payloads under path prefixes.
# Sourced by includes/mtx-predeploy.sh, tools/fixes/root-paths.sh (CLI), and transitively vendor-payloads.
# Portable (Linux / macOS / WSL): mktemp + mv — no Node.
#
# Public functions (stable names for callers):
#   mtx_predeploy_normalize_html_file
#   mtx_predeploy_normalize_vite_config
#   mtx_predeploy_normalize_payload_dir
#   mtx_predeploy_normalize_source_paths_from_server_json

mtx_root_paths__write_sed() {
  local dest="$1"
  shift
  # shellcheck disable=SC2068
  sed "$@" >"$dest"
}

# Normalize one HTML file (built dist or dev index): /assets/ and common root-absolute entry refs.
mtx_predeploy_normalize_html_file() {
  local f="$1"
  [ -f "$f" ] || return 0
  local tmp
  tmp="$(mktemp)"
  mtx_root_paths__write_sed "$tmp" \
    -e 's|href"\./|href="./|g' \
    -e 's|src"\./|src="./|g' \
    -e 's|="/assets/|"./assets/|g' \
    -e "s|='/assets/|'./assets/|g" \
    -e 's|="/vite.svg|"./vite.svg|g' \
    -e "s|='/vite.svg|'./vite.svg|g" \
    -e 's|src="/|src="./|g' \
    -e "s|src='/|src='./|g" \
    -e 's|href="/|href="./|g' \
    -e "s|href='/|href='./|g" \
    "$f" || return 1
  if ! cmp -s "$f" "$tmp" 2>/dev/null; then
    mv -f "$tmp" "$f"
    echo "==> mtx root-paths: updated $(basename "$(dirname "$f")")/$(basename "$f")"
  else
    rm -f "$tmp"
  fi
  return 0
}

# Coerce explicit Vite root base to relative when present (helps next local build).
mtx_predeploy_normalize_vite_config() {
  local f="$1"
  [ -f "$f" ] || return 0
  local tmp
  tmp="$(mktemp)"
  mtx_root_paths__write_sed "$tmp" \
    -e "s|base[[:space:]]*:[[:space:]]*['\"]/['\"]|base: './'|g" \
    "$f" || return 1
  if ! cmp -s "$f" "$tmp" 2>/dev/null; then
    mv -f "$tmp" "$f"
    echo "==> mtx root-paths: updated $(basename "$f")"
  else
    rm -f "$tmp"
  fi
  return 0
}

mtx_predeploy_normalize_payload_dir() {
  local d="$1"
  [ -d "$d" ] || return 0
  mtx_predeploy_normalize_html_file "$d/index.html"
  mtx_predeploy_normalize_html_file "$d/dist/index.html"
  mtx_predeploy_normalize_html_file "$d/targets/client/dist/index.html"
  for vc in "$d/vite.config.ts" "$d/vite.config.mts" "$d/vite.config.js" "$d/vite.config.mjs"; do
    [ -f "$vc" ] || continue
    mtx_predeploy_normalize_vite_config "$vc"
  done
  return 0
}

# Normalize every path payload listed in config/server.json (sibling ../payload-* repos, etc.).
# Used by org dev (before unified server) and safe to call when sources already live under payloads/.
# Requires jq. Idempotent with mtx_predeploy_normalize_payload_dir.
mtx_predeploy_normalize_source_paths_from_server_json() {
  local org_root="$1"
  [ -n "$org_root" ] || return 0
  org_root="$(cd "$org_root" && pwd)"
  local sj="$org_root/config/server.json"
  [ -f "$sj" ] || return 0
  if ! command -v jq >/dev/null 2>&1; then
    echo "mtx root-paths: jq not found; skip normalize_source_paths_from_server_json" >&2
    return 0
  fi

  local APP_KEY=""
  if jq -e '.apps | type == "array"' "$sj" >/dev/null 2>&1; then
    APP_KEY=apps
  elif jq -e '.payloads | type == "array"' "$sj" >/dev/null 2>&1; then
    APP_KEY=payloads
  else
    return 0
  fi

  local config_dir projectRoot
  config_dir="$(cd "$org_root/config" && pwd)"
  projectRoot="$(jq -r '.server.projectRoot // "."' "$sj")"
  if [[ "$projectRoot" != /* ]]; then
    projectRoot="$(cd "$config_dir/$projectRoot" && pwd)"
  else
    projectRoot="$(cd "$projectRoot" && pwd)"
  fi

  local n i src_path rel entry_id resolved
  n="$(jq --arg k "$APP_KEY" '.[$k] | length' "$sj")"
  for ((i = 0; i < n; i++)); do
    src_path="$(jq -r --argjson i "$i" --arg k "$APP_KEY" '.[$k][$i].source.path // empty' "$sj")"
    [ -n "$src_path" ] || continue
    rel="${src_path#"${src_path%%[![:space:]]*}"}"
    rel="${rel%"${rel##*[![:space:]]}"}"
    case "$rel" in '' | '.' | './') continue ;; esac
    entry_id="$(jq -r --argjson i "$i" --arg k "$APP_KEY" '.[$k][$i].id // empty' "$sj")"
    if ! resolved="$(cd "$projectRoot" && test -e "$rel" && cd "$rel" && pwd)"; then
      echo "mtx root-paths: skip normalize \"$entry_id\": not under projectRoot ($projectRoot): $rel" >&2
      continue
    fi
    if [ ! -f "$resolved/package.json" ]; then
      continue
    fi
    mtx_predeploy_normalize_payload_dir "$resolved" || return 1
  done
  return 0
}
