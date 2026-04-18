#!/usr/bin/env bash
# Portable (Linux / macOS / WSL): post-assembly pre-deploy for org Railway bundles.
# Invoked by MTX build.sh after `npm run prepare:railway` (payload vendor + per-payload builds).
#
# 1) Optional org hook: scripts/org-pre-deploy.sh <project_root> (silent no-op if missing)
# 2) Payload normalizer: fix root-absolute asset URLs in HTML so apps work under path prefixes.
#
# No Node required. In-place edits use mktemp + mv (no sed -i differences).

mtx_predeploy__write_sed() {
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
  mtx_predeploy__write_sed "$tmp" \
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
    echo "==> mtx-predeploy: updated $(basename "$(dirname "$f")")/$(basename "$f")"
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
  mtx_predeploy__write_sed "$tmp" \
    -e "s|base[[:space:]]*:[[:space:]]*['\"]/['\"]|base: './'|g" \
    "$f" || return 1
  if ! cmp -s "$f" "$tmp" 2>/dev/null; then
    mv -f "$tmp" "$f"
    echo "==> mtx-predeploy: updated $(basename "$f")"
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

# Public entry: project root (org repo) after payloads are assembled under payloads/*.
mtx_predeploy_after_payload_assembly() {
  local root="$1"
  [ -n "$root" ] || return 0
  root="$(cd "$root" && pwd)"

  local hook="$root/scripts/org-pre-deploy.sh"
  if [ -f "$hook" ]; then
    echo "==> mtx-predeploy: org hook"
    bash "$hook" "$root" || return 1
  fi

  local pd="$root/payloads"
  if [ -d "$pd" ]; then
    local entry
    for entry in "$pd"/*/; do
      [ -d "$entry" ] || continue
      mtx_predeploy_normalize_payload_dir "$entry" || return 1
    done
  fi

  # Org shell client mirror (if present); safe no-op when missing.
  mtx_predeploy_normalize_html_file "$root/targets/client/dist/index.html"

  echo "==> mtx-predeploy: done"
  return 0
}
