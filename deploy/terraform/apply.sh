#!/usr/bin/env bash
# MTX terraform apply: PROJECT_ROOT = tree with config/app.json (normatively org-* host); terraform runs in $PROJECT_ROOT/terraform/
desc="Apply Terraform (Railway etc.); deploy unified app service"
set -e

# Directory where this script lives (MTX/deploy/terraform); use for sourcing subroutines, not project's terraform
APPLY_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
MTX_ROOT="$(cd "$APPLY_SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../includes/prepare-env.sh
source "$MTX_ROOT/includes/prepare-env.sh"
# shellcheck source=../../includes/mtx-run.sh
[ -f "$MTX_ROOT/includes/mtx-run.sh" ] && source "$MTX_ROOT/includes/mtx-run.sh"
# mtx deploy exports MTX_VERBOSE; direct `bash apply.sh` leaves it unset — pass subprocess output through
if [ -z "${MTX_VERBOSE+x}" ]; then
  mtx_run() { "$@"; }
fi
declare -F mtx_run &>/dev/null || mtx_run() { "$@"; }

# Run a command with combined stdout+stderr; duplicate to a log file; hide from tty at MTX_VERBOSE<=1
mtx_tf_tee() {
  local logf="$1"
  shift
  if [ "${MTX_VERBOSE:-1}" -le 1 ]; then
    "$@" 2>&1 | tee "$logf" >/dev/null
  else
    "$@" 2>&1 | tee "$logf"
  fi
  return "${PIPESTATUS[0]}"
}

# shellcheck source=../../includes/mtx-deploy-spinner.sh
[ -f "$MTX_ROOT/includes/mtx-deploy-spinner.sh" ] && source "$MTX_ROOT/includes/mtx-deploy-spinner.sh" || {
  mtx_deploy_spinner_start() { :; }
  mtx_deploy_spinner_stop() { :; }
}

# Resolve project root (directory containing config/org.json or legacy config/app.json) so .env is
# always loaded from the right place. Per rule-of-law §1 2026-04-20 Config triad, org identity lives
# in config/org.json; config/app.json is retired on orgs but tolerated as a fallback.
PROJECT_ROOT=""
for root_candidate in . .. ../project-bridge; do
  if [ -f "${root_candidate}/config/org.json" ] || [ -f "${root_candidate}/config/app.json" ]; then
    PROJECT_ROOT="$(cd "$root_candidate" && pwd)"
    break
  fi
done
[ -z "$PROJECT_ROOT" ] && PROJECT_ROOT="$(pwd)"
cd "$PROJECT_ROOT" || exit 1

# Identity source: prefer config/org.json (.org.*), fall back to config/app.json (.app.*).
# Exposes ORG_IDENTITY_FILE + ORG_IDENTITY_KEY for jq paths below.
if [ -f "$PROJECT_ROOT/config/org.json" ]; then
  ORG_IDENTITY_FILE="$PROJECT_ROOT/config/org.json"
  ORG_IDENTITY_KEY="org"
elif [ -f "$PROJECT_ROOT/config/app.json" ]; then
  ORG_IDENTITY_FILE="$PROJECT_ROOT/config/app.json"
  ORG_IDENTITY_KEY="app"
else
  ORG_IDENTITY_FILE=""
  ORG_IDENTITY_KEY=""
fi

SCRIPT_DIR="$PROJECT_ROOT/terraform"
ENV_FILE="$PROJECT_ROOT/.env"
mtx_require_prepare_env "$PROJECT_ROOT" || exit 1

# Railway CLI sends RAILWAY_TOKEN as the HTTP header "project-access-token".
# CR/LF or stray quotes from .env make HeaderValue::from_str fail; the CLI
# then reports a misleading "Login state is corrupt" / "failed to parse header value".
mtx_normalize_railway_token() {
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

mtx_sanitize_railway_token_env_from_dotenv() {
    local k cleaned
    for k in RAILWAY_ACCOUNT_TOKEN RAILWAY_TOKEN RAILWAY_API_TOKEN RAILWAY_PROJECT_TOKEN RAILWAY_PROJECT_TOKEN_STAGING RAILWAY_PROJECT_TOKEN_PRODUCTION; do
        [ -n "${!k:-}" ] || continue
        cleaned="$(mtx_normalize_railway_token "${!k}")"
        printf -v "$k" '%s' "$cleaned"
        export "$k"
    done
}

# Load org .env if it exists (host-specific secrets: JWT, master-auth build-time fan-out, etc.).
# Shared RAILWAY_* tokens are not stored here — they live in $MTX_PREPARE_FILE (see set_prepare_key).
if [ -f "$ENV_FILE" ]; then
    set -a
    source "$ENV_FILE"
    set +a
    mtx_sanitize_railway_token_env_from_dotenv
fi
# Workspace prepare file is the source of truth for Railway IDs/tokens.
set -a
# shellcheck source=/dev/null
source "$MTX_PREPARE_FILE"
set +a
mtx_sanitize_railway_token_env_from_dotenv

# Workspace-root MASTER_JWT_SECRET (.env.master or workspace .env) overrides org .env for pass-down to Railway.
mtx_workspace_overlay_master_jwt_secret || true

# Clear an env var from .env and current shell (for invalid/stale service IDs on 404 etc.)
clear_env_var_in_file() {
    local key="$1"
    local silent="${2:-}"
    if [ ! -f "$ENV_FILE" ]; then
        return
    fi
    if grep -q "^${key}=" "$ENV_FILE" 2>/dev/null; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "/^${key}=/d" "$ENV_FILE"
        else
            sed -i "/^${key}=/d" "$ENV_FILE"
        fi
        unset "$key"
        if [ "$silent" != "true" ]; then
            echo -e "${YELLOW}🗑️  Cleared invalid ${key} from .env (re-run setup to re-discover)${NC}"
        fi
    fi
}

# Set an env var in .env (create file or update existing line) for idempotent re-runs
set_env_var_in_file() {
    local key="$1"
    local value="$2"
    local line="${key}=${value}"
    if [ ! -f "$ENV_FILE" ]; then
        echo "$line" >> "$ENV_FILE"
        return
    fi
    if grep -q "^${key}=" "$ENV_FILE" 2>/dev/null; then
        grep -v "^${key}=" "$ENV_FILE" > "${ENV_FILE}.tmp" && mv "${ENV_FILE}.tmp" "$ENV_FILE"
        echo "$line" >> "$ENV_FILE"
    else
        echo "$line" >> "$ENV_FILE"
    fi
}

# Shared Railway account / workspace / project / project-scoped deploy tokens: persist to workspace
# .mtx.prepare.env (see mtx require/prepare) — not per-org .env, to avoid cross-org drift and duplication.
set_prepare_key() {
    local key="$1" value="$2" line
    line="${key}=${value}"
    if [ -z "${MTX_PREPARE_FILE:-}" ] || [ ! -f "$MTX_PREPARE_FILE" ]; then
        echo "❌ Missing workspace prepare file (run: mtx prepare). Could not write ${key}." >&2
        return 1
    fi
    if grep -q "^${key}=" "$MTX_PREPARE_FILE" 2>/dev/null; then
        grep -v "^${key}=" "$MTX_PREPARE_FILE" > "${MTX_PREPARE_FILE}.tmp" && mv "${MTX_PREPARE_FILE}.tmp" "$MTX_PREPARE_FILE"
    fi
    echo "$line" >> "$MTX_PREPARE_FILE"
    chmod 600 "$MTX_PREPARE_FILE" 2>/dev/null || true
}

clear_prepare_key() {
    local key="$1" silent="${2:-}"
    if [ -z "${MTX_PREPARE_FILE:-}" ] || [ ! -f "$MTX_PREPARE_FILE" ]; then
        return 0
    fi
    if grep -q "^${key}=" "$MTX_PREPARE_FILE" 2>/dev/null; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "/^${key}=/d" "$MTX_PREPARE_FILE"
        else
            sed -i "/^${key}=/d" "$MTX_PREPARE_FILE"
        fi
        unset "$key" 2>/dev/null || true
        if [ "$silent" != "true" ]; then
            echo -e "${YELLOW}🗑️  Cleared invalid ${key} from ${MTX_PREPARE_FILE##*/}${NC}"
        fi
    fi
}

# Persist is-master switch only when the caller is *explicitly* asadmin (MTX_ASADMIN=1 sentinel
# set by MTX/deploy/asadmin.sh). Without this gate, any `mtx deploy` from an org whose .env
# accidentally contains RUN_AS_MASTER=true would re-persist and re-propagate master-ness —
# see apply.sh:1290+ block and rule-of-law "Master promotion is declarative, not incidental".
if [ "${MTX_ASADMIN:-}" = "1" ] && [ -n "${RUN_AS_MASTER:-}" ]; then
    set_env_var_in_file "RUN_AS_MASTER" "true"
elif [ -z "${MTX_ASADMIN:-}" ] && [ -n "${RUN_AS_MASTER:-}" ]; then
    # Defensive: scrub inherited RUN_AS_MASTER from the deploy shell so the master-auth block
    # at apply.sh:1290+ cannot re-set it on the Railway service. The authoritative way to
    # restore master-ness is `mtx deploy asadmin` (guarded by org.master: true).
    echo -e "${YELLOW}⚠️  Ignoring RUN_AS_MASTER in environment for this deploy — MTX_ASADMIN sentinel not set (run 'mtx deploy asadmin' for a master deploy).${NC}"
    unset RUN_AS_MASTER
fi
if [ -n "${MASTER_JWT_SECRET:-}" ]; then
    set_env_var_in_file "MASTER_JWT_SECRET" "$MASTER_JWT_SECRET"
fi
[ -n "${MASTER_AUTH_ISSUER:-}" ] && set_env_var_in_file "MASTER_AUTH_ISSUER" "$MASTER_AUTH_ISSUER"
[ -n "${MASTER_CORS_ORIGINS:-}" ] && set_env_var_in_file "MASTER_CORS_ORIGINS" "$MASTER_CORS_ORIGINS"
[ -n "${MASTER_AUTH_PUBLIC_URL:-}" ] && set_env_var_in_file "MASTER_AUTH_PUBLIC_URL" "$MASTER_AUTH_PUBLIC_URL"
[ -n "${VITE_MASTER_AUTH_URL:-}" ] && set_env_var_in_file "VITE_MASTER_AUTH_URL" "$VITE_MASTER_AUTH_URL"

# After prepare:railway, config/server.json.railway may exist (path payloads vendored under ./payloads/).
# Swap onto server.json only for railway up, then restore the dev file from backup.
mtx_railway_swap_server_config_for_upload() {
    local root="$1"
    local r="$root/config/server.json.railway"
    [ -f "$r" ] || return 0
    cp -a "$root/config/server.json" "$root/config/server.json.mtx-dev-bak"
    cp -a "$r" "$root/config/server.json"
    echo -e "${CYAN}ℹ️  Using config/server.json.railway for Railway upload (payload paths under ./payloads/).${NC}"
}

mtx_railway_restore_server_config_after_upload() {
    local root="$1"
    local bak="$root/config/server.json.mtx-dev-bak"
    [ -f "$bak" ] || return 0
    mv -f "$bak" "$root/config/server.json"
    echo -e "${CYAN}ℹ️  Restored config/server.json for local development.${NC}"
}

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m' # No Color

mtx_output_looks_like_network_problem() {
    local text="${1:-}"
    echo "$text" | grep -qiE "ENOTFOUND|server misbehaving|Temporary failure in name resolution|Could not resolve host|dial tcp: lookup|network is unreachable|No route to host|ECONNRESET|ECONNREFUSED|ETIMEDOUT|i/o timeout|TLS handshake timeout|connection timed out|request timed out|Failed to connect"
}

mtx_print_network_help() {
    echo -e "${RED}🌐 Internet connection problem detected.${NC}"
    echo "The deploy step could not reach required external services (Railway/GitHub/npm)."
    echo "Please check your network and DNS, then run the same command again."
}

# Subroutine: ensure Railway public domain (source from MTX/deploy/terraform, not project dir)
# shellcheck source=ensure-railway-domain.sh
[ -f "$APPLY_SCRIPT_DIR/ensure-railway-domain.sh" ] && source "$APPLY_SCRIPT_DIR/ensure-railway-domain.sh"

echo -e "${BLUE}🚀 Terraform Apply - Smart API Key Detection${NC}"
echo "=========================================="
echo ""

# Check if deploy.json exists
if [ ! -f "$PROJECT_ROOT/config/deploy.json" ]; then
    echo "❌ config/deploy.json not found"
    exit 1
fi

# Parse platform array from deploy.json
PLATFORM_TYPE=$(jq -r '.platform | type' "$PROJECT_ROOT/config/deploy.json" 2>/dev/null || echo "null")

if [ "$PLATFORM_TYPE" != "array" ]; then
    echo "❌ Platform must be an array in deploy.json"
    exit 1
fi

# Detect which platforms are needed (Railway only)
HAS_RAILWAY=$(jq -r '.platform | index("railway") != null' "$PROJECT_ROOT/config/deploy.json" 2>/dev/null || echo "false")

PLATFORMS=$(jq -r '.platform | join(", ")' "$PROJECT_ROOT/config/deploy.json")
echo -e "📋 Platforms in deploy.json: ${GREEN}[$PLATFORMS]${NC}"
echo ""

# Parse script args: [environment] [--force-backend] [--revendor] (flag ignored; unified server has no separate backend service)
ENVIRONMENT="staging"
FORCE_BACKEND="${FORCE_BACKEND:-}"
while [ $# -gt 0 ]; do
    case "$1" in
        --force-backend)
            echo -e "${CYAN}ℹ️  --force-backend is deprecated (single unified Railway service).${NC}"
            FORCE_BACKEND="1"
            shift
            ;;
        --revendor)
            export MTX_VENDOR_REVENDOR=1
            shift
            ;;
        *) ENVIRONMENT="$1"; shift ;;
    esac
