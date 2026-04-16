#!/usr/bin/env bash
# Ensure Railway public domains for app and backend, then print deploy URLs.
# Standalone: run via "mtx deploy urls" or "mtx deploy urls [staging|production]" anytime;
# also invoked automatically at the end of "mtx deploy".
desc="Ensure deploy URLs (Railway domains) and print app/backend URLs for an environment"
nobanner=1
set -e

# Resolve project root (same logic as terraform/apply.sh)
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

# MTX repo root (this script lives in MTX/deploy/)
MTX_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$PROJECT_ROOT/.env"
TERRAFORM_DIR="$PROJECT_ROOT/terraform"

if [ ! -d "$TERRAFORM_DIR" ] || [ ! -f "$TERRAFORM_DIR/apply.sh" ]; then
  echo "❌ No terraform dir at $TERRAFORM_DIR. Run deploy first." >&2
  exit 1
fi

# Load .env
if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck source=/dev/null
  source "$ENV_FILE"
  set +a
fi

# Environment: arg only (default staging). Never prompt.
ENVIRONMENT="${1:-${DEFAULT_ENVIRONMENT:-staging}}"
case "$ENVIRONMENT" in
  staging|production) ;;
  *) echo "Invalid environment '$ENVIRONMENT' (expected staging|production)." >&2; exit 1 ;;
