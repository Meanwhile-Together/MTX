#!/usr/bin/env bash
# Sourced by deploy/terraform/apply.sh: auto tenant_registry provision (rule-of-law) before Railway TENANT_SECRET sync.
# Expects caller scope: PROJECT_ROOT, MTX_ROOT, ORG_IDENTITY_FILE, ORG_IDENTITY_KEY, APP_SLUG, ENVIRONMENT,
# PROJECT_ID, SERVICE_ID, PROJECT_TOKEN, MTX_ORG_DECLARES_MASTER, ENV_FILE, NC, YELLOW, GREEN, CYAN (optional).

mtx_deploy_parse_tenant_base_url_from_domain_out() {
  local out="$1"
  local url
  url=$(echo "$out" | grep -Eo '[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.up\.railway\.app' | head -n 1)
  [ -z "$url" ] && url=$(echo "$out" | jq -r '.domain // .url // .host // empty' 2>/dev/null)
  [ -z "$url" ] && return 1
  url=$(echo "$url" | tr -d '\n\r' | sed 's|^https\?://||' | sed 's|/.*||')
  [ -z "$url" ] || [ "$url" = "null" ] && return 1
  printf 'https://%s' "$url"
  return 0
}

# Persist TENANT_SECRET= to org .env (append if no line; replace if rotate).
mtx_deploy_persist_tenant_secret_to_dotenv() {
  local env_file="$1"
  local secret_val="$2"
  local rotate="${3:-0}"
  [ -n "$env_file" ] || return 1
  umask 077
  if [ "$rotate" = "1" ] && [ -f "$env_file" ]; then
    if grep -qE '^[[:space:]]*TENANT_SECRET=' "$env_file" 2>/dev/null; then
      if [[ "$OSTYPE" == darwin* ]]; then
        sed -i '' '/^[[:space:]]*TENANT_SECRET=/d' "$env_file"
      else
        sed -i '/^[[:space:]]*TENANT_SECRET=/d' "$env_file"
      fi
    fi
  fi
  if [ -f "$env_file" ]; then
    if ! grep -qE '^[[:space:]]*TENANT_SECRET=' "$env_file" 2>/dev/null; then
      echo "TENANT_SECRET=${secret_val}" >>"$env_file"
      chmod 600 "$env_file" 2>/dev/null || true
      return 0
    fi
  else
    echo "TENANT_SECRET=${secret_val}" >>"$env_file"
    chmod 600 "$env_file" 2>/dev/null || true
    return 0
  fi
  return 0
}