done
[ -z "$ENVIRONMENT" ] && ENVIRONMENT="staging"

# One project, two environments: use env-specific project ID only when set (two-project); else single RAILWAY_PROJECT_ID
if [ "$ENVIRONMENT" = "staging" ] && [ -n "${RAILWAY_PROJECT_ID_STAGING:-}" ]; then
    RAILWAY_PROJECT_ID_FOR_RUN="$RAILWAY_PROJECT_ID_STAGING"
elif [ "$ENVIRONMENT" = "production" ] && [ -n "${RAILWAY_PROJECT_ID_PRODUCTION:-}" ]; then
    RAILWAY_PROJECT_ID_FOR_RUN="$RAILWAY_PROJECT_ID_PRODUCTION"
else
    RAILWAY_PROJECT_ID_FOR_RUN="${RAILWAY_PROJECT_ID:-}"
fi

# Get app name and slug (slug used for Railway service name). Reads org.json first, then legacy app.json.
if [ -n "$ORG_IDENTITY_FILE" ]; then
    APP_NAME=$(jq -r ".${ORG_IDENTITY_KEY}.name // empty" "$ORG_IDENTITY_FILE" 2>/dev/null || echo "")
    APP_SLUG=$(jq -r ".${ORG_IDENTITY_KEY}.slug // .${ORG_IDENTITY_KEY}.name // \"app\"" "$ORG_IDENTITY_FILE" 2>/dev/null | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/^-*//;s/-*$//')
else
    APP_NAME=""
    APP_SLUG=""
fi
if [ -z "$APP_NAME" ]; then
    echo "⚠️  name not found in config/org.json or config/app.json, using default"
    APP_NAME="My Application"
fi
[ -z "$APP_SLUG" ] && APP_SLUG="app"

# Check environment variables and prompt for missing ones
echo -e "${BLUE}🔐 Checking API keys...${NC}"
echo ""

TF_VARS=(
    -var="environment=$ENVIRONMENT"
)

# Railway
# Terraform provider needs ACCOUNT token to create services (project tokens get "serviceCreate Not Authorized").
# Project tokens are used only for deploy (railway up) later.
if [ "$HAS_RAILWAY" = "true" ]; then
    if [ -n "$ORG_IDENTITY_FILE" ]; then
        APP_OWNER=$(jq -r ".${ORG_IDENTITY_KEY}.owner // \"\"" "$ORG_IDENTITY_FILE" 2>/dev/null || echo "")
    else
        APP_OWNER=""
    fi
    RAILWAY_TOKEN_VALUE=""
    if [ -n "${RAILWAY_TOKEN:-}" ]; then
        RAILWAY_TOKEN_VALUE="$RAILWAY_TOKEN"
    elif [ -n "${RAILWAY_ACCOUNT_TOKEN:-}" ]; then
        RAILWAY_TOKEN_VALUE="$RAILWAY_ACCOUNT_TOKEN"
    elif [ -n "${TF_VAR_railway_token:-}" ]; then
        RAILWAY_TOKEN_VALUE="$TF_VAR_railway_token"
    fi
    RAILWAY_TOKEN_VALUE="$(mtx_normalize_railway_token "$RAILWAY_TOKEN_VALUE")"
    if [ -z "$RAILWAY_TOKEN_VALUE" ] || [ "$RAILWAY_TOKEN_VALUE" = "null" ]; then
        if [ -t 0 ]; then
            echo -e "${YELLOW}🔐 Railway account token needed (one-time). It will be saved to the workspace prepare file for future deploys.${NC}"
            echo -e "${BLUE}🔗 Get an account token: https://railway.app/account/tokens${NC}"
            echo -e "${CYAN}   (input is hidden; token will be stored in ${MTX_PREPARE_FILE})${NC}"
            read -r -sp "Paste your Railway account token: " RAILWAY_TOKEN_VALUE
            echo ""
            if [ -z "$RAILWAY_TOKEN_VALUE" ]; then
                echo -e "${RED}❌ No token entered. Exiting.${NC}"
                exit 1
            fi
            set_prepare_key "RAILWAY_ACCOUNT_TOKEN" "$RAILWAY_TOKEN_VALUE"
            echo -e "${GREEN}✅ Token saved to ${MTX_PREPARE_FILE##*/} — future deploys will use it automatically.${NC}"
        else
            echo -e "${RED}❌ Railway account token required. Set RAILWAY_ACCOUNT_TOKEN in ${MTX_PREPARE_FILE} or run mtx prepare (get from https://railway.app/account/tokens).${NC}"
            exit 1
        fi
    else
        # Persist so second deploy (e.g. new shell) never needs token again
        set_prepare_key "RAILWAY_ACCOUNT_TOKEN" "$RAILWAY_TOKEN_VALUE"
    fi
    TF_VARS+=(-var="railway_token=$RAILWAY_TOKEN_VALUE")
    echo -e "${GREEN}✅${NC} Railway account token ready"

    # Project token for module + Terraform provider (when set); deploy step uses project token for railway up
    if [ "$ENVIRONMENT" = "staging" ] && [ -n "${RAILWAY_PROJECT_TOKEN_STAGING:-}" ]; then
        TF_VARS+=(-var="railway_project_token=$RAILWAY_PROJECT_TOKEN_STAGING")
    elif [ "$ENVIRONMENT" = "production" ] && [ -n "${RAILWAY_PROJECT_TOKEN_PRODUCTION:-}" ]; then
        TF_VARS+=(-var="railway_project_token=$RAILWAY_PROJECT_TOKEN_PRODUCTION")
    elif [ -n "${RAILWAY_PROJECT_TOKEN:-}" ]; then
        TF_VARS+=(-var="railway_project_token=$RAILWAY_PROJECT_TOKEN")
    fi

    # Resolve workspace ID from app owner name (config/app.json); no manual RAILWAY_WORKSPACE_ID needed
    if [ -n "${RAILWAY_WORKSPACE_ID:-}" ]; then
        echo -e "${GREEN}✅${NC} RAILWAY_WORKSPACE_ID found in environment: $RAILWAY_WORKSPACE_ID"
        TF_VARS+=(-var="railway_workspace_id=$RAILWAY_WORKSPACE_ID")
    else
        echo -e "${BLUE}ℹ️${NC}  Resolving Railway workspace from app owner: ${APP_OWNER:-<first available>}"
        WORKSPACE_QUERY='{"query":"query { me { workspaces { id name } } }"}'
        WORKSPACE_RESPONSE=$(curl -s -X POST "https://backboard.railway.com/graphql/v2" \
            -H "Authorization: Bearer $RAILWAY_TOKEN_VALUE" \
            -H "Content-Type: application/json" \
            -d "$WORKSPACE_QUERY" 2>/dev/null)
        
        if [ $? -eq 0 ] && [ -n "$WORKSPACE_RESPONSE" ]; then
            RAILWAY_WORKSPACE_ID=$(echo "$WORKSPACE_RESPONSE" | jq -r --arg owner "${APP_OWNER:-}" '
                .data.me.workspaces as $ws |
                (if ($owner | length) > 0 then ($ws | map(select((.name | ascii_downcase) == ($owner | ascii_downcase))) | .[0]) else null end) // $ws[0] |
                .id // empty
            ' 2>/dev/null)
            if [ -n "$RAILWAY_WORKSPACE_ID" ] && [ "$RAILWAY_WORKSPACE_ID" != "null" ]; then
                WORKSPACE_NAME=$(echo "$WORKSPACE_RESPONSE" | jq -r --arg owner "${APP_OWNER:-}" '
                    .data.me.workspaces as $ws |
                    (if ($owner | length) > 0 then ($ws | map(select((.name | ascii_downcase) == ($owner | ascii_downcase))) | .[0]) else null end) // $ws[0] |
                    .name // empty
                ' 2>/dev/null)
                echo -e "${GREEN}✅${NC} Found workspace: $WORKSPACE_NAME (ID: $RAILWAY_WORKSPACE_ID)"
                set_prepare_key "RAILWAY_WORKSPACE_ID" "$RAILWAY_WORKSPACE_ID"
                TF_VARS+=(-var="railway_workspace_id=$RAILWAY_WORKSPACE_ID")
            fi
        fi
        if [ -z "${RAILWAY_WORKSPACE_ID:-}" ] || [ "$RAILWAY_WORKSPACE_ID" = "null" ]; then
            echo -e "${RED}❌ Could not resolve Railway workspace. Set RAILWAY_WORKSPACE_ID in ${MTX_PREPARE_FILE:-.mtx.prepare.env} or run mtx prepare, or ensure config org owner (or legacy app.owner) matches a Railway workspace name.${NC}"
            exit 1
        fi
    fi

    # Resolve project: workspace prepare file is source of truth when set (avoids creating duplicates). Only discover from API when unset.
    if [ -n "${RAILWAY_PROJECT_ID:-}" ] && [ "$RAILWAY_PROJECT_ID" != "null" ]; then
        RAILWAY_PROJECT_ID_FOR_RUN="$RAILWAY_PROJECT_ID"
        echo -e "${GREEN}✅${NC} Using project from workspace prepare file: $RAILWAY_PROJECT_ID_FOR_RUN (no new project will be created)"
    elif [ -z "${RAILWAY_PROJECT_ID_FOR_RUN:-}" ] && [ -n "${RAILWAY_WORKSPACE_ID:-}" ] && [ -n "$RAILWAY_TOKEN_VALUE" ]; then
        PROJECTS_QUERY=$(printf '{"query":"query($wid: String!) { workspace(workspaceId: $wid) { projects(first: 50) { edges { node { id name } } } } }", "variables": {"wid": "%s"}}' "$RAILWAY_WORKSPACE_ID")
        PROJECTS_RESPONSE=$(curl -s -X POST "https://backboard.railway.com/graphql/v2" \
            -H "Authorization: Bearer $RAILWAY_TOKEN_VALUE" \
            -H "Content-Type: application/json" \
            -d "$PROJECTS_QUERY" 2>/dev/null)
        if [ $? -eq 0 ] && [ -n "$PROJECTS_RESPONSE" ]; then
            RAILWAY_PROJECT_ID_FOR_RUN=$(echo "$PROJECTS_RESPONSE" | jq -r --arg owner "${APP_OWNER:-}" '
                (.data.workspace.projects // .data.workspace.team.projects).edges[]? | .node | select((.name | ascii_downcase) == ($owner | ascii_downcase)) | .id // empty
            ' 2>/dev/null | head -1)
            if [ -n "$RAILWAY_PROJECT_ID_FOR_RUN" ] && [ "$RAILWAY_PROJECT_ID_FOR_RUN" != "null" ]; then
                echo -e "${GREEN}✅${NC} Using existing project (config/app.json owner): $RAILWAY_PROJECT_ID_FOR_RUN"
            else
                echo -e "${CYAN}ℹ️${NC}  No project named \"${APP_OWNER:-default-owner}\" in workspace; Terraform will create it."
            fi
        fi
    fi

    # Pass existing project ID if available (from env or API resolution)
    if [ -n "${RAILWAY_PROJECT_ID_FOR_RUN:-}" ]; then
        TF_VARS+=(-var="railway_owner_project_id=$RAILWAY_PROJECT_ID_FOR_RUN")
    fi
    
    # Resolve unified app service ID (service name = slug; staging/prod = Railway environments).
    discover_railway_services() {
        EXISTING_APP_ID=""
        [ -z "$SERVICES_RESPONSE" ] && return
        get_id() {
            local name="$1"
            local id=""
            id=$(echo "$SERVICES_RESPONSE" | jq -r --arg name "$name" '.data.project.services.edges[]? | select(.node.name == $name) | .node.id // empty' 2>/dev/null | head -1)
            [ -z "$id" ] || [ "$id" = "null" ] && id=$(echo "$SERVICES_RESPONSE" | jq -r --arg name "$name" '.data.project.services[]? | select(.name == $name) | .id // empty' 2>/dev/null | head -1)
            echo "$id"
        }
        EXISTING_APP_ID=$(get_id "$APP_SLUG")
    }
    EXISTING_APP_ID=""
    if [ -n "${RAILWAY_PROJECT_ID_FOR_RUN:-}" ] && [ -n "${RAILWAY_TOKEN_VALUE:-}" ]; then
        SERVICES_QUERY='{"query":"query($projectId: String!) { project(id: $projectId) { services { edges { node { id name } } } } }", "variables": {"projectId": "'"$RAILWAY_PROJECT_ID_FOR_RUN"'"}}'
        SERVICES_RESPONSE=$(curl -s -X POST "https://backboard.railway.com/graphql/v2" \
            -H "Authorization: Bearer $RAILWAY_TOKEN_VALUE" \
            -H "Content-Type: application/json" \
            -d "$SERVICES_QUERY" 2>/dev/null)
        discover_railway_services
    fi
    if [ -n "$EXISTING_APP_ID" ] && [ "$EXISTING_APP_ID" != "null" ]; then
        echo -e "${GREEN}✅${NC} App service $APP_SLUG already exists"
        TF_VARS+=(-var="railway_service_id=$EXISTING_APP_ID")
    else
        echo -e "${CYAN}ℹ️${NC}  App service $APP_SLUG not found; Terraform will create it"
    fi
else
    echo -e "${RED}❌ Railway is required. Add \"railway\" to config/deploy.json platform array.${NC}"
    exit 1
fi

# Refresh vendored terraform/ from project-bridge before init/apply (prompt on drift when interactive; see .mtx-vendor.pinned).
if [ -f "$MTX_ROOT/lib/vendor-terraform-from-bridge.sh" ]; then
  VTF_MODE=prompt
  if [ ! -t 0 ] || [ -n "${MTX_NONINTERACTIVE:-}" ]; then
    VTF_MODE=auto
  fi
  [ -n "${MTX_DEPLOY_VENDOR_AUTO:-}" ] && VTF_MODE=auto
  [ -n "${MTX_VENDOR_TERRAFORM_MODE:-}" ] && VTF_MODE="$MTX_VENDOR_TERRAFORM_MODE"
  VTF_EXTRA=()
  [ "${MTX_VENDOR_REVENDOR:-}" = 1 ] && VTF_EXTRA+=(--revendor)
  # prompt mode is interactive; auto/non-tty: quiet vendor noise at default -v (mtx_run)
  if [ "$VTF_MODE" = "auto" ]; then
    mtx_run bash "$MTX_ROOT/lib/vendor-terraform-from-bridge.sh" --sync-mode="$VTF_MODE" "${VTF_EXTRA[@]}" "$PROJECT_ROOT"
  else
    bash "$MTX_ROOT/lib/vendor-terraform-from-bridge.sh" --sync-mode="$VTF_MODE" "${VTF_EXTRA[@]}" "$PROJECT_ROOT"
  fi
fi

# Org-json-only trees (no legacy config/app.json) need terraform that reads org.json / optional app.json
# (project-bridge/terraform main.tf migration). Stale vendored main.tf still has data.local_file.app_config
# → plan fails with "open ../config/app.json: no such file". If the operator skipped an earlier re-vendor
# prompt, force a one-shot sync when bridge is available (same as MTX_VENDOR_REVENDOR=1).
if [ -f "$PROJECT_ROOT/config/org.json" ] && [ ! -f "$PROJECT_ROOT/config/app.json" ] && [ -f "$PROJECT_ROOT/terraform/main.tf" ]; then
  if grep -q 'data "local_file" "app_config"' "$PROJECT_ROOT/terraform/main.tf" 2>/dev/null; then
    echo -e "${YELLOW}⚠️  This project uses config/org.json only, but terraform/main.tf still requires legacy config/app.json.${NC}"
    echo "    Forcing re-vendor from project-bridge/terraform so Terraform matches the org triad." >&2
    if [ -f "$MTX_ROOT/lib/vendor-terraform-from-bridge.sh" ]; then
      bash "$MTX_ROOT/lib/vendor-terraform-from-bridge.sh" --sync-mode=auto --revendor "$PROJECT_ROOT" || true
    fi
    if grep -q 'data "local_file" "app_config"' "$PROJECT_ROOT/terraform/main.tf" 2>/dev/null; then
      echo -e "${RED}❌ terraform/main.tf is still the legacy app.json-only version.${NC}" >&2
      echo "   Fix: place project-bridge next to this repo (../project-bridge), set PROJECT_BRIDGE_ROOT, or run:" >&2
      echo "     MTX_VENDOR_REVENDOR=1 mtx deploy …   (or mtx deploy --revendor …)" >&2
      echo "   If terraform is listed in .mtx-vendor.pinned, temporarily unpin to allow the upgrade." >&2
      exit 1
    fi
    echo -e "${GREEN}✅${NC} Terraform refreshed for org.json-only config."
  fi
fi

echo ""
echo -e "${BLUE}🚀 Running terraform apply...${NC}"
echo ""

# One-line status during terraform (cleared before "Deploying code" so logs do not blend). MTX_DEPLOY_SPINNER=0 to disable.
trap 'mtx_deploy_spinner_stop' EXIT
mtx_deploy_spinner_start "$ENVIRONMENT" "$APP_NAME"

# Change to terraform directory
cd "$SCRIPT_DIR"

# Ensure backend and providers are initialized (idempotent; no-op if already inited)
TF_INIT_LOG="/tmp/tf-init-$$.log"
if ! mtx_tf_tee "$TF_INIT_LOG" terraform init -reconfigure -input=false; then
    echo ""
    echo -e "${RED}❌ terraform init failed${NC}"
    if [ -f "$TF_INIT_LOG" ] && mtx_output_looks_like_network_problem "$(cat "$TF_INIT_LOG")"; then
        echo ""
        mtx_print_network_help
    fi
    rm -f "$TF_INIT_LOG"
    exit 1
fi
rm -f "$TF_INIT_LOG"

# When using an existing project, import it so Terraform tracks it. Without import, apply would create a duplicate project.
# Use TF_VAR_* env vars for import (avoid passing token on command line — prevents quote/special-char breakage).
# Import must succeed and project must appear in state, or we abort.
if [ "$HAS_RAILWAY" = "true" ] && [ -n "${RAILWAY_PROJECT_ID_FOR_RUN:-}" ] && [ "$RAILWAY_PROJECT_ID_FOR_RUN" != "null" ]; then
    if ! terraform state list 2>/dev/null | grep -qF 'module.railway_owner[0].railway_project.owner[0]'; then
        echo -e "${CYAN}ℹ️  Importing existing Railway project into state (so Terraform will not create a duplicate)...${NC}"
        export TF_VAR_environment="$ENVIRONMENT"
        export TF_VAR_railway_token="$RAILWAY_TOKEN_VALUE"
        export TF_VAR_railway_workspace_id="$RAILWAY_WORKSPACE_ID"
        export TF_VAR_railway_owner_project_id="$RAILWAY_PROJECT_ID_FOR_RUN"
        if [ "$ENVIRONMENT" = "staging" ] && [ -n "${RAILWAY_PROJECT_TOKEN_STAGING:-}" ]; then
            export TF_VAR_railway_project_token="$RAILWAY_PROJECT_TOKEN_STAGING"
        elif [ "$ENVIRONMENT" = "production" ] && [ -n "${RAILWAY_PROJECT_TOKEN_PRODUCTION:-}" ]; then
            export TF_VAR_railway_project_token="$RAILWAY_PROJECT_TOKEN_PRODUCTION"
        elif [ -n "${RAILWAY_PROJECT_TOKEN:-}" ]; then
            export TF_VAR_railway_project_token="$RAILWAY_PROJECT_TOKEN"
        fi
        if ! terraform import -input=false 'module.railway_owner[0].railway_project.owner[0]' "$RAILWAY_PROJECT_ID_FOR_RUN"; then
            echo ""
            echo -e "${RED}❌ Import failed. Terraform would create a new project with the same name if we continued.${NC}"
            echo -e "${YELLOW}   Fix the error above (e.g. token access, project ID) and re-run.${NC}"
            echo -e "${YELLOW}   Or remove RAILWAY_PROJECT_ID from ${MTX_PREPARE_FILE} only if you intend to create a new project.${NC}"
            exit 1
        fi
        if ! terraform state list 2>/dev/null | grep -qF 'module.railway_owner[0].railway_project.owner[0]'; then
            echo -e "${RED}❌ Import reported success but project is not in state. Aborting to avoid creating a duplicate project.${NC}"
            exit 1
        fi
        echo -e "${GREEN}✅ Project imported; apply will not create a duplicate.${NC}"
    fi
fi

# Remove legacy single "backend" resource from state if present
if terraform state list 2>/dev/null | grep -q 'module.railway_owner\[0\].railway_service.backend\[0\]'; then
    echo -e "${CYAN}ℹ️  Removing legacy backend from state...${NC}"
    terraform state rm 'module.railway_owner[0].railway_service.backend[0]' 2>/dev/null || true
fi
# Unified server: drop backend-staging / backend-prod from Terraform state (no longer in config). Railway may still show those services until you delete them in the dashboard.
for _be in 'module.railway_owner[0].railway_service.backend_staging[0]' 'module.railway_owner[0].railway_service.backend_production[0]'; do
    if terraform state list 2>/dev/null | grep -qF "$_be"; then
        echo -e "${CYAN}ℹ️  Removing ${_be} from Terraform state (unified app service only)...${NC}"
        terraform state rm "$_be" 2>/dev/null || true
    fi
done
# Drop old dual-app resources from state (replaced by single railway_service.app[0]).
for _legacy_app in \
    'module.railway_app[0].railway_service.app_staging[0]' \
    'module.railway_app[0].railway_service.app_production[0]'; do
    if terraform state list 2>/dev/null | grep -qF "$_legacy_app"; then
        echo -e "${CYAN}ℹ️  Removing ${_legacy_app} from state (unified single app service)...${NC}"
        terraform state rm "$_legacy_app" 2>/dev/null || true
    fi
done

# When adopting an existing Railway app by id, drop managed app from state so Terraform uses -var only.
if [ -n "${EXISTING_APP_ID:-}" ] && [ "$EXISTING_APP_ID" != "null" ]; then
    if terraform state list 2>/dev/null | grep -qF 'module.railway_app[0].railway_service.app[0]'; then
        echo -e "${CYAN}ℹ️  Removing app from state (using existing discovered service id)...${NC}"
        terraform state rm 'module.railway_app[0].railway_service.app[0]' 2>/dev/null || true
    fi
fi

# Run terraform apply - show output in real-time, capture for retry check
# Using -auto-approve since we're in a script and user has already confirmed via setup.sh
set +e  # Don't exit on error, we'll check exit code
TF_APPLY_LOG="/tmp/tf-apply-$$.log"
mtx_tf_tee "$TF_APPLY_LOG" terraform apply -auto-approve "${TF_VARS[@]}"
TERRAFORM_EXIT=$?
set -e  # Re-enable exit on error

# If apply failed with "already exists" (service created outside Terraform), discover and re-apply with existing IDs
if [ $TERRAFORM_EXIT -ne 0 ] && grep -q "already exists in this project" "$TF_APPLY_LOG" 2>/dev/null; then
    echo ""
    echo -e "${BLUE}🔧 Service already exists; discovering and re-applying with existing IDs...${NC}"
    SERVICES_RESPONSE=$(curl -s -X POST "https://backboard.railway.com/graphql/v2" \
        -H "Authorization: Bearer $RAILWAY_TOKEN_VALUE" \
        -H "Content-Type: application/json" \
        -d "$SERVICES_QUERY" 2>/dev/null)
    discover_railway_services
    [ -n "$EXISTING_APP_ID" ] && [ "$EXISTING_APP_ID" != "null" ] && TF_VARS+=(-var="railway_service_id=$EXISTING_APP_ID") && terraform state rm 'module.railway_app[0].railway_service.app[0]' 2>/dev/null || true
    echo ""
    if [ "${MTX_VERBOSE:-1}" -le 1 ]; then
      if mtx_run terraform apply -auto-approve "${TF_VARS[@]}"; then
        TERRAFORM_EXIT=0
      else
        TERRAFORM_EXIT=$?
      fi
    else
      terraform apply -auto-approve "${TF_VARS[@]}"
      TERRAFORM_EXIT=$?
    fi
fi
# If apply failed due to backend not initialized, run init and retry once (idempotent recovery)
if [ $TERRAFORM_EXIT -ne 0 ] && [ -f "$TF_APPLY_LOG" ] && grep -q "Backend initialization required\|please run \"terraform init\"" "$TF_APPLY_LOG" 2>/dev/null; then
    echo ""
    echo -e "${CYAN}🔄 Backend not initialized; running terraform init and retrying apply...${NC}"
    if [ "${MTX_VERBOSE:-1}" -le 1 ]; then
      if mtx_run terraform init -reconfigure -input=false && mtx_run terraform apply -auto-approve "${TF_VARS[@]}"; then
        TERRAFORM_EXIT=0
      fi
    else
      if terraform init -reconfigure -input=false && terraform apply -auto-approve "${TF_VARS[@]}"; then
        TERRAFORM_EXIT=0
      fi
    fi
fi
rm -f "$TF_APPLY_LOG"

if [ $TERRAFORM_EXIT -ne 0 ]; then
    echo ""
    echo -e "${RED}❌ Terraform apply failed${NC}"
    if [ -f "$TF_APPLY_LOG" ] && mtx_output_looks_like_network_problem "$(cat "$TF_APPLY_LOG")"; then
        mtx_print_network_help
    else
        echo -e "${CYAN}Review the error messages above for details.${NC}"
    fi
    echo ""
    echo -e "${YELLOW}Common issues:${NC}"
    echo "  - State lock: Another Terraform process may be running"
    echo "  - Missing variables: Check that all required tokens are set"
    echo "  - Invalid configuration: Review Terraform error messages above"
    echo ""
    
    exit 1
fi

# Record project-bridge/terraform fingerprint so mtx build can re-vendor when canon drifts.
if [ -f "$MTX_ROOT/lib/vendor-terraform-from-bridge.sh" ]; then
  mtx_run bash "$MTX_ROOT/lib/vendor-terraform-from-bridge.sh" --write-digest "$PROJECT_ROOT" || true
fi

# Output was already shown in real-time above, no need to echo again

# If we are not doing an app deploy, stop the infra spinner (terraform phase only)
if [ "$HAS_RAILWAY" != "true" ]; then
  mtx_deploy_spinner_stop
fi

# If Railway was deployed successfully, automatically deploy code
if [ "$HAS_RAILWAY" = "true" ]; then
    # Finish terraform status line before any section headers (avoids text glued to the spinner line)
    mtx_deploy_spinner_stop
    echo ""
    echo -e "${BLUE}🚀 Deploying code to Railway...${NC}"
    echo "=========================================="
    echo ""
    
    SERVICE_ID=$(terraform output -raw railway_app_service_id 2>/dev/null || echo "")
    PROJECT_ID=$(terraform output -raw railway_project_id 2>/dev/null || echo "")
    # If project ID changed (e.g. Terraform just created a new project), clear project tokens — they're for the old project
    OLD_PROJECT_ID=""
    if [ -f "${MTX_PREPARE_FILE:-}" ] && grep -q "^RAILWAY_PROJECT_ID=" "$MTX_PREPARE_FILE" 2>/dev/null; then
        OLD_PROJECT_ID=$(grep "^RAILWAY_PROJECT_ID=" "$MTX_PREPARE_FILE" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'")
    elif [ -f "$ENV_FILE" ] && grep -q "^RAILWAY_PROJECT_ID=" "$ENV_FILE" 2>/dev/null; then
        OLD_PROJECT_ID=$(grep "^RAILWAY_PROJECT_ID=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'")
    fi
    if [ -n "$PROJECT_ID" ] && [ "$PROJECT_ID" != "null" ] && [ -n "$OLD_PROJECT_ID" ] && [ "$OLD_PROJECT_ID" != "$PROJECT_ID" ]; then
        clear_prepare_key "RAILWAY_PROJECT_TOKEN_STAGING" "true"
        clear_prepare_key "RAILWAY_PROJECT_TOKEN_PRODUCTION" "true"
        clear_env_var_in_file "RAILWAY_PROJECT_TOKEN_STAGING" "true"
        clear_env_var_in_file "RAILWAY_PROJECT_TOKEN_PRODUCTION" "true"
        unset RAILWAY_PROJECT_TOKEN_STAGING RAILWAY_PROJECT_TOKEN_PRODUCTION
        echo -e "${YELLOW}🔄 Project ID changed (new project created). Cleared old project tokens; you'll be prompted for new ones for this project.${NC}"
        echo ""
    fi
    # Persist current project ID for next run
    if [ -n "$PROJECT_ID" ] && [ "$PROJECT_ID" != "null" ]; then
        set_prepare_key "RAILWAY_PROJECT_ID" "$PROJECT_ID"
    fi
    
    # Unified server: one Railway app service; deploy target environment is Railway $ENVIRONMENT.
    APP_SERVICE_NAME_FOR_ENV="$APP_SLUG"
    echo -e "${CYAN}Deploy target (environment: $ENVIRONMENT):${NC}"
    echo -e "  Unified app service: $APP_SERVICE_NAME_FOR_ENV ${GREEN}(service id: ${SERVICE_ID:-<none>})${NC}"
    echo ""
    
    if [ -z "$SERVICE_ID" ] || [ "$SERVICE_ID" = "null" ]; then
        echo -e "${YELLOW}⚠️  Could not get Railway app service ID for $ENVIRONMENT${NC}"
        echo "Skipping code deployment"
        mtx_deploy_spinner_stop
    else
        echo -e "${GREEN}✅ Deploying app to $APP_SERVICE_NAME_FOR_ENV ($SERVICE_ID) for environment $ENVIRONMENT${NC}"
        echo -e "${GREEN}✅ Project: $PROJECT_ID${NC}"
        echo ""
        
        # Navigate to project root
        cd "$PROJECT_ROOT"

        # Harden: framework project-bridge (sibling) or cwd must have placeholder org.json before link/build/upload.
        if [ -f "$MTX_ROOT/includes/verify-pb-framework-identity.sh" ]; then
            # shellcheck source=../../includes/verify-pb-framework-identity.sh
            # shellcheck disable=SC1090
            source "$MTX_ROOT/includes/verify-pb-framework-identity.sh"
            mtx_verify_project_bridge_identity_for_build_context "$PROJECT_ROOT" "$MTX_ROOT" || exit 1
        else
            echo "❌ MTX missing $MTX_ROOT/includes/verify-pb-framework-identity.sh" >&2
            exit 1
        fi
        
        # Check if Railway CLI is installed
        if ! command -v railway &> /dev/null; then
            echo -e "${BLUE}ℹ️  Installing Railway CLI...${NC}"
            curl -fsSL https://railway.app/install.sh | sh
            export PATH="$HOME/.railway/bin:$PATH"
        fi
        
        # Railway CLI requires project token for 'railway up', but we have account token
        # Try using account token first, fall back to API if it doesn't work
        if [ -z "${RAILWAY_TOKEN:-}" ] && [ -n "$RAILWAY_TOKEN_VALUE" ]; then
            export RAILWAY_TOKEN="$RAILWAY_TOKEN_VALUE"
        fi
        
        # Also try RAILWAY_API_TOKEN (some CLI commands work with account token)
        if [ -n "$RAILWAY_TOKEN_VALUE" ]; then
            export RAILWAY_API_TOKEN="$RAILWAY_TOKEN_VALUE"
        fi
        
        # Explicitly link to this environment's app service so we deploy to the correct one (not another env's service)
        if [ ! -d ".railway" ]; then
            echo -e "${BLUE}🔗 Linking to app service $APP_SERVICE_NAME_FOR_ENV...${NC}"
            railway link --service "$SERVICE_ID" --project "$PROJECT_ID" --environment "$ENVIRONMENT" 2>/dev/null || {
                mkdir -p .railway
                echo "$SERVICE_ID" > .railway/service
                echo "$PROJECT_ID" > .railway/project
                echo "$ENVIRONMENT" > .railway/environment
            }
        else
            LINKED_SERVICE=$(cat .railway/service 2>/dev/null || echo "")
            if [ "$LINKED_SERVICE" != "$SERVICE_ID" ]; then
                echo -e "${BLUE}🔗 Re-linking to app service $APP_SERVICE_NAME_FOR_ENV (was linked to different service)...${NC}"
                rm -rf .railway
                railway link --service "$SERVICE_ID" --project "$PROJECT_ID" --environment "$ENVIRONMENT" 2>/dev/null || {
                    mkdir -p .railway
                    echo "$SERVICE_ID" > .railway/service
                    echo "$PROJECT_ID" > .railway/project
                    echo "$ENVIRONMENT" > .railway/environment
                }
            fi
        fi
        echo -e "${GREEN}✅ Linked to $APP_SERVICE_NAME_FOR_ENV${NC}"
        echo ""
        
        # Build app server (shared with mtx build server; skip if pre-built)
        if [ "${MTX_SKIP_BUILD:-}" = "1" ]; then
            echo -e "${BLUE}ℹ️  MTX_SKIP_BUILD=1 — skipping build (use mtx build server if needed)${NC}"
            echo ""
        else
            if [ ! -f "$MTX_ROOT/build.sh" ]; then
                echo -e "${RED}❌ MTX build.sh missing at $MTX_ROOT/build.sh (incomplete MTX install?)${NC}" >&2
                exit 1
            fi
            bash "$MTX_ROOT/build.sh" server || {
                echo -e "${RED}❌ Build failed${NC}"
                exit 1
            }
            echo ""
        fi
        
        # Function to handle Railway deployment with service selection and environment
        # Returns: 0 on success, 1 on failure
        # Output is captured in global variable RAILWAY_DEPLOY_OUTPUT
        # Sets NEED_PROJECT_TOKEN_FOR_ENV=1 if project token is needed for environment creation
        deploy_to_railway() {
            local TOKEN PROJ_ID SVC_ID ENV_NAME VERBOSE
            TOKEN="$(mtx_normalize_railway_token "$1")"
            PROJ_ID="$(mtx_normalize_railway_token "$2")"
            SVC_ID="$(mtx_normalize_railway_token "$3")"
            ENV_NAME="$(mtx_normalize_railway_token "$4")"  # staging or production
            VERBOSE="${5:-}"  # non-empty = add --verbose (e.g. for backend to see tarball size)
            
            # Set token for Railway CLI
            export RAILWAY_TOKEN="$TOKEN"
            unset RAILWAY_API_TOKEN
            
            # Global variable to capture output
            RAILWAY_DEPLOY_OUTPUT=""
            
            # Note: Environment creation is handled BEFORE calling this function
            # This function only handles deployment
            # Pass project, service, and environment explicitly so the token doesn't "pick" a different project/env
            # --no-gitignore: include prepared targets/server/dist + npm-packs (see template .gitignore / .railwayignore)
            local UP_OPTS="--project $PROJ_ID --service $SVC_ID --environment $ENV_NAME --no-gitignore"
            [ -n "$VERBOSE" ] && UP_OPTS="$UP_OPTS --verbose"
            # At default -v, hide railway up noise; still capture for parsing (no tee to tty)
            local OUTPUT EXIT_CODE
            if [ "${MTX_VERBOSE:-1}" -le 1 ]; then
                set +e
                OUTPUT=$(railway up $UP_OPTS 2>&1)
                EXIT_CODE=$?
                set -e
            else
                OUTPUT=$(railway up $UP_OPTS 2>&1 | tee /dev/stderr)
                EXIT_CODE=${PIPESTATUS[0]}
            fi
            
            # Store output in global variable for caller to check
            RAILWAY_DEPLOY_OUTPUT="$OUTPUT"
            
            # Check if error is about multiple services (even with --service flag)
            if echo "$OUTPUT" | grep -qi "Multiple services found\|Please specify a service"; then
                echo -e "${YELLOW}⚠️  Multiple services found in project${NC}"
                echo "Fetching list of services..."
                echo ""
                
                # Query Railway API for services
                local SERVICES_QUERY='{"query":"query { project(id: \"'$PROJ_ID'\") { services { id name } } }"}'
                local SERVICES_RESPONSE=$(curl -s -X POST "https://backboard.railway.com/graphql/v2" \
                    -H "Authorization: Bearer $TOKEN" \
                    -H "Content-Type: application/json" \
                    -d "$SERVICES_QUERY" 2>/dev/null)
                
                # Parse services
                local SERVICE_COUNT=$(echo "$SERVICES_RESPONSE" | jq -r '.data.project.services | length' 2>/dev/null)
                
                if [ -z "$SERVICE_COUNT" ] || [ "$SERVICE_COUNT" = "0" ] || [ "$SERVICE_COUNT" = "null" ]; then
                    echo -e "${RED}❌ Could not fetch services list${NC}"
                    return 1
                fi
                
                echo -e "${CYAN}Available services:${NC}"
                echo ""
                
                # Display services with numbers
                local I=1
                local SERVICE_IDS=()
                local SERVICE_NAMES=()
                
                while [ $I -le $SERVICE_COUNT ]; do
                    local INDEX=$((I - 1))
                    local SVC_NAME=$(echo "$SERVICES_RESPONSE" | jq -r ".data.project.services[$INDEX].name" 2>/dev/null)
                    local SVC_ID_VAL=$(echo "$SERVICES_RESPONSE" | jq -r ".data.project.services[$INDEX].id" 2>/dev/null)
                    
                    SERVICE_IDS+=("$SVC_ID_VAL")
                    SERVICE_NAMES+=("$SVC_NAME")
                    
                    echo "  $I) $SVC_NAME (ID: $SVC_ID_VAL)"
                    I=$((I + 1))
                done
                
                echo ""
                echo -e "${CYAN}Which service would you like to deploy to?${NC}"
                read -p "Enter number (1-$SERVICE_COUNT): " SELECTION
                
                # Validate selection
                if ! [[ "$SELECTION" =~ ^[0-9]+$ ]] || [ "$SELECTION" -lt 1 ] || [ "$SELECTION" -gt "$SERVICE_COUNT" ]; then
                    echo -e "${RED}❌ Invalid selection${NC}"
                    return 1
                fi
                
                local SELECTED_INDEX=$((SELECTION - 1))
                local SELECTED_SERVICE_ID="${SERVICE_IDS[$SELECTED_INDEX]}"
                local SELECTED_SERVICE_NAME="${SERVICE_NAMES[$SELECTED_INDEX]}"
                
                echo ""
                echo -e "${BLUE}🚀 Deploying to service: $SELECTED_SERVICE_NAME${NC}"
                echo ""
                
                # Deploy to selected service with project + environment (explicit so token doesn't pick)
                if [ "${MTX_VERBOSE:-1}" -le 1 ]; then
                    set +e
                    OUTPUT=$(railway up --project "$PROJ_ID" --service "$SELECTED_SERVICE_ID" --environment "$ENV_NAME" --no-gitignore 2>&1)
                    EXIT_CODE=$?
                    set -e
                else
                    OUTPUT=$(railway up --project "$PROJ_ID" --service "$SELECTED_SERVICE_ID" --environment "$ENV_NAME" --no-gitignore 2>&1 | tee /dev/stderr)
                    EXIT_CODE=${PIPESTATUS[0]}
                fi
                
                # Store output in global variable
                RAILWAY_DEPLOY_OUTPUT="$OUTPUT"
                
                # Check both exit code and output for error patterns
                local HAS_ERROR=false
                
                if [ $EXIT_CODE -ne 0 ]; then
                    HAS_ERROR=true
                elif echo "$OUTPUT" | grep -qiE "error|timed out|failed|Caused by:|operation timed out"; then
                    HAS_ERROR=true
                fi
                
                if [ "$HAS_ERROR" = "true" ]; then
                    echo -e "${RED}❌ Deployment failed${NC}"
                    return 1
                else
                    echo -e "${GREEN}✅ Deployment successful via Railway CLI!${NC}"
                    return 0
                fi
            else
                # No multiple services issue, check if deployment succeeded
                # If Railway CLI printed "Deploy complete", treat as success (don't false-fail on other "failed" wording)
                if echo "$OUTPUT" | grep -qi "Deploy complete"; then
                    return 0
                fi
                # Check both exit code and output for error patterns
                # Railway CLI might return 0 even on timeout/errors
                local HAS_ERROR=false
                local IS_TOKEN_ERROR=false
                
                if [ $EXIT_CODE -ne 0 ]; then
                    HAS_ERROR=true
                elif echo "$OUTPUT" | grep -qiE "Unauthorized|Invalid RAILWAY_TOKEN|invalid.*token|token.*invalid|Select a workspace|Select a project|Please specify"; then
                    HAS_ERROR=true
                    IS_TOKEN_ERROR=true
                elif echo "$OUTPUT" | grep -qiE "error|timed out|failed|Caused by:|operation timed out"; then
                    HAS_ERROR=true
                fi
                
                if [ "$HAS_ERROR" = "true" ]; then
                    # Failure - output was already displayed via tee
                    if [ "$IS_TOKEN_ERROR" = "true" ]; then
                        echo -e "${RED}❌ Token validation failed - token is invalid or expired${NC}"
                    fi
                    return 1
                else
                    # Success - output was already displayed
                    return 0
                fi
            fi
        }
        
        # Function to check if environment exists (no automatic creation)
        check_environment_exists() {
            local TOKEN="$1"
            local PROJ_ID="$2"
            local ENV_NAME="$3"  # staging or production
            
            # Temporarily disable set -e
            set +e
            local ENV_QUERY='{"query":"query { project(id: \"'$PROJ_ID'\") { environments { id name } } }"}'
            local ENV_RESPONSE=$(curl -s -X POST "https://backboard.railway.com/graphql/v2" \
                -H "Authorization: Bearer $TOKEN" \
                -H "Content-Type: application/json" \
                -d "$ENV_QUERY" 2>/dev/null || echo "")
            local CURL_EXIT=$?
            set -e
            
            # Check for curl failure or empty response
            if [ $CURL_EXIT -ne 0 ] || [ -z "$ENV_RESPONSE" ]; then
                return 1
            fi
            
            # Check if response contains errors
            local HAS_ERRORS=$(echo "$ENV_RESPONSE" | jq -r '.errors // empty' 2>/dev/null)
            if [ -n "$HAS_ERRORS" ] && [ "$HAS_ERRORS" != "null" ]; then
                return 1
            fi
            
            set +e
            local ENV_ID=$(echo "$ENV_RESPONSE" | jq -r ".data.project.environments[] | select(.name == \"$ENV_NAME\") | .id" 2>/dev/null)
            local JQ_EXIT=$?
            set -e
            
            # Check if jq succeeded and found an environment ID
            if [ $JQ_EXIT -eq 0 ] && [ -n "$ENV_ID" ] && [ "$ENV_ID" != "null" ] && [ "$ENV_ID" != "" ]; then
                return 0  # Environment exists
            else
                return 1  # Environment does not exist
            fi
        }

        # Central DB policy: one shared DB service per environment, then wire app service DATABASE_URL.
        ensure_central_database_for_env() {
            local TOKEN="$1"
            local PROJ_ID="$2"
            local ENV_NAME="$3"
            local APP_SVC_ID="$4"
            local ACCOUNT_TOKEN="$5"
            local DB_SVC_NAME="mtx-db-${ENV_NAME}"
            local DB_SVC_ID=""
            local SERVICES_QUERY SERVICES_RESPONSE DB_REF APP_VARS DB_URL_VAL
            local ACCOUNT_API_TOKEN="${ACCOUNT_TOKEN:-$TOKEN}"
            local DB_ID_VAR DB_ID_FROM_ENV DB_MATCH_COUNT
            local -a DB_MATCHES

            echo -e "${BLUE}🗄️  Ensuring central database service (${DB_SVC_NAME})...${NC}"
            mtx_deploy_spinner_start "database" "${APP_NAME:-$APP_SLUG}"
            trap 'mtx_deploy_spinner_stop' RETURN

            SERVICES_QUERY='{"query":"query($projectId: String!) { project(id: $projectId) { services { edges { node { id name } } } } }", "variables": {"projectId": "'"$PROJ_ID"'"}}'
            SERVICES_RESPONSE=$(curl -s -X POST "https://backboard.railway.com/graphql/v2" \
                -H "Authorization: Bearer $ACCOUNT_API_TOKEN" \
                -H "Content-Type: application/json" \
                -d "$SERVICES_QUERY" 2>/dev/null)
            DB_ID_VAR="MTX_DB_SERVICE_ID_${ENV_NAME^^}"
            DB_ID_FROM_ENV="${!DB_ID_VAR:-}"

            if [ -n "$DB_ID_FROM_ENV" ] && [ "$DB_ID_FROM_ENV" != "null" ]; then
                DB_SVC_ID="$DB_ID_FROM_ENV"
                DB_SVC_NAME=$(echo "$SERVICES_RESPONSE" | jq -r --arg id "$DB_SVC_ID" '.data.project.services.edges[]? | select(.node.id == $id) | .node.name // empty' 2>/dev/null | head -1)
                if [ -z "$DB_SVC_NAME" ]; then
                    echo -e "${RED}❌ ${DB_ID_VAR}=${DB_SVC_ID} was not found in project services.${NC}"
                    return 1
                fi
            else
                DB_SVC_ID=$(echo "$SERVICES_RESPONSE" | jq -r --arg name "$DB_SVC_NAME" '.data.project.services.edges[]? | select(.node.name == $name) | .node.id // empty' 2>/dev/null | head -1)
                if [ -z "$DB_SVC_ID" ] || [ "$DB_SVC_ID" = "null" ]; then
                    # Auto-adopt exactly one plausible DB service when present.
                    mapfile -t DB_MATCHES < <(echo "$SERVICES_RESPONSE" | jq -r '
                        .data.project.services.edges[]?.node
                        | select(.name | test("(^Postgres|postgres|database|\\bdb\\b)"; "i"))
                        | (.id + "\t" + .name)
                      ' 2>/dev/null)
                    DB_MATCH_COUNT="${#DB_MATCHES[@]}"
                    if [ "$DB_MATCH_COUNT" -eq 1 ]; then
                        DB_SVC_ID="$(echo "${DB_MATCHES[0]}" | cut -f1)"
                        DB_SVC_NAME="$(echo "${DB_MATCHES[0]}" | cut -f2)"
                        echo -e "${YELLOW}ℹ️  Using existing Postgres service for ${ENV_NAME}: ${DB_SVC_NAME}${NC}"
                        set_env_var_in_file "$DB_ID_VAR" "$DB_SVC_ID"
                    elif [ "$DB_MATCH_COUNT" -gt 1 ]; then
                        echo -e "${RED}❌ Multiple Postgres services found; refusing auto-pick to avoid more DB sprawl.${NC}"
                        echo "Set ${DB_ID_VAR} in .mtx.prepare.env to one of:"
                        printf '  %s\n' "${DB_MATCHES[@]}"
                        return 1
                    else
                        echo -e "${RED}❌ No Postgres service found and auto-create is disabled to prevent duplicates.${NC}"
                        echo "Create one DB service manually, then set ${DB_ID_VAR} in .mtx.prepare.env."
                        return 1
                    fi
                fi
            fi

            DB_REF="\${{${DB_SVC_NAME}.DATABASE_URL}}"
            DB_PUBLIC_REF="\${{${DB_SVC_NAME}.DATABASE_PUBLIC_URL}}"
            export RAILWAY_TOKEN="$TOKEN"
            unset RAILWAY_API_TOKEN
            (cd "$PROJECT_ROOT" && railway variable set "DATABASE_URL=$DB_REF" --service "$APP_SVC_ID" --environment "$ENV_NAME" --skip-deploys >/dev/null 2>&1) || {
                echo -e "${RED}❌ Failed to set DATABASE_URL on app service (${APP_SVC_ID}) for ${ENV_NAME}.${NC}"
                return 1
            }
            # DATABASE_PUBLIC_URL is wired as a fallback for Railway private-network DNS flaps (*.railway.internal EAI_AGAIN).
            # If the Postgres service doesn't expose a public URL this silently no-ops on Railway's side.
            (cd "$PROJECT_ROOT" && railway variable set "DATABASE_PUBLIC_URL=$DB_PUBLIC_REF" --service "$APP_SVC_ID" --environment "$ENV_NAME" --skip-deploys >/dev/null 2>&1) || \
                echo -e "${YELLOW}⚠️  Could not set DATABASE_PUBLIC_URL on app service (${APP_SVC_ID}) for ${ENV_NAME}; continuing.${NC}"
            (cd "$PROJECT_ROOT" && railway variable set "DATABASE_PROVIDER=postgresql" --service "$APP_SVC_ID" --environment "$ENV_NAME" --skip-deploys >/dev/null 2>&1) || {
                echo -e "${RED}❌ Failed to set DATABASE_PROVIDER=postgresql on app service (${APP_SVC_ID}) for ${ENV_NAME}.${NC}"
                return 1
            }
            # Force IPv6-first DNS resolution so Node's dns.lookup() doesn't return EAI_AGAIN on *.railway.internal AAAA-only hosts.
            (cd "$PROJECT_ROOT" && railway variable set 'NODE_OPTIONS=--dns-result-order=ipv6first' --service "$APP_SVC_ID" --environment "$ENV_NAME" --skip-deploys >/dev/null 2>&1) || \
                echo -e "${YELLOW}⚠️  Could not set NODE_OPTIONS on app service (${APP_SVC_ID}) for ${ENV_NAME}; continuing.${NC}"

            APP_VARS=$(cd "$PROJECT_ROOT" && railway variable list --service "$APP_SVC_ID" --environment "$ENV_NAME" --json 2>/dev/null || echo "{}")
            DB_URL_VAL=$(echo "$APP_VARS" | jq -r '.DATABASE_URL // empty' 2>/dev/null)
            if [ -z "$DB_URL_VAL" ] || [ "$DB_URL_VAL" = "null" ]; then
                echo -e "${RED}❌ DATABASE_URL not present after wiring ${DB_SVC_NAME} -> app service.${NC}"
                return 1
            fi

            echo -e "${GREEN}✅ DATABASE_URL wired from ${DB_SVC_NAME} to app service for ${ENV_NAME}.${NC}"
            return 0
        }
        
        # Pause spinner before any project-token / staging prompts (stderr reads)
        mtx_deploy_spinner_stop
        
        # Deploy to Railway - ensure environment exists first, then deploy
        echo -e "${BLUE}🚀 Deploying to Railway...${NC}"
        
        # Step 1: Always get PRODUCTION project token FIRST
        # This is the primary token needed for production deployments
        echo ""
        PRODUCTION_TOKEN_VAR="RAILWAY_PROJECT_TOKEN_PRODUCTION"
        PRODUCTION_TOKEN="$(mtx_normalize_railway_token "${!PRODUCTION_TOKEN_VAR:-}")"
        
        if [ -z "$PRODUCTION_TOKEN" ]; then
            echo ""
            echo -e "${YELLOW}📝 PRODUCTION Project Token Required${NC}"
            echo "This token will be used for production deployments."
            echo "Project tokens are scoped to specific environments."
            echo ""
            echo -e "${BLUE}🔗 Open this link to create a PRODUCTION project token:${NC}"
            echo "   https://railway.app/project/$PROJECT_ID/settings/tokens"
            echo ""
            echo -e "${CYAN}Important: When creating the token, make sure to scope it to the PRODUCTION environment only.${NC}"
            echo -e "${CYAN}After creating the PRODUCTION token, paste it below:${NC}"
            echo -e "${CYAN}   Note: Input will not be shown for security${NC}"
            read -sp "PRODUCTION Project Token: " PRODUCTION_TOKEN
            echo ""
            echo ""
            PRODUCTION_TOKEN="$(mtx_normalize_railway_token "$PRODUCTION_TOKEN")"
            
            if [ -z "$PRODUCTION_TOKEN" ]; then
                echo -e "${RED}❌ No token provided. Deployment cancelled.${NC}"
                exit 1
            fi
            
            set_prepare_key "$PRODUCTION_TOKEN_VAR" "$PRODUCTION_TOKEN"
            echo -e "${GREEN}✅ Saved PRODUCTION token to ${MTX_PREPARE_FILE##*/} as $PRODUCTION_TOKEN_VAR${NC}"
            echo ""
        else
            echo -e "${GREEN}✅ Found PRODUCTION project token from environment variable${NC}"
            echo ""
        fi
        
        # Step 2: Always check if staging environment should be created
        # This happens regardless of which environment we're deploying to
        STAGING_TOKEN_VAR="RAILWAY_PROJECT_TOKEN_STAGING"
        STAGING_TOKEN="$(mtx_normalize_railway_token "${!STAGING_TOKEN_VAR:-}")"
        
        # Check if staging environment exists using production token (we can check with any valid token)
        echo -e "${BLUE}ℹ️  Checking if STAGING environment exists...${NC}"
        STAGING_EXISTS=false
        # Use account token for environment checks (can see all environments)
        # Fall back to staging token if account token not available
        ENV_CHECK_TOKEN="${RAILWAY_ACCOUNT_TOKEN:-$STAGING_TOKEN}"
        if [ -n "$ENV_CHECK_TOKEN" ] && check_environment_exists "$ENV_CHECK_TOKEN" "$PROJECT_ID" "staging"; then
            STAGING_EXISTS=true
            echo -e "${GREEN}✅ STAGING environment already exists${NC}"
            echo ""
        elif [ -n "$STAGING_TOKEN" ]; then
            # If we have a staging token, assume environment exists (token wouldn't work without it)
            STAGING_EXISTS=true
            echo -e "${GREEN}✅ STAGING token exists - assuming environment is configured${NC}"
            echo ""
        else
            echo -e "${YELLOW}⚠️  STAGING environment not found (or no token to check)${NC}"
            echo ""
        fi
        
        # If staging doesn't exist or we don't have a staging token, prompt to set it up
        if [ "$STAGING_EXISTS" = "false" ] || [ -z "$STAGING_TOKEN" ]; then
            echo ""
            echo -e "${YELLOW}📝 STAGING Environment Setup${NC}"
            echo ""
            if [ "$STAGING_EXISTS" = "false" ]; then
                echo -e "${CYAN}The STAGING environment does not exist yet.${NC}"
            fi
            if [ -z "$STAGING_TOKEN" ]; then
                echo -e "${CYAN}You don't have a STAGING project token configured.${NC}"
            fi
            echo ""
            echo -e "${CYAN}Do you want to create and configure the STAGING environment?${NC}"
            read -p "Set up staging environment? (y/n, default: y): " CREATE_STAGING
            CREATE_STAGING="${CREATE_STAGING:-y}"
            
            if [[ "$CREATE_STAGING" =~ ^[Yy]$ ]]; then
                # FIRST: Create staging environment if it doesn't exist
                if [ "$STAGING_EXISTS" = "false" ]; then
                    echo ""
                    echo -e "${YELLOW}📝 Please create the STAGING environment manually:${NC}"
                    echo ""
                    echo -e "${BLUE}🔗 Open this link to create the STAGING environment:${NC}"
                    echo "   https://railway.com/project/$PROJECT_ID/settings/environments"
                    echo ""
                    echo -e "${CYAN}Steps to create STAGING environment:${NC}"
                    echo "  1. Click 'New Environment' or 'Add Environment'"
                    echo "  2. Name it 'staging' (lowercase, exactly as shown)"
                    echo "  3. Save the environment"
                    echo ""
                    echo -e "${CYAN}After creating the STAGING environment, press Enter to continue...${NC}"
                    read -p "Press Enter when ready: " WAIT_FOR_STAGING
                    echo ""
                    
                    # Verify staging environment was created (use account token for full visibility)
                    echo -e "${BLUE}ℹ️  Verifying STAGING environment exists...${NC}"
                    ENV_CHECK_TOKEN="${RAILWAY_ACCOUNT_TOKEN:-$STAGING_TOKEN}"
                    if [ -n "$ENV_CHECK_TOKEN" ] && check_environment_exists "$ENV_CHECK_TOKEN" "$PROJECT_ID" "staging"; then
                        echo -e "${GREEN}✅ STAGING environment found!${NC}"
                        echo ""
                        STAGING_EXISTS=true
                    else
                        echo -e "${YELLOW}⚠️  Could not verify STAGING environment${NC}"
                        echo -e "${YELLOW}   Continuing - the staging token will validate during deployment${NC}"
                        echo ""
                        # Continue anyway - deployment will fail if env doesn't exist
                    fi
                fi
                
                # THEN: Get STAGING token if we don't have it (after environment is created)
                if [ -z "$STAGING_TOKEN" ]; then
                    echo ""
                    echo -e "${YELLOW}📝 STAGING Project Token Required${NC}"
                    echo "Now that the STAGING environment exists, you need a project token scoped to it."
                    echo "Project tokens are scoped to specific environments."
                    echo ""
                    echo -e "${BLUE}🔗 Open this link to create a STAGING project token:${NC}"
                    echo "   https://railway.app/project/$PROJECT_ID/settings/tokens"
                    echo ""
                    echo -e "${CYAN}Important: When creating the token, make sure to scope it to the STAGING environment ONLY.${NC}"
                    echo -e "${CYAN}   This should be a separate token from your PRODUCTION token.${NC}"
                    echo -e "${CYAN}   Create a new token and select 'staging' as the environment scope.${NC}"
                    echo -e "${CYAN}After creating the STAGING token, paste it below:${NC}"
                    echo -e "${CYAN}   Note: Input will not be shown for security${NC}"
                    read -sp "STAGING Project Token: " STAGING_TOKEN
                    echo ""
                    echo ""
                    STAGING_TOKEN="$(mtx_normalize_railway_token "$STAGING_TOKEN")"
                    
                    if [ -z "$STAGING_TOKEN" ]; then
                        echo -e "${RED}❌ No token provided. Staging setup incomplete.${NC}"
                        echo -e "${YELLOW}   You can add the token later by setting RAILWAY_PROJECT_TOKEN_STAGING${NC}"
                        echo -e "${YELLOW}   Continuing with $ENVIRONMENT deployment only...${NC}"
                        echo ""
                    else
                        set_prepare_key "$STAGING_TOKEN_VAR" "$STAGING_TOKEN"
                        echo -e "${GREEN}✅ Saved STAGING token to ${MTX_PREPARE_FILE##*/} as $STAGING_TOKEN_VAR${NC}"
                        echo ""
                    fi
                fi
            else
                echo -e "${YELLOW}⚠️  Skipping staging environment setup${NC}"
                echo -e "${CYAN}   Continuing with $ENVIRONMENT deployment only...${NC}"
                echo ""
            fi
        else
            echo -e "${GREEN}✅ STAGING environment and token are already configured${NC}"
            echo ""
        fi
        
        # Step 2b: Set the appropriate token for the current deployment
        if [ "$ENVIRONMENT" = "staging" ]; then
            if [ -z "$STAGING_TOKEN" ]; then
                echo -e "${RED}❌ STAGING token required for staging deployment but not found${NC}"
                echo -e "${YELLOW}   Please set up staging environment first${NC}"
                exit 1
            fi
            PROJECT_TOKEN="$(mtx_normalize_railway_token "$STAGING_TOKEN")"
        else
            # For production, use production token
            PROJECT_TOKEN="$(mtx_normalize_railway_token "$PRODUCTION_TOKEN")"
        fi
        
        # Step 3: Check if environment exists using the environment-specific project token
        # (This step happens after we have the appropriate token for the environment)
        # Note: For staging, we already handled environment creation in Step 2, so skip this entire check
        if [ "$ENVIRONMENT" != "staging" ]; then
            # Only check for non-staging environments (production, etc.)
            echo -e "${BLUE}ℹ️  Checking if $ENVIRONMENT environment exists...${NC}"
            # Use account token for environment checks (has full visibility)
            ENV_CHECK_TOKEN="${RAILWAY_ACCOUNT_TOKEN:-$PROJECT_TOKEN}"
            if ! check_environment_exists "$ENV_CHECK_TOKEN" "$PROJECT_ID" "$ENVIRONMENT"; then
                echo -e "${YELLOW}⚠️  $ENVIRONMENT environment not found${NC}"
                echo ""
                echo -e "${YELLOW}📝 Please create the PRODUCTION environment manually:${NC}"
                echo ""
                echo -e "${BLUE}🔗 Open this link to create it:${NC}"
                echo "   https://railway.com/project/$PROJECT_ID/settings/environments"
                echo ""
                echo -e "${CYAN}After creating the $ENVIRONMENT environment, press Enter to continue...${NC}"
                read -p "Press Enter when ready: " WAIT_FOR_ENV
                echo ""
                
                # Verify environment was created (use account token for full visibility)
                echo -e "${BLUE}ℹ️  Verifying $ENVIRONMENT environment exists...${NC}"
                ENV_CHECK_TOKEN="${RAILWAY_ACCOUNT_TOKEN:-$PROJECT_TOKEN}"
                if check_environment_exists "$ENV_CHECK_TOKEN" "$PROJECT_ID" "$ENVIRONMENT"; then
                    echo -e "${GREEN}✅ $ENVIRONMENT environment found!${NC}"
                    echo ""
                else
                    echo -e "${YELLOW}⚠️  Could not verify $ENVIRONMENT environment${NC}"
                    echo -e "${YELLOW}   Continuing - deployment will validate during execution${NC}"
                    echo ""
                fi
            else
                echo -e "${GREEN}✅ $ENVIRONMENT environment exists${NC}"
                echo ""
            fi
        else
            # For staging, we already handled everything in Step 2, so just confirm we're ready
            echo -e "${GREEN}✅ Proceeding with STAGING deployment (environment setup completed in previous step)${NC}"
            echo ""
        fi

        # Step 3b: enforce shared DB policy and wire DATABASE_URL onto the deploy target service.
        if ! ensure_central_database_for_env "$PROJECT_TOKEN" "$PROJECT_ID" "$ENVIRONMENT" "$SERVICE_ID" "$RAILWAY_TOKEN_VALUE"; then
            echo -e "${RED}❌ Central database wiring failed; aborting deployment.${NC}"
            exit 1
        fi

        # mtx deploy asadmin / child orgs with master trust: auth env on the unified app service (admin + payloads).
        # Set these *before* the first `railway up` so the initial release runs with the correct env. Doing this
        # after the code deploy used to require a second `railway redeploy` (extra Railway run / cost) for the
        # same image just to pick up variables set with --skip-deploys.
        if [ -n "${RUN_AS_MASTER:-}" ] || [ -n "${MASTER_JWT_SECRET:-}" ] || [ -n "${MASTER_AUTH_ISSUER:-}" ] || [ -n "${MASTER_CORS_ORIGINS:-}" ] || [ -n "${MASTER_AUTH_PUBLIC_URL:-}" ] || [ -n "${VITE_MASTER_AUTH_URL:-}" ]; then
            echo -e "${BLUE}🔐 Setting master auth variables on $APP_SERVICE_NAME_FOR_ENV (before first deploy)...${NC}"
            export RAILWAY_TOKEN="$PROJECT_TOKEN"
            unset RAILWAY_API_TOKEN
            (cd "$PROJECT_ROOT" && mkdir -p .railway && echo "$PROJECT_ID" > .railway/project && echo "$SERVICE_ID" > .railway/service && echo "$ENVIRONMENT" > .railway/environment)
            # Force CLI context to the exact project/service/environment before setting vars.
            (cd "$PROJECT_ROOT" && railway link --project "$PROJECT_ID" --service "$SERVICE_ID" --environment "$ENVIRONMENT" >/dev/null 2>&1) || true
            railway_set_var() {
                local kv="$1"
                # Batching: --skip-deploys avoids one deploy per variable; the single `deploy_to_railway` below
                # is the one deploy that applies all of them. (Without --skip-deploys, the CLI can roll the
                # service many times and amplify transient DNS flakiness.)
                railway variable set "$kv" --service "$SERVICE_ID" --environment "$ENVIRONMENT" --skip-deploys >/dev/null 2>&1 \
                  || railway variable set "$kv" --service "$SERVICE_ID" --environment "$ENVIRONMENT" >/dev/null 2>&1 \
                  || railway variables set "$kv" >/dev/null 2>&1
            }
            if [ "${MTX_ASADMIN:-}" = "1" ] && [ -n "${RUN_AS_MASTER:-}" ]; then
                RUN_AS_MASTER_VAL="true"
                (railway_set_var "RUN_AS_MASTER=$RUN_AS_MASTER_VAL" && echo -e "${GREEN}✅ RUN_AS_MASTER=$RUN_AS_MASTER_VAL on $APP_SERVICE_NAME_FOR_ENV${NC}") || echo -e "${YELLOW}⚠️  Could not set RUN_AS_MASTER via CLI${NC}"
            else
                # Not an asadmin deploy → actively remove RUN_AS_MASTER from the Railway service
                # so a previously-poisoned tenant self-heals on its next plain `mtx deploy`.
                # Idempotent (harmless if the var isn't set).
                #
                # CLI form (Railway v3.x, confirmed 2026-04-22):
                #   railway variable delete --service <s> --environment <e> <KEY>
                # 'variable delete' does NOT accept --yes or --skip-deploys. On older CLIs the
                # plural form 'variables delete' existed — kept as a fallback. Any successful path
                # prints a success line so the deploy log shows the scrub happened.
                if railway variable delete RUN_AS_MASTER --service "$APP_SERVICE_NAME_FOR_ENV" --environment "$ENVIRONMENT" >/dev/null 2>&1 \
                  || railway variable delete RUN_AS_MASTER --service "$SERVICE_ID" --environment "$ENVIRONMENT" >/dev/null 2>&1 \
                  || railway variables delete RUN_AS_MASTER --service "$SERVICE_ID" --environment "$ENVIRONMENT" >/dev/null 2>&1; then
                    echo -e "${YELLOW}🧹 Scrubbed stale RUN_AS_MASTER from $APP_SERVICE_NAME_FOR_ENV (plain 'mtx deploy' does not assert master).${NC}"
                fi
            fi
            # Master admin addon reads Railway env vars at runtime to list services/logs/apps.
            # Persist project-scoped token + project id on the deployed service.
            [ -n "${PROJECT_TOKEN:-}" ] && (railway_set_var "RAILWAY_PROJECT_TOKEN=$PROJECT_TOKEN" && echo -e "${GREEN}✅ RAILWAY_PROJECT_TOKEN set on $APP_SERVICE_NAME_FOR_ENV${NC}") || echo -e "${YELLOW}⚠️  Could not set RAILWAY_PROJECT_TOKEN via CLI${NC}"
            [ -n "${PROJECT_TOKEN:-}" ] && (railway_set_var "RAILWAY_TOKEN=$PROJECT_TOKEN" && echo -e "${GREEN}✅ RAILWAY_TOKEN set on $APP_SERVICE_NAME_FOR_ENV${NC}") || echo -e "${YELLOW}⚠️  Could not set RAILWAY_TOKEN via CLI${NC}"
            [ -n "${PROJECT_ID:-}" ] && (railway_set_var "RAILWAY_PROJECT_ID=$PROJECT_ID" && echo -e "${GREEN}✅ RAILWAY_PROJECT_ID set on $APP_SERVICE_NAME_FOR_ENV${NC}") || echo -e "${YELLOW}⚠️  Could not set RAILWAY_PROJECT_ID via CLI${NC}"
            [ -n "${MASTER_JWT_SECRET:-}" ] && (railway_set_var "MASTER_JWT_SECRET=$MASTER_JWT_SECRET" && echo -e "${GREEN}✅ MASTER_JWT_SECRET set on $APP_SERVICE_NAME_FOR_ENV${NC}") || echo -e "${YELLOW}⚠️  Could not set MASTER_JWT_SECRET via CLI${NC}"
            # JWT_SECRET policy under the asmaster architecture (rule-of-law §1 2026-04-21):
            #   • Master (RUN_AS_MASTER=true): admin lane and master-hosted apps both use master-issued
            #     tokens, so JWT_SECRET is mirrored from MASTER_JWT_SECRET. verifyMasterAuthToken on the
            #     admin mount also uses MASTER_JWT_SECRET; the mirror just keeps any legacy code path
            #     using getAuthService() aligned.
            #   • Tenant (no RUN_AS_MASTER, but MASTER_JWT_SECRET set via workspace overlay): tenant
            #     app payloads sign/verify with a tenant-local JWT_SECRET that is INTENTIONALLY distinct
            #     from MASTER_JWT_SECRET, so a compromised tenant cannot forge master-valid admin tokens
            #     and vice versa. If JWT_SECRET is missing we generate a random one here, persist it to
            #     PROJECT_ROOT/.env (so future deploys reuse it — rotating it on every deploy would
            #     invalidate every active tenant-app session), and set it on the Railway service.
            if [ -n "${MASTER_JWT_SECRET:-}" ] && [ -z "${JWT_SECRET:-}" ]; then
                if [ -n "${RUN_AS_MASTER:-}" ]; then
                    (railway_set_var "JWT_SECRET=$MASTER_JWT_SECRET" && echo -e "${GREEN}✅ JWT_SECRET mirrored from MASTER_JWT_SECRET on $APP_SERVICE_NAME_FOR_ENV${NC}") || echo -e "${YELLOW}⚠️  Could not set JWT_SECRET via CLI${NC}"
                    export JWT_SECRET="$MASTER_JWT_SECRET"
                else
                    NEW_JWT_SECRET=""
                    if command -v openssl >/dev/null 2>&1; then
                        NEW_JWT_SECRET="$(openssl rand -base64 48 | tr -d '\n\r')"
                    elif [ -r /dev/urandom ]; then
                        NEW_JWT_SECRET="$(tr -dc 'A-Za-z0-9' </dev/urandom 2>/dev/null | head -c 64)"
                    fi
                    if [ -n "$NEW_JWT_SECRET" ]; then
                        (railway_set_var "JWT_SECRET=$NEW_JWT_SECRET" && echo -e "${GREEN}✅ Generated tenant JWT_SECRET on $APP_SERVICE_NAME_FOR_ENV${NC}") || echo -e "${YELLOW}⚠️  Could not set JWT_SECRET via CLI${NC}"
                        # Persist to PROJECT_ROOT/.env only when no JWT_SECRET= line is already present
                        # (treat any existing line — even empty — as authoritative to avoid fighting an operator edit).
                        if [ -f "$PROJECT_ROOT/.env" ]; then
                            if ! grep -qE '^[[:space:]]*JWT_SECRET=' "$PROJECT_ROOT/.env" 2>/dev/null; then
                                echo "JWT_SECRET=$NEW_JWT_SECRET" >> "$PROJECT_ROOT/.env"
                                echo -e "${GREEN}✅ Persisted tenant JWT_SECRET to $PROJECT_ROOT/.env${NC}"
                            fi
                        else
                            echo "JWT_SECRET=$NEW_JWT_SECRET" >> "$PROJECT_ROOT/.env"
                            chmod 600 "$PROJECT_ROOT/.env" 2>/dev/null || true
                            echo -e "${GREEN}✅ Persisted tenant JWT_SECRET to $PROJECT_ROOT/.env${NC}"
                        fi
                        export JWT_SECRET="$NEW_JWT_SECRET"
                    else
                        echo -e "${YELLOW}⚠️  Could not generate tenant JWT_SECRET (install openssl or ensure /dev/urandom is readable).${NC}"
                    fi
                fi
            fi
            [ -n "${MASTER_AUTH_ISSUER:-}" ] && railway_set_var "MASTER_AUTH_ISSUER=$MASTER_AUTH_ISSUER" || true
            [ -n "${MASTER_CORS_ORIGINS:-}" ] && railway_set_var "MASTER_CORS_ORIGINS=$MASTER_CORS_ORIGINS" || true
            [ -n "${MASTER_AUTH_PUBLIC_URL:-}" ] && railway_set_var "MASTER_AUTH_PUBLIC_URL=$MASTER_AUTH_PUBLIC_URL" || true
            [ -n "${VITE_MASTER_AUTH_URL:-}" ] && railway_set_var "VITE_MASTER_AUTH_URL=$VITE_MASTER_AUTH_URL" || true
        fi
        
        # Step 4: Deploy using Railway CLI with environment-specific project token
        echo -e "${BLUE}🚀 Deploying to Railway ($ENVIRONMENT environment)...${NC}"
        export RAILWAY_SERVICE="$SERVICE_ID"
        export RAILWAY_PROJECT="$PROJECT_ID"
        export RAILWAY_TOKEN="$PROJECT_TOKEN"
        unset RAILWAY_API_TOKEN  # Clear account token so project token takes precedence

        mtx_railway_swap_server_config_for_upload "$PROJECT_ROOT"
        mtx_railway_restore_deploy_server_json_cleanup() {
            mtx_railway_restore_server_config_after_upload "$PROJECT_ROOT"
        }
        trap 'mtx_deploy_spinner_stop; mtx_railway_restore_deploy_server_json_cleanup' EXIT
        
        # Status line while Railway CLI uploads (no spinner during read below)
        mtx_deploy_spinner_start "railway-up" "$APP_NAME"
        
        # Run Railway CLI and capture output - retry with new token if validation fails
        RAILWAY_DEPLOY_OUTPUT=""  # Initialize global output variable
        DEPLOY_SUCCESS=false
        MAX_TOKEN_RETRIES=2
        TOKEN_RETRY_COUNT=0
        
        while [ "$DEPLOY_SUCCESS" = "false" ] && [ $TOKEN_RETRY_COUNT -lt $MAX_TOKEN_RETRIES ]; do
            if deploy_to_railway "$PROJECT_TOKEN" "$PROJECT_ID" "$SERVICE_ID" "$ENVIRONMENT"; then
                DEPLOY_SUCCESS=true
                echo -e "${GREEN}✅ Deployment successful!${NC}"
            else
                # Check if it was a token error (wrong project, expired, or Unauthorized)
                if echo "$RAILWAY_DEPLOY_OUTPUT" | grep -qiE "Unauthorized|Invalid RAILWAY_TOKEN|invalid.*token|token.*invalid|valid and has access|Login state is corrupt|failed to parse header value"; then
                    echo ""
                    if echo "$RAILWAY_DEPLOY_OUTPUT" | grep -qiE "Login state is corrupt|failed to parse header value"; then
                        echo -e "${RED}❌ Railway CLI rejected the token as an HTTP header (often newline, spaces, or quotes in the prepare file or .env).${NC}"
                    else
                        echo -e "${RED}❌ Token validation failed - the ${ENVIRONMENT^^} token is invalid, for a different project, or expired${NC}"
                    fi
                    echo ""
                    
                    # Determine which token variable to update
                    if [ "$ENVIRONMENT" = "staging" ]; then
                        TOKEN_VAR="RAILWAY_PROJECT_TOKEN_STAGING"
                    else
                        TOKEN_VAR="RAILWAY_PROJECT_TOKEN_PRODUCTION"
                    fi
                    
                    # Clear stale token from workspace prepare and legacy org .env
                    clear_prepare_key "$TOKEN_VAR" "true"
                    clear_env_var_in_file "$TOKEN_VAR" "true"
                    echo -e "${YELLOW}🗑️  Cleared stale $TOKEN_VAR from ${MTX_PREPARE_FILE##*/} and/or .env if present${NC}"
                    
                    mtx_deploy_spinner_stop
                    # Prompt for new token
                    echo -e "${YELLOW}📝 Please provide a valid ${ENVIRONMENT^^} project token:${NC}"
                    echo -e "${BLUE}🔗 Get it from: https://railway.app/project/$PROJECT_ID/settings/tokens${NC}"
                    echo -e "${CYAN}   Note: Input will not be shown for security${NC}"
                    read -sp "${ENVIRONMENT^^} Project Token: " NEW_TOKEN
                    echo ""
                    NEW_TOKEN="$(mtx_normalize_railway_token "$NEW_TOKEN")"
                    
                    if [ -z "$NEW_TOKEN" ]; then
                        echo -e "${RED}❌ No token provided. Deployment cancelled.${NC}"
                        exit 1
                    fi
                    
                    set_prepare_key "$TOKEN_VAR" "$NEW_TOKEN"
                    echo -e "${GREEN}✅ Saved new $TOKEN_VAR to ${MTX_PREPARE_FILE##*/}${NC}"
                    
                    # Update token for retry
                    PROJECT_TOKEN="$NEW_TOKEN"
                    export RAILWAY_TOKEN="$PROJECT_TOKEN"
                    TOKEN_RETRY_COUNT=$((TOKEN_RETRY_COUNT + 1))
                    echo ""
                    echo -e "${CYAN}Retrying deployment with new token...${NC}"
                    mtx_deploy_spinner_start "railway-up" "$APP_NAME"
                elif echo "$RAILWAY_DEPLOY_OUTPUT" | grep -qiE "404|Failed to upload code"; then
                    # Service/environment ID invalid – invalidate so setup can re-discover (same as token invalidation)
                    clear_env_var_in_file "RAILWAY_APP_SERVICE_ID"
                    echo -e "${RED}❌ App deployment failed (service or environment invalid)${NC}"
                    echo ""
                    echo -e "${CYAN}   Re-run: ./scripts/setup.sh --setup-deployment to re-discover services.${NC}"
                    exit 2
                else
                    # Non-token error, don't retry
                    echo -e "${RED}❌ Deployment failed${NC}"
                    echo ""
                    if echo "$RAILWAY_DEPLOY_OUTPUT" | grep -qiE "Login state is corrupt|failed to parse header value"; then
                        echo -e "${YELLOW}💡 The Railway CLI maps bad HTTP headers to \"Login state is corrupt\". Usually RAILWAY_PROJECT_TOKEN_* in the workspace prepare file has a trailing newline, spaces, or quotes — use a single-line unquoted token.${NC}"
                    else
                        echo -e "${YELLOW}💡 Tip: Make sure the token is a project token for the $ENVIRONMENT environment${NC}"
                        echo "   Get it from: https://railway.app/project/$PROJECT_ID/settings/tokens"
                    fi
                    exit 1
                fi
            fi
        done
        
        if [ "$DEPLOY_SUCCESS" = "false" ]; then
            echo -e "${RED}❌ App deployment failed after $MAX_TOKEN_RETRIES token attempts${NC}"
            exit 1
        fi
        
        mtx_deploy_spinner_stop
        mtx_railway_restore_deploy_server_json_cleanup
        trap 'mtx_deploy_spinner_stop' EXIT

        # Drop path-vendored ./payloads/<slug>/ trees from the org host after upload; next mtx build / deploy compile re-vendors them.
        # Skip when MTX_SKIP_BUILD=1 so a deploy without a compile in this run can still upload a payloads/ tree from a prior build.
        if [ "${MTX_SKIP_BUILD:-}" != "1" ] && [ -f "$MTX_ROOT/lib/cleanup-path-vendored-payloads-after-deploy.sh" ]; then
          bash "$MTX_ROOT/lib/cleanup-path-vendored-payloads-after-deploy.sh" "$PROJECT_ROOT" || true
        fi
        
        # Ensure app service has a Railway-provided public domain (*.railway.app). Terraform provider has no domain resource; use CLI.
        echo -e "${BLUE}🔗 Ensuring public domain for app service...${NC}"
        # Prefer env project token for deploy/domain ops; fallback to account token.
        export RAILWAY_TOKEN="${PROJECT_TOKEN:-${RAILWAY_ACCOUNT_TOKEN:-}}"
        unset RAILWAY_API_TOKEN
        if type ensure_railway_domain &>/dev/null; then
            ensure_railway_domain "$PROJECT_ROOT" "$PROJECT_ID" "$SERVICE_ID" "$ENVIRONMENT" "app" || true
        else
            (cd "$PROJECT_ROOT" && mkdir -p .railway && echo "$PROJECT_ID" > .railway/project && echo "$SERVICE_ID" > .railway/service && echo "$ENVIRONMENT" > .railway/environment && railway domain 2>/dev/null) || true
        fi

        echo ""
        echo -e "${GREEN}✅ Deployment complete!${NC}"
        echo "Your application should be live on Railway shortly."
    fi
fi

echo ""
echo -e "${GREEN}✅ All done!${NC}"
