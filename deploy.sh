#!/usr/bin/env bash
# MTX deploy: run from org host (or transitional) project root — menu (staging|production) then deploy/terraform/apply.sh
desc="Interactive deploy menu (choose staging or production), then deploy/terraform apply; optional --revendor"
nobanner=1
set -e

# Always use MTX scripts (this script lives in MTX root).
# Use BASH_SOURCE so this resolves correctly even when sourced by the mtx wrapper
# (where $0 is typically /usr/bin/mtx).
MTX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=includes/prepare-env.sh
source "$MTX_ROOT/includes/prepare-env.sh"

# All token/id-aware deploy flows require workspace prepare context.
mtx_require_prepare_env "$(pwd)" || exit 1

# Intelligent master lane: only org-project-bridge (see includes/mtx-bridge-deploy.sh) rotates master JWT
# and exports MTX_MASTER_LANE=1 for apply.sh / Railway — no mtx deploy asadmin / RUN_AS_MASTER / MTX_ASADMIN.
PROJECT_ROOT="$(mtx_deploy_resolve_project_root)"
export PROJECT_ROOT
unset MTX_ASADMIN 2>/dev/null || true
unset RUN_AS_MASTER 2>/dev/null || true
if mtx_deploy_is_org_project_bridge "$PROJECT_ROOT"; then
  export MTX_MASTER_LANE=1
  ENV_FILE="$PROJECT_ROOT/.env"
  if [ -f "$ENV_FILE" ]; then
    set -a
    # shellcheck source=/dev/null
    source "$ENV_FILE"
    set +a
  fi
  mtx_workspace_rotate_master_jwt_secret_for_asadmin || exit 1
  if [ -z "${MASTER_JWT_SECRET:-}" ] || [ "$MASTER_JWT_SECRET" = "null" ]; then
    echo "❌ org-project-bridge deploy requires MASTER_JWT_SECRET after rotation (check workspace .env.master)." >&2
    exit 1
  fi
  [ -n "${MASTER_AUTH_ISSUER:-}" ] && export MASTER_AUTH_ISSUER
  [ -n "${MASTER_CORS_ORIGINS:-}" ] && export MASTER_CORS_ORIGINS
else
  unset MTX_MASTER_LANE 2>/dev/null || true
fi

# Accept staging|production and optional flags in any order
unset MTX_VENDOR_REVENDOR 2>/dev/null || true
ENV=""
MTX_VENDOR_REVENDOR=0
for _arg in "$@"; do
  case "$_arg" in
    staging|production) ENV="$_arg" ;;
    --revendor) MTX_VENDOR_REVENDOR=1 ;;
    --no-provision-tenant) export MTX_SKIP_AUTO_TENANT_PROVISION=1 ;;
    --rotate-tenant-secret) export MTX_ROTATE_TENANT_SECRET=1 ;;
  esac
done
[ "$MTX_VENDOR_REVENDOR" = 1 ] && export MTX_VENDOR_REVENDOR=1
if [ -z "$ENV" ]; then
  echo "Deploy environment:"
  echo "  1) staging"
  echo "  2) production"
  read -rp "Choice (1 or 2) [1]: " choice
  choice="${choice:-1}"
  case "$choice" in
    1|s|staging)   ENV=staging ;;
    2|p|production) ENV=production ;;
    *) echo "Invalid choice. Use 1 or 2." >&2; exit 1 ;;
  esac
fi

[ -n "${FORCE_BACKEND:-}" ] && export FORCE_BACKEND
REV_ARGS=()
[ "${MTX_VENDOR_REVENDOR:-}" = 1 ] && REV_ARGS+=(--revendor)
[ "${MTX_SKIP_AUTO_TENANT_PROVISION:-}" = 1 ] && REV_ARGS+=(--no-provision-tenant)
[ "${MTX_ROTATE_TENANT_SECRET:-}" = 1 ] && REV_ARGS+=(--rotate-tenant-secret)
# Run MTX's deploy/terraform/apply.sh (never the project's ./terraform/apply.sh)
if [ -n "${FORCE_BACKEND:-}" ]; then
  "$MTX_ROOT/deploy/terraform/apply.sh" --force-backend "${REV_ARGS[@]}" "$ENV"
else
  "$MTX_ROOT/deploy/terraform/apply.sh" "${REV_ARGS[@]}" "$ENV"
fi
# After successful deploy, ensure deploy URLs and print them (same as mtx deploy urls)
if [ -f "$MTX_ROOT/deploy/urls.sh" ]; then
  MTX_NONINTERACTIVE=1 "$MTX_ROOT/deploy/urls.sh" "$ENV"
fi
