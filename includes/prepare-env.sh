#!/usr/bin/env bash

# Resolve workspace root by walking up until a *.code-workspace file is found.
mtx_detect_workspace_root() {
  local walk="${1:-$(pwd)}"
  while [ -n "$walk" ] && [ "$walk" != "/" ]; do
    for f in "$walk"/*.code-workspace; do
      if [ -f "$f" ]; then
        printf '%s' "$walk"
        return 0
      fi
    done
    walk="$(dirname "$walk")"
  done
  return 1
}

mtx_prepare_file_path() {
  local root="$1"
  printf '%s/.mtx.prepare.env' "$root"
}

# Upsert KEY=value in $MTX_PREPARE_FILE (workspace .mtx.prepare.env). File must exist (run mtx prepare).
# Used by deploy/urls.sh after asadmin when persisting discovered master origin; mirrors apply.sh set_prepare_key.
mtx_prepare_env_set_key() {
  local key="$1" value="$2" line pf
  line="${key}=${value}"
  pf="${MTX_PREPARE_FILE:-}"
  if [ -z "$pf" ] || [ ! -f "$pf" ]; then
    echo "❌ mtx_prepare_env_set_key: MTX_PREPARE_FILE missing or not found (run: mtx prepare)." >&2
    return 1
  fi
  if grep -q "^${key}=" "$pf" 2>/dev/null; then
    grep -v "^${key}=" "$pf" > "${pf}.tmp" && mv "${pf}.tmp" "$pf"
  fi
  echo "$line" >> "$pf"
  chmod 600 "$pf" 2>/dev/null || true
  return 0
}

mtx_trim_inline() {
  local v="${1:-}"
  v="${v//$'\r'/}"
  v="${v//$'\n'/}"
  v="${v#"${v%%[![:space:]]*}"}"
  v="${v%"${v##*[![:space:]]}"}"
  case "$v" in
    '"'*) v="${v#\"}"; v="${v%\"}" ;;
    "'"*) v="${v#\'}"; v="${v%\'}" ;;
  esac
  printf '%s' "$v"
}

# Read workspace-root master JWT for non-asadmin deploys (never creates or rotates here).
# Reads $MTX_WORKSPACE_ROOT/.env.master first, then MASTER_JWT_SECRET= from $MTX_WORKSPACE_ROOT/.env.
# Call after org .env so workspace values override per-org drift.
mtx_workspace_overlay_master_jwt_secret() {
  local root="${MTX_WORKSPACE_ROOT:-}"
  [ -n "$root" ] || return 0
  local val="" mf uw
  mf="$root/.env.master"
  uw="$root/.env"
  if [ -f "$mf" ] && grep -qE '^[[:space:]]*MASTER_JWT_SECRET=' "$mf" 2>/dev/null; then
    val="$(grep -E '^[[:space:]]*MASTER_JWT_SECRET=' "$mf" | head -1 | sed 's/^[^=]*=//')"
    val="$(mtx_trim_inline "$val")"
  fi
  if [ -z "$val" ] && [ -f "$uw" ] && grep -qE '^[[:space:]]*MASTER_JWT_SECRET=' "$uw" 2>/dev/null; then
    val="$(grep -E '^[[:space:]]*MASTER_JWT_SECRET=' "$uw" | head -1 | sed 's/^[^=]*=//')"
    val="$(mtx_trim_inline "$val")"
  fi
  if [ -n "$val" ] && [ "$val" != "null" ]; then
    export MASTER_JWT_SECRET="$val"
  fi
  return 0
}

# mtx deploy master lane (org-project-bridge): always write a new MASTER_JWT_SECRET to .env.master (rotate every run).
# Plain tenant deploy never calls this — missing secret stays missing until the next deploy from org-project-bridge.
mtx_workspace_rotate_master_jwt_secret_for_asadmin() {
  case "${MTX_MASTER_LANE:-}" in 1|true|yes) ;;
  *) return 0 ;;
  esac
  local root="${MTX_WORKSPACE_ROOT:-}"
  [ -n "$root" ] || return 1
  local gen mf tmp
  mf="$root/.env.master"
  if command -v openssl >/dev/null 2>&1; then
    gen="$(openssl rand -base64 48 | tr -d '\n\r')"
  else
    gen="$(tr -dc 'A-Za-z0-9' </dev/urandom 2>/dev/null | head -c 64)"
  fi
  [ -n "$gen" ] || {
    echo "❌ Could not generate MASTER_JWT_SECRET (install openssl or ensure /dev/urandom is readable)." >&2
    return 1
  }
  umask 077
  tmp="$(mktemp "${TMPDIR:-/tmp}/mtx-master-jwt.XXXXXX")"
  if [ -f "$mf" ]; then
    # grep exits 1 on "no lines" for some inputs; never fail the deploy under set -e
    grep -vE '^[[:space:]]*MASTER_JWT_SECRET=' "$mf" >"$tmp" 2>/dev/null || true
  else
    : >"$tmp"
  fi
  printf 'MASTER_JWT_SECRET=%s\n' "$gen" >>"$tmp"
  mv "$tmp" "$mf"
  chmod 600 "$mf" 2>/dev/null || true
  export MASTER_JWT_SECRET="$gen"
  echo "[INFO] Rotated MASTER_JWT_SECRET for org-project-bridge master lane; wrote $mf (workspace root). Tenant deploys only read this file and never auto-generate a missing secret." >&2
  return 0
}

# shellcheck source=mtx-bridge-deploy.sh
_bridge_deploy_inc="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/mtx-bridge-deploy.sh"
[ -f "$_bridge_deploy_inc" ] && # shellcheck disable=SC1090
source "$_bridge_deploy_inc"
unset _bridge_deploy_inc

# Load and validate workspace-level prepare file.
# Exports MTX_WORKSPACE_ROOT and MTX_PREPARE_FILE.
mtx_require_prepare_env() {
  local start_dir="${1:-$(pwd)}"
  local workspace_root prepare_file
  local required_vars=(
    RAILWAY_ACCOUNT_TOKEN
    RAILWAY_WORKSPACE_ID
    RAILWAY_PROJECT_ID
    RAILWAY_PROJECT_TOKEN_STAGING
    RAILWAY_PROJECT_TOKEN_PRODUCTION
  )

  workspace_root="$(mtx_detect_workspace_root "$start_dir")" || {
    echo "❌ Workspace root not found (missing *.code-workspace in parent chain)." >&2
    echo "   Run this command from inside your MT workspace." >&2
    return 1
  }
  prepare_file="$(mtx_prepare_file_path "$workspace_root")"

  if [ ! -f "$prepare_file" ]; then
    echo "❌ Required prepare file missing: $prepare_file" >&2
    echo "   Run: mtx prepare" >&2
    return 1
  fi

  set -a
  # shellcheck source=/dev/null
  source "$prepare_file"
  set +a

  local key val
  for key in "${required_vars[@]}"; do
    val="$(mtx_trim_inline "${!key:-}")"
    if [ -z "$val" ]; then
      echo "❌ Required key missing in $prepare_file: $key" >&2
      echo "   Run: mtx prepare" >&2
      return 1
    fi
    printf -v "$key" '%s' "$val"
    export "$key"
  done

  export MTX_WORKSPACE_ROOT="$workspace_root"
  export MTX_PREPARE_FILE="$prepare_file"
}

# Source workspace .mtx.prepare.env if it exists; set MTX_WORKSPACE_ROOT and MTX_PREPARE_FILE.
# Does not require any keys (for mtx master * commands that only need platform singletons).
# Usage: mtx_source_prepare_file_from_cwd [start_dir] || exit
mtx_source_prepare_file_from_cwd() {
  local start_dir="${1:-$(pwd)}" wr pf
  wr="$(mtx_detect_workspace_root "$start_dir")" || {
    echo "❌ Workspace root not found (missing *.code-workspace in parent chain)." >&2
    return 1
  }
  pf="$(mtx_prepare_file_path "$wr")"
  export MTX_WORKSPACE_ROOT="$wr"
  export MTX_PREPARE_FILE="$pf"
  if [ -f "$pf" ]; then
    set -a
    # shellcheck source=/dev/null
    source "$pf"
    set +a
  fi
  return 0
}
