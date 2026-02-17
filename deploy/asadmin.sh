#!/usr/bin/env bash
# Deploy as master admin: same as "mtx deploy" but sets RUN_AS_MASTER and ensures
# MASTER_JWT_SECRET (and related env) are passed via env, persisted to .env and Terraform, and set on Railway backend.
desc="Deploy as master admin (RUN_AS_MASTER); persists is-master env to .env and Railway backend"
nobanner=1
set -e

# Switch that signals to the server this is the main master (mounts /auth; apply.sh persists to .env and sets on Railway)
export RUN_AS_MASTER=true

# Resolve project root to load .env for MASTER_JWT_SECRET
PROJECT_ROOT=""
if [ -f "config/app.json" ]; then
  PROJECT_ROOT="$(pwd)"
fi
if [ -z "$PROJECT_ROOT" ] && [ -f "../config/app.json" ]; then
  PROJECT_ROOT="$(cd .. && pwd)"
fi
if [ -z "$PROJECT_ROOT" ]; then
  for d in . .. ../project-bridge; do
    [ -f "${d}/config/app.json" ] && PROJECT_ROOT="$(cd "$d" && pwd)" && break
  done
fi
[ -z "$PROJECT_ROOT" ] && PROJECT_ROOT="$(pwd)"
ENV_FILE="$PROJECT_ROOT/.env"
if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck source=/dev/null
  source "$ENV_FILE"
  set +a
fi

# MASTER_JWT_SECRET is required for master backend (auth at /auth). Prompt if missing.
if [ -z "${MASTER_JWT_SECRET:-}" ] || [ "$MASTER_JWT_SECRET" = "null" ]; then
  echo "Deploy as admin (master) requires MASTER_JWT_SECRET for backend /auth."
  if [ -f "$ENV_FILE" ] && grep -q "^MASTER_JWT_SECRET=" "$ENV_FILE" 2>/dev/null; then
    MASTER_JWT_SECRET=$(grep "^MASTER_JWT_SECRET=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'")
  fi
  if [ -z "$MASTER_JWT_SECRET" ]; then
    echo "Enter MASTER_JWT_SECRET (will be saved to .env and set on Railway backend):"
    read -rs MASTER_JWT_SECRET
    echo ""
    [ -z "$MASTER_JWT_SECRET" ] && echo "MASTER_JWT_SECRET is required for asadmin deploy." >&2 && exit 1
    export MASTER_JWT_SECRET
  else
    export MASTER_JWT_SECRET
  fi
fi

# Optional: pass through for CORS / issuer if set
[ -n "${MASTER_AUTH_ISSUER:-}" ] && export MASTER_AUTH_ISSUER
[ -n "${MASTER_CORS_ORIGINS:-}" ] && export MASTER_CORS_ORIGINS

# Same flow as deploy.sh: choose env, run terraform apply, then deploy urls
ENV=""
case "${1:-}" in
  staging|production) ENV="$1" ;;
esac
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
if [ -n "${FORCE_BACKEND:-}" ]; then
  ./terraform/apply.sh --force-backend "$ENV"
else
  ./terraform/apply.sh "$ENV"
fi
if [ -f "./deploy/urls.sh" ]; then
  ./deploy/urls.sh "$ENV"
fi
