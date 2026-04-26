#!/usr/bin/env bash
desc='Normalize HTML/Vite root-absolute paths for path-prefixed payload mounts (idempotent).'
# MTX command: mtx tools fixes root-paths [--workspace DIR] [DIR...]
# Default --workspace is the parent of the MTX repo (sibling org-*/payload-* layout).
# (Sourced by mtx.sh — avoid global set -u/set -o pipefail here.)

MTX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=root-paths-lib.sh
source "$MTX_ROOT/tools/fixes/root-paths-lib.sh"

mtx_fixes_root_paths_usage() {
  echo "Usage: mtx tools fixes root-paths [--workspace DIR] [DIR...]" >&2
  echo "  --workspace DIR   Scan DIR for org-*/ (config/server.json + payloads/*) and payload-* repos." >&2
  echo "                    Default: parent of MTX ($MTX_ROOT/..)." >&2
  echo "  DIR...            Additional org roots, payload repo roots, or payload directories to normalize." >&2
}

mtx_fixes_root_paths_one() {
  local p="${1%/}"
  [ -n "$p" ] || return 0
  if [ ! -e "$p" ]; then
    echo "mtx tools fixes root-paths: skip (missing): $p" >&2
    return 0
  fi
  p="$(cd "$p" && pwd)"
  if [ -f "$p/config/server.json" ]; then
    echo "==> mtx tools fixes root-paths: org $p (server.json paths + payloads/)"
    mtx_predeploy_normalize_source_paths_from_server_json "$p" || return 1
    if [ -d "$p/payloads" ]; then
      local sub
      for sub in "$p/payloads"/*/; do
        [ -d "$sub" ] || continue
        echo "==> mtx tools fixes root-paths: payloads/$(basename "$sub") under $p"
        mtx_predeploy_normalize_payload_dir "$sub" || return 1
      done
    fi
    return 0
  fi
  if [ -f "$p/package.json" ]; then
    echo "==> mtx tools fixes root-paths: app dir $p"
    mtx_predeploy_normalize_payload_dir "$p" || return 1
  fi
}

mtx_fixes_root_paths_scan_workspace() {
  local ws="$1"
  ws="$(cd "$ws" && pwd)"
  echo "==> mtx tools fixes root-paths: scanning workspace $ws"
  local cand
  for cand in "$ws"/org-*/; do
    [ -d "$cand" ] || continue
    mtx_fixes_root_paths_one "$cand" || return 1
  done
  for cand in "$ws"/payload-*/; do
    [ -d "$cand" ] || continue
    mtx_fixes_root_paths_one "$cand" || return 1
  done
}

mtx_fixes_root_paths_main() {
  local workspace="" paths=()
  while [ $# -gt 0 ]; do
    case "$1" in
      -h | --help)
        mtx_fixes_root_paths_usage
        return 0
        ;;
      --workspace)
        workspace="${2:-}"
        [ -n "$workspace" ] || { echo "mtx tools fixes root-paths: --workspace needs a directory" >&2; return 1; }
        shift 2
        ;;
      *)
        paths+=("$1")
        shift
        ;;
    esac
  done

  if [ -z "$workspace" ] && [ ${#paths[@]} -eq 0 ]; then
    workspace="$(cd "$MTX_ROOT/.." && pwd)"
  fi

  if [ -n "$workspace" ]; then
    mtx_fixes_root_paths_scan_workspace "$workspace" || return 1
  fi

  local p
  for p in "${paths[@]}"; do
    mtx_fixes_root_paths_one "$p" || return 1
  done

  echo "==> mtx tools fixes root-paths: done"
}

mtx_fixes_root_paths_main "$@"
