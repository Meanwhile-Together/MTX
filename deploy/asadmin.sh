#!/usr/bin/env bash
# Deploy as master admin: same as "mtx deploy" but sets RUN_AS_MASTER and ensures
# MASTER_JWT_SECRET (and related env) are passed via env, persisted to .env and the Railway backend service (admin lane).
desc="Deploy as master admin (RUN_AS_MASTER); persists is-master env to .env and Railway backend service"
nobanner=1
set -e

# Always use MTX scripts (this script lives in MTX/deploy/)
MTX_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../includes/prepare-env.sh
source "$MTX_ROOT/includes/prepare-env.sh"

# Switch that signals to the server this is the main master (mounts /auth; apply.sh persists to .env and sets on Railway)
export RUN_AS_MASTER=true

# Resolve project root to load .env for MASTER_JWT_SECRET (., .., or sibling dirs with config/app.json)
PROJECT_ROOT=""
if [ -f "config/app.json" ]; then
  PROJECT_ROOT="$(pwd)"
fi
if [ -z "$PROJECT_ROOT" ] && [ -f "../config/app.json" ]; then
  PROJECT_ROOT="$(cd .. && pwd)"
fi
if [ -z "$PROJECT_ROOT" ]; then
  for d in . ..; do
    [ -f "${d}/config/app.json" ] && PROJECT_ROOT="$(cd "$d" && pwd)" && break
  done
fi
[ -z "$PROJECT_ROOT" ] && PROJECT_ROOT="$(pwd)"

mtx_require_prepare_env "$PROJECT_ROOT" || exit 1

ENV_FILE="$PROJECT_ROOT/.env"
if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck source=/dev/null
  source "$ENV_FILE"
  set +a
fi

# Every asadmin deploy rotates workspace-root MASTER_JWT_SECRET (apply.sh overlays it after org .env).
mtx_workspace_rotate_master_jwt_secret_for_asadmin || exit 1

if [ -z "${MASTER_JWT_SECRET:-}" ] || [ "$MASTER_JWT_SECRET" = "null" ]; then
  echo "Deploy as admin (master) requires MASTER_JWT_SECRET for backend /auth." >&2
  echo "  Rotation failed; check openssl / permissions on ${MTX_WORKSPACE_ROOT:-<workspace>}/.env.master." >&2
  exit 1
fi

# Optional: pass through for CORS / issuer if set
[ -n "${MASTER_AUTH_ISSUER:-}" ] && export MASTER_AUTH_ISSUER
[ -n "${MASTER_CORS_ORIGINS:-}" ] && export MASTER_CORS_ORIGINS

# Same flow as deploy.sh: choose env, run terraform apply, then deploy urls
unset MTX_VENDOR_REVENDOR 2>/dev/null || true
ENV=""
MTX_VENDOR_REVENDOR=0
for _arg in "$@"; do
  case "$_arg" in
    staging|production) ENV="$_arg" ;;
    --revendor) MTX_VENDOR_REVENDOR=1 ;;
  esac
done
[ "$MTX_VENDOR_REVENDOR" = 1 ] && export MTX_VENDOR_REVENDOR=1
if [ -z "$ENV" ]; then
  echo "Deploy as admin (master) – environment:"
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
# Run MTX's deploy/terraform/apply.sh (never the project's ./terraform/apply.sh)
if [ -n "${FORCE_BACKEND:-}" ]; then
  "$MTX_ROOT/deploy/terraform/apply.sh" --force-backend "${REV_ARGS[@]}" "$ENV"
else
  "$MTX_ROOT/deploy/terraform/apply.sh" "${REV_ARGS[@]}" "$ENV"
fi
if [ -f "$MTX_ROOT/deploy/urls.sh" ]; then
  "$MTX_ROOT/deploy/urls.sh" "$ENV"
fi
