#!/usr/bin/env bash
# Ensure Railway public domains for app and backend, then print deploy URLs.
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

# Environment: $1 or prompt
ENVIRONMENT="${1:-}"
case "$ENVIRONMENT" in
  staging|production) ;;
  *)
    echo "Deploy URLs for:"
    echo "  1) staging"
    echo "  2) production"
    read -rp "Choice (1 or 2) [1]: " choice
    choice="${choice:-1}"
    case "$choice" in
      1|s|staging)   ENVIRONMENT=staging ;;
      2|p|production) ENVIRONMENT=production ;;
      *) echo "Invalid choice." >&2; exit 1 ;;
    esac
    ;;
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

# Project token for this environment
if [ "$ENVIRONMENT" = "staging" ]; then
  RAILWAY_TOKEN="${RAILWAY_PROJECT_TOKEN_STAGING:-$RAILWAY_TOKEN}"
else
  RAILWAY_TOKEN="${RAILWAY_PROJECT_TOKEN_PRODUCTION:-$RAILWAY_TOKEN}"
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

echo -e "${CYAN}🔗 Ensure deploy URLs ($ENVIRONMENT)${NC}"
echo ""

# Ensure app domain
if [ -n "$SERVICE_ID" ] && [ "$SERVICE_ID" != "null" ]; then
  echo -e "${BLUE}  App service...${NC}"
  if type ensure_railway_domain &>/dev/null; then
    ensure_railway_domain "$PROJECT_ROOT" "$PROJECT_ID" "$SERVICE_ID" "$ENVIRONMENT" "app" || true
  else
    (cd "$PROJECT_ROOT" && mkdir -p .railway && echo "$PROJECT_ID" > .railway/project && echo "$SERVICE_ID" > .railway/service && echo "$ENVIRONMENT" > .railway/environment && railway domain --service "$SERVICE_ID" --environment "$ENVIRONMENT" 2>/dev/null) || true
  fi
fi

# Ensure backend domain
if [ -n "$BACKEND_SERVICE_ID" ] && [ "$BACKEND_SERVICE_ID" != "null" ]; then
  echo -e "${BLUE}  Backend service...${NC}"
  if type ensure_railway_domain &>/dev/null; then
    ensure_railway_domain "$PROJECT_ROOT" "$PROJECT_ID" "$BACKEND_SERVICE_ID" "$ENVIRONMENT" "backend" || true
  else
    (cd "$PROJECT_ROOT" && mkdir -p .railway && echo "$PROJECT_ID" > .railway/project && echo "$BACKEND_SERVICE_ID" > .railway/service && echo "$ENVIRONMENT" > .railway/environment && railway domain --service "$BACKEND_SERVICE_ID" --environment "$ENVIRONMENT" 2>/dev/null) || true
  fi
fi

# Print URLs (link to app, get domain; link to backend, get domain)
echo ""
echo -e "${GREEN}Deploy URLs ($ENVIRONMENT):${NC}"
print_service_url() {
  local name="$1"
  local sid="$2"
  [ -z "$sid" ] || [ "$sid" = "null" ] && return
  local out
  out=$(cd "$PROJECT_ROOT" && mkdir -p .railway && echo "$PROJECT_ID" > .railway/project && echo "$sid" > .railway/service && echo "$ENVIRONMENT" > .railway/environment && railway domain --service "$sid" --environment "$ENVIRONMENT" --json 2>/dev/null) || \
  out=$(cd "$PROJECT_ROOT" && railway domain --service "$sid" --environment "$ENVIRONMENT" 2>/dev/null) || true
  if [ -n "$out" ]; then
    local url
    url=$(echo "$out" | jq -r '.domain // . // empty' 2>/dev/null)
    [ -z "$url" ] && url="$out"
    url=$(echo "$url" | tr -d '\n' | sed 's|^https\?://||')
    [ -n "$url" ] && echo "  $name: https://$url"
  fi
}
print_service_url "App"     "$SERVICE_ID"
print_service_url "Backend" "$BACKEND_SERVICE_ID"
echo ""
