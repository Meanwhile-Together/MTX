#!/usr/bin/env bash
# Deploy as master admin: same as "mtx deploy" but sets RUN_AS_MASTER and ensures
# MASTER_JWT_SECRET (and related env) are passed via env, persisted to .env and the Railway backend service (admin lane).
desc="Deploy as master admin (RUN_AS_MASTER); persists is-master env to .env and Railway backend service"
nobanner=1
set -e

# Always use MTX scripts (this script lives in MTX/deploy/). Use BASH_SOURCE so mtx wrapper
# sourcing works ($0 is often /usr/bin/mtx, which would wrongly resolve MTX_ROOT to /usr).
MTX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
# shellcheck source=../includes/prepare-env.sh
source "$MTX_ROOT/includes/prepare-env.sh"

# Resolve project root first (., .., or sibling dirs with config/app.json or config/org.json)
PROJECT_ROOT=""
if [ -f "config/app.json" ] || [ -f "config/org.json" ]; then
  PROJECT_ROOT="$(pwd)"
fi
if [ -z "$PROJECT_ROOT" ] && { [ -f "../config/app.json" ] || [ -f "../config/org.json" ]; }; then
  PROJECT_ROOT="$(cd .. && pwd)"
fi
if [ -z "$PROJECT_ROOT" ]; then
  for d in . ..; do
    { [ -f "${d}/config/app.json" ] || [ -f "${d}/config/org.json" ]; } && PROJECT_ROOT="$(cd "$d" && pwd)" && break
  done
fi
[ -z "$PROJECT_ROOT" ] && PROJECT_ROOT="$(pwd)"

# GUARDRAIL: asadmin is only valid against a project/org that declares itself as the master.
# Without this, a stray `mtx deploy asadmin` from any tenant org silently plants
# RUN_AS_MASTER=true into that org's .env (apply.sh:122-125), which then re-propagates on
# every subsequent `mtx deploy` (apply.sh:1290+) — producing a two-master split-brain on Railway.
# See project-bridge/docs/rule-of-law.md ("Master promotion is declarative, not incidental").
#
# Escape hatch for first-time master-promote (e.g. a brand-new workspace where no org has been
# promoted yet): MTX_ASADMIN_FORCE=1 mtx deploy asadmin.
mtx_org_declares_master() {
  local root="$1" f
  for f in "$root/config/org.json" "$root/config/app.json"; do
    [ -f "$f" ] || continue
    # jq-free: grep inside a single-line match for "master": true in the "org" block or top level.
    if grep -qE '"master"[[:space:]]*:[[:space:]]*true' "$f"; then
      return 0
    fi
  done
  return 1
}
if [ "${MTX_ASADMIN_FORCE:-}" != "1" ] && ! mtx_org_declares_master "$PROJECT_ROOT"; then
  echo "❌ Refusing to run 'mtx deploy asadmin' from $PROJECT_ROOT" >&2
  echo "   This project does not declare itself as master (expected \"master\": true inside the org block of config/org.json)." >&2
  echo "   Running asadmin from a tenant org plants RUN_AS_MASTER=true into its .env and will re-propagate on every subsequent 'mtx deploy'," >&2
  echo "   creating a two-master split-brain on Railway." >&2
  echo "" >&2
  echo "   If you genuinely mean to promote this project to master, either:" >&2
  echo "     1. Add  \"master\": true  inside the \"org\" block of $PROJECT_ROOT/config/org.json, OR" >&2
  echo "     2. Re-run with MTX_ASADMIN_FORCE=1 (also adds the declaration)." >&2
  exit 1
fi

# Explicit intent sentinel. apply.sh uses this (not the presence of RUN_AS_MASTER in env) to gate
# master-env persistence to .env and propagation to the Railway service. Prevents a polluted .env
# from an earlier wrong-directory asadmin run from re-asserting master-ness on future deploys.
export MTX_ASADMIN=1

# Switch that signals to the server this is the main master (mounts /auth; apply.sh persists to .env and sets on Railway)
export RUN_AS_MASTER=true

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
