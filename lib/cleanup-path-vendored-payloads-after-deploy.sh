#!/usr/bin/env bash
# MTX: after a successful Railway upload in mtx deploy, remove path-vendored trees under
# <org>/payloads/<slug>/ that vendor-payloads-from-config.sh rsync'd for upload staging.
# In-repo payloads (source already under ./payloads/) are never listed — they stay on disk.
# Drops config/server.json.railway when any listed slug was processed so the next compile
# regenerates it from config/server.json.
#
# Arg: org repo root (default: cwd).
# Env: MTX_SKIP_POSTDEPLOY_PATH_PAYLOAD_CLEANUP=1 — no-op.
# Note: apply.sh does not invoke this when MTX_SKIP_BUILD=1 (upload may rely on payloads/ from a prior compile).
set -euo pipefail

ROOT="$(cd "${1:-.}" && pwd)"
if [ "${MTX_SKIP_POSTDEPLOY_PATH_PAYLOAD_CLEANUP:-}" = "1" ]; then
  exit 0
fi

MANIFEST="$ROOT/.mtx/path-vendored-payload-slugs"
[ -f "$MANIFEST" ] || exit 0

mtx_cleanup_path_payload_slug_ok() {
  local s="${1:-}"
  [ -n "$s" ] || return 1
  case "$s" in
    *..*|*/*|'') return 1 ;;
  esac
  [[ "$s" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]] || return 1
  return 0
}

saw_valid_slug=false
while IFS= read -r slug || [ -n "${slug:-}" ]; do
  slug="${slug#"${slug%%[![:space:]]*}"}"
  slug="${slug%"${slug##*[![:space:]]}"}"
  [ -n "$slug" ] || continue
  mtx_cleanup_path_payload_slug_ok "$slug" || continue
  saw_valid_slug=true
  target="$ROOT/payloads/$slug"
  if [ -e "$target" ]; then
    rm -rf "$target"
    echo "[mtx] Removed path-vendored payload staging dir: payloads/$slug" >&2
  fi
done < "$MANIFEST"

rm -f "$MANIFEST"

if [ "$saw_valid_slug" = true ] && [ -f "$ROOT/config/server.json.railway" ]; then
  rm -f "$ROOT/config/server.json.railway"
  echo "[mtx] Removed config/server.json.railway (regenerated on next mtx build / deploy compile step)." >&2
fi

exit 0
