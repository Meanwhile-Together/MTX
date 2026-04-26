#!/usr/bin/env bash
# Portable (Linux / macOS / WSL): post-assembly pre-deploy for org Railway bundles.
# Invoked by MTX build.sh after `npm run prepare:railway` (payload vendor + per-payload builds).
#
# 1) Optional org hook: scripts/org-pre-deploy.sh <project_root> (silent no-op if missing)
# 2) Payload root-path normalization — see tools/fixes/root-paths-lib.sh (HTML + Vite base; no Node).

_mtx_predeploy_mtx_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
_mtx_predeploy_lib="$_mtx_predeploy_mtx_root/tools/fixes/root-paths-lib.sh"
if [ ! -f "$_mtx_predeploy_lib" ]; then
  _mtx_predeploy_lib="$_mtx_predeploy_mtx_root/fixes/root-paths-lib.sh"
fi
if [ ! -f "$_mtx_predeploy_lib" ]; then
  echo "❌ mtx-predeploy: root-paths-lib.sh not found (expected ${_mtx_predeploy_mtx_root}/tools/fixes/root-paths-lib.sh)" >&2
  unset _mtx_predeploy_mtx_root _mtx_predeploy_lib
  return 1 2>/dev/null || exit 1
fi
# shellcheck source=../tools/fixes/root-paths-lib.sh
# shellcheck disable=SC1090
source "$_mtx_predeploy_lib"
unset _mtx_predeploy_mtx_root _mtx_predeploy_lib

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
