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