esac

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Terraform outputs (run from project's terraform dir)
cd "$TERRAFORM_DIR" || exit 1
if [ "$ENVIRONMENT" = "staging" ]; then
  SERVICE_ID=$(terraform output -raw railway_app_service_id_staging 2>/dev/null || echo "")
  BACKEND_SERVICE_ID=$(terraform output -raw railway_backend_staging_service_id 2>/dev/null || echo "")
else
  SERVICE_ID=$(terraform output -raw railway_app_service_id_production 2>/dev/null || echo "")
  BACKEND_SERVICE_ID=$(terraform output -raw railway_backend_production_service_id 2>/dev/null || echo "")
fi
PROJECT_ID=$(terraform output -raw railway_project_id 2>/dev/null || echo "")
cd "$PROJECT_ROOT" || exit 1

if [ -z "$PROJECT_ID" ] || [ "$PROJECT_ID" = "null" ]; then
  echo -e "${YELLOW}⚠️  No Railway project ID from terraform. Run deploy first.${NC}" >&2
  exit 1
fi

# Prefer account token for domain creation/listing when available; fallback to env project token.
if [ "$ENVIRONMENT" = "staging" ]; then
  RAILWAY_TOKEN="${RAILWAY_ACCOUNT_TOKEN:-${RAILWAY_PROJECT_TOKEN_STAGING:-$RAILWAY_TOKEN}}"
else
  RAILWAY_TOKEN="${RAILWAY_ACCOUNT_TOKEN:-${RAILWAY_PROJECT_TOKEN_PRODUCTION:-$RAILWAY_TOKEN}}"
fi
if [ -z "$RAILWAY_TOKEN" ]; then
  echo -e "${YELLOW}⚠️  No RAILWAY_PROJECT_TOKEN_$ENVIRONMENT (or RAILWAY_TOKEN). Set in .env or run deploy.${NC}" >&2
  exit 1
fi
export RAILWAY_TOKEN
unset RAILWAY_API_TOKEN

# Railway CLI
if ! command -v railway &>/dev/null; then
  echo -e "${BLUE}ℹ️  Installing Railway CLI...${NC}"
  curl -fsSL https://railway.app/install.sh | sh
  export PATH="$HOME/.railway/bin:$PATH"
fi

# Subroutine: ensure Railway domain
# shellcheck source=../terraform/ensure-railway-domain.sh
if [ -f "$MTX_ROOT/terraform/ensure-railway-domain.sh" ]; then
  source "$MTX_ROOT/terraform/ensure-railway-domain.sh"
fi

run_with_timeout() {
  local secs="${1:-15}"
  shift
  timeout "${secs}s" "$@" </dev/null 2>/dev/null
}

# Parse domain from CLI/API output (JSON, plain hostname, or line containing *.up.railway.app)
# Usage: parse_domain [stdin or $1]
parse_domain() {
  local out
  if [ -n "${1:-}" ]; then
    out="$1"
  else
    out=$(cat)
  fi
  local url=""
  [ -z "$out" ] && return
  url=$(echo "$out" | jq -r '.domain // .url // .host // . // empty' 2>/dev/null)
  [ -z "$url" ] && url=$(echo "$out" | tr -d '\n\r' | sed -n 's/.*\([a-zA-Z0-9.-]*\.up\.railway\.app\).*/\1/p')
  [ -z "$url" ] && url=$(echo "$out" | head -1 | tr -d '\n\r')
  url=$(echo "$url" | tr -d '\n\r' | sed 's|^https\?://||' | sed 's|/.*||')
  [ -n "$url" ] && [ "$url" != "null" ] && echo "$url"
}

# Get service domain via Railway GraphQL API (project token)
get_domain_via_api() {
  local project_id="$1"
  local service_id="$2"
  local token="$3"
  local query
  query=$(printf '{"query":"query { project(id: \"%s\") { services { edges { node { id serviceDomains { edges { node { domain } } } } } } } }"}' "$project_id")
  local res
  res=$(curl -s -S -X POST "https://backboard.railway.com/graphql/v2" \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    -d "$query" 2>/dev/null)
  local domain
  domain=$(echo "$res" | jq -r --arg sid "$service_id" '
    .data.project.services.edges[] | select(.node.id == $sid) | .node.serviceDomains.edges[0].node.domain // empty
  ' 2>/dev/null)
  # Alternate schema: domains on node directly
  [ -z "$domain" ] && domain=$(echo "$res" | jq -r --arg sid "$service_id" '
    .data.project.services.edges[] | select(.node.id == $sid) | .node.domains.edges[0].node.domain // empty
  ' 2>/dev/null)
  [ -n "$domain" ] && [ "$domain" != "null" ] && echo "$domain"
}

echo -e "${CYAN}🔗 Ensure deploy URLs ($ENVIRONMENT)${NC}"

# Ensure app domain and capture output for display
APP_DOMAIN=""
if [ -n "$SERVICE_ID" ] && [ "$SERVICE_ID" != "null" ]; then
  echo -e "${BLUE}  App service...${NC}"
  if type ensure_railway_domain &>/dev/null; then
    APP_DOMAIN=$(run_with_timeout "${MTX_URLS_TIMEOUT_SEC:-20}" ensure_railway_domain "$PROJECT_ROOT" "$PROJECT_ID" "$SERVICE_ID" "$ENVIRONMENT" "app" | parse_domain) || true
  else
    APP_DOMAIN=$(cd "$PROJECT_ROOT" && mkdir -p .railway && echo "$PROJECT_ID" > .railway/project && echo "$SERVICE_ID" > .railway/service && echo "$ENVIRONMENT" > .railway/environment && run_with_timeout "${MTX_URLS_TIMEOUT_SEC:-20}" railway domain --service "$SERVICE_ID" | parse_domain) || true
  fi
fi

# Ensure backend domain and capture output for display
BACKEND_DOMAIN=""
if [ -n "$BACKEND_SERVICE_ID" ] && [ "$BACKEND_SERVICE_ID" != "null" ]; then
  echo -e "${BLUE}  Backend service...${NC}"
  if type ensure_railway_domain &>/dev/null; then
    BACKEND_DOMAIN=$(run_with_timeout "${MTX_URLS_TIMEOUT_SEC:-20}" ensure_railway_domain "$PROJECT_ROOT" "$PROJECT_ID" "$BACKEND_SERVICE_ID" "$ENVIRONMENT" "backend" | parse_domain) || true
  else
    BACKEND_DOMAIN=$(cd "$PROJECT_ROOT" && mkdir -p .railway && echo "$PROJECT_ID" > .railway/project && echo "$BACKEND_SERVICE_ID" > .railway/service && echo "$ENVIRONMENT" > .railway/environment && run_with_timeout "${MTX_URLS_TIMEOUT_SEC:-20}" railway domain --service "$BACKEND_SERVICE_ID" | parse_domain) || true
  fi
fi

# If ensure didn't return a domain, try Railway API (same token)
[ -z "$APP_DOMAIN" ] && APP_DOMAIN=$(get_domain_via_api "$PROJECT_ID" "$SERVICE_ID" "$RAILWAY_TOKEN" 2>/dev/null) || true
[ -z "$BACKEND_DOMAIN" ] && BACKEND_DOMAIN=$(get_domain_via_api "$PROJECT_ID" "$BACKEND_SERVICE_ID" "$RAILWAY_TOKEN" 2>/dev/null) || true

# Print URLs only for services that exist.
echo -e "${GREEN}Deploy URLs ($ENVIRONMENT):${NC}"
print_service_url() {
  local name="$1"
  local sid="$2"
  local preferred="$3"
  [ -z "$sid" ] || [ "$sid" = "null" ] && return
  local url="$preferred"
  if [ -z "$url" ]; then
    local out
    (cd "$PROJECT_ROOT" && mkdir -p .railway && echo "$PROJECT_ID" > .railway/project && echo "$sid" > .railway/service && echo "$ENVIRONMENT" > .railway/environment)
    out=$(cd "$PROJECT_ROOT" && run_with_timeout "${MTX_URLS_TIMEOUT_SEC:-20}" railway domain --service "$sid" --json) || \
    out=$(cd "$PROJECT_ROOT" && run_with_timeout "${MTX_URLS_TIMEOUT_SEC:-20}" railway domain --service "$sid") || true
    url=$(parse_domain "$out")
  fi
  url=$(echo "$url" | tr -d '\n\r' | sed 's|^https\?://||' | sed 's|/.*||')
  if [ -n "$url" ] && [ "$url" != "null" ]; then
    echo "  $name: https://$url"
  else
    echo -e "  ${YELLOW}$name: (no Railway domain available)${NC}"
  fi
}
print_service_url "App"     "$SERVICE_ID" "$APP_DOMAIN"
print_service_url "Backend" "$BACKEND_SERVICE_ID" "$BACKEND_DOMAIN"
echo ""