# Uses: MTX_SKIP_AUTO_TENANT_PROVISION, MTX_ROTATE_TENANT_SECRET, MASTER_DATABASE_URL, DATABASE_URL.
mtx_deploy_auto_provision_tenant_if_needed() {
  if [ "${MTX_SKIP_AUTO_TENANT_PROVISION:-}" = "1" ]; then
    [ "${MTX_VERBOSE:-1}" -ge 2 ] 2>/dev/null && echo "[mtx-tenant-provision] Skipped (MTX_SKIP_AUTO_TENANT_PROVISION=1)." >&2 || true
    return 0
  fi
  if [ "${MTX_ORG_DECLARES_MASTER:-false}" = "true" ]; then
    [ "${MTX_VERBOSE:-1}" -ge 2 ] 2>/dev/null && echo "[mtx-tenant-provision] Skipped (declarative master org)." >&2 || true
    return 0
  fi
  if declare -F mtx_deploy_is_org_project_bridge >/dev/null 2>&1 && [ -n "${PROJECT_ROOT:-}" ] && mtx_deploy_is_org_project_bridge "$PROJECT_ROOT"; then
    [ "${MTX_VERBOSE:-1}" -ge 2 ] 2>/dev/null && echo "[mtx-tenant-provision] Skipped (org-project-bridge host)." >&2 || true
    return 0
  fi

  local app_db=""
  if [ -n "${MASTER_DATABASE_URL:-}" ]; then
    app_db="$MASTER_DATABASE_URL"
  elif [ -n "${DATABASE_URL:-}" ]; then
    app_db="$DATABASE_URL"
  fi
  if [ -z "$app_db" ]; then
    echo -e "${YELLOW:-}⚠️  Auto tenant provision skipped: set MASTER_DATABASE_URL (or DATABASE_URL to the master app DB) in workspace .mtx.prepare.env for registry upsert.${NC:-}" >&2
    return 0
  fi

  local rotate=0
  [ "${MTX_ROTATE_TENANT_SECRET:-}" = "1" ] && rotate=1
  if [ -n "${TENANT_SECRET:-}" ] && [ "$rotate" != "1" ]; then
    [ "${MTX_VERBOSE:-1}" -ge 2 ] 2>/dev/null && echo "[mtx-tenant-provision] Skipped (TENANT_SECRET already set; use MTX_ROTATE_TENANT_SECRET=1 or --rotate-tenant-secret to rotate)." >&2 || true
    return 0
  fi
  if [ -n "${TENANT_SECRET:-}" ] && [ "$rotate" = "1" ]; then
    echo -e "${YELLOW:-}⚠️  Rotating TENANT_SECRET — federation/heartbeat will change; all envs must pick up the new secret.${NC:-}" >&2
  fi

  local org_slug=""
  if [ -n "${ORG_IDENTITY_FILE:-}" ] && [ -f "$ORG_IDENTITY_FILE" ] && [ -n "${ORG_IDENTITY_KEY:-}" ]; then
    org_slug=$(jq -r ".${ORG_IDENTITY_KEY}.slug // empty" "$ORG_IDENTITY_FILE" 2>/dev/null || echo "")
  fi
  if [ -z "$org_slug" ]; then
    org_slug="${APP_SLUG:-}"
  fi
  if [ -z "$org_slug" ]; then
    echo -e "${YELLOW:-}⚠️  Auto tenant provision skipped: could not resolve org slug from config.${NC:-}" >&2
    return 0
  fi

  if ! command -v psql >/dev/null 2>&1 || ! command -v openssl >/dev/null 2>&1; then
    echo -e "${YELLOW:-}⚠️  Auto tenant provision skipped: need psql and openssl on PATH.${NC:-}" >&2
    return 0
  fi

  if [ -z "${PROJECT_ID:-}" ] || [ "$PROJECT_ID" = "null" ] || [ -z "${SERVICE_ID:-}" ] || [ "$SERVICE_ID" = "null" ]; then
    echo -e "${YELLOW:-}⚠️  Auto tenant provision skipped: missing Railway project/service id.${NC:-}" >&2
    return 0
  fi

  local domain_out base_url
  export RAILWAY_TOKEN="${PROJECT_TOKEN:-${RAILWAY_TOKEN:-}}"
  unset RAILWAY_API_TOKEN
  domain_out=""
  if type ensure_railway_domain &>/dev/null; then
    domain_out=$(ensure_railway_domain "${PROJECT_ROOT}" "${PROJECT_ID}" "${SERVICE_ID}" "${ENVIRONMENT}" "app" || true)
  fi
  if [ -z "$domain_out" ]; then
    echo -e "${YELLOW:-}⚠️  Auto tenant provision skipped: no Railway public domain yet. Re-run deploy after Railway assigns *.up.railway.app.${NC:-}" >&2
    return 0
  fi
  base_url=$(mtx_deploy_parse_tenant_base_url_from_domain_out "$domain_out") || base_url=""
  if [ -z "$base_url" ]; then
    echo -e "${YELLOW:-}⚠️  Auto tenant provision skipped: could not parse public https base URL from domain output.${NC:-}" >&2
    return 0
  fi

  local provision_script="${MTX_ROOT}/master/provision-tenant.sh"
  if [ ! -f "$provision_script" ]; then
    echo -e "${YELLOW:-}⚠️  Auto tenant provision skipped: $provision_script not found.${NC:-}" >&2
    return 0
  fi

  local saved_pwd out_line secret_val rc
  saved_pwd=$(pwd)
  cd "${PROJECT_ROOT}" || return 0
  export MASTER_DATABASE_URL="$app_db"
  set +e
  out_line=$(MTX_VERBOSE="${MTX_VERBOSE:-1}" bash "$provision_script" --emit-secret-only "$org_slug" "$base_url" "${SERVICE_ID}")
  rc=$?
  set -e
  cd "$saved_pwd" || true
  if [ "$rc" != "0" ] || [ -z "$out_line" ]; then
    echo -e "${YELLOW:-}⚠️  Auto tenant provision failed (mtx master provision-tenant exited $rc). Run mtx master provision-tenant manually if needed.${NC:-}" >&2
    return 0
  fi
  case "$out_line" in
  TENANT_SECRET=*)
    secret_val="${out_line#TENANT_SECRET=}"
    ;;
  *)
    echo -e "${YELLOW:-}⚠️  Auto tenant provision: unexpected provision script output.${NC:-}" >&2
    return 0
    ;;
  esac
  if [ -z "$secret_val" ]; then
    return 0
  fi

  mtx_deploy_persist_tenant_secret_to_dotenv "${ENV_FILE:-$PROJECT_ROOT/.env}" "$secret_val" "$rotate"
  export TENANT_SECRET="$secret_val"
  echo -e "${GREEN:-}✅ Auto-provisioned tenant_registry; TENANT_SECRET set for Railway (${org_slug} @ ${base_url})${NC:-}"
  return 0
}
