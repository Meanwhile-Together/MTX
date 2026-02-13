#!/usr/bin/env bash
# MTX terraform apply: run from project root (wrapper sets cwd); use project's terraform dir
desc="Apply Terraform (Railway etc.); deploy app and backend"
set -e

PROJECT_ROOT="$(pwd)"
SCRIPT_DIR="$PROJECT_ROOT/terraform"

# Load .env if it exists (for RAILWAY_ACCOUNT_TOKEN and other tokens)
ENV_FILE="$PROJECT_ROOT/.env"
if [ -f "$ENV_FILE" ]; then
    set -a
    source "$ENV_FILE"
    set +a
fi

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

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m' # No Color

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

# Parse script args: [environment] [--force-backend] or [--force-backend] [environment]
# FORCE_BACKEND can come from env (e.g. setup.sh --force-backend) or from --force-backend flag
ENVIRONMENT="staging"
FORCE_BACKEND="${FORCE_BACKEND:-}"
while [ $# -gt 0 ]; do
    case "$1" in
        --force-backend) FORCE_BACKEND="1"; shift ;;
        *)               ENVIRONMENT="$1"; shift ;;
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

# Get app name and slug (slug used for Railway service name)
APP_NAME=$(jq -r '.app.name' "$PROJECT_ROOT/config/app.json" 2>/dev/null || echo "")
APP_SLUG=$(jq -r '.app.slug // .app.name // "app"' "$PROJECT_ROOT/config/app.json" 2>/dev/null | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/^-*//;s/-*$//')
if [ -z "$APP_NAME" ]; then
    echo "⚠️  app.name not found in config/app.json, using default"
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
    APP_OWNER=$(jq -r '.app.owner // ""' "$PROJECT_ROOT/config/app.json" 2>/dev/null || echo "")
    RAILWAY_TOKEN_VALUE=""
    if [ -n "${RAILWAY_TOKEN:-}" ]; then
        echo -e "${GREEN}✅${NC} RAILWAY_TOKEN found in environment"
        RAILWAY_TOKEN_VALUE="$RAILWAY_TOKEN"
        TF_VARS+=(-var="railway_token=$RAILWAY_TOKEN")
    elif [ -n "${RAILWAY_ACCOUNT_TOKEN:-}" ]; then
        echo -e "${GREEN}✅${NC} RAILWAY_ACCOUNT_TOKEN found in environment"
        RAILWAY_TOKEN_VALUE="$RAILWAY_ACCOUNT_TOKEN"
        TF_VARS+=(-var="railway_token=$RAILWAY_ACCOUNT_TOKEN")
    elif [ -n "${TF_VAR_railway_token:-}" ]; then
        echo -e "${GREEN}✅${NC} TF_VAR_railway_token found"
        RAILWAY_TOKEN_VALUE="$TF_VAR_railway_token"
        TF_VARS+=(-var="railway_token=$TF_VAR_railway_token")
    else
        RAILWAY_TOKEN_URL="https://railway.app/account/tokens"
        echo ""
        echo -e "${YELLOW}🔐 Railway account token needed for this run.${NC}"
        echo -e "${CYAN}   Set RAILWAY_TOKEN or RAILWAY_ACCOUNT_TOKEN in .env (project root) to skip this prompt next time.${NC}"
        echo -e "${BLUE}🔗 Get an account token: ${RAILWAY_TOKEN_URL}${NC}"
        echo -e "${YELLOW}   (input is hidden for security)${NC}"
        while true; do
            read -r -sp "Paste your Railway account token (or Ctrl+C to cancel): " RAILWAY_TOKEN_VALUE
            echo ""
            if [ -n "$RAILWAY_TOKEN_VALUE" ]; then
                TF_VARS+=(-var="railway_token=$RAILWAY_TOKEN_VALUE")
                echo -e "${GREEN}✅ Using provided token.${NC}"
                break
            fi
            echo -e "${YELLOW}   No token entered. Try again or open: ${RAILWAY_TOKEN_URL}${NC}"
        done
    fi

    # Project token for module (fallback); deploy step uses project token for railway up
    if [ "$ENVIRONMENT" = "staging" ] && [ -n "${RAILWAY_PROJECT_TOKEN_STAGING:-}" ]; then
        TF_VARS+=(-var="railway_project_token=$RAILWAY_PROJECT_TOKEN_STAGING")
    elif [ "$ENVIRONMENT" = "production" ] && [ -n "${RAILWAY_PROJECT_TOKEN_PRODUCTION:-}" ]; then
        TF_VARS+=(-var="railway_project_token=$RAILWAY_PROJECT_TOKEN_PRODUCTION")
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
                TF_VARS+=(-var="railway_workspace_id=$RAILWAY_WORKSPACE_ID")
            fi
        fi
        if [ -z "${RAILWAY_WORKSPACE_ID:-}" ] || [ "$RAILWAY_WORKSPACE_ID" = "null" ]; then
            echo -e "${RED}❌ Could not resolve Railway workspace. Set RAILWAY_WORKSPACE_ID in .env or ensure config/app.json app.owner matches a Railway workspace name.${NC}"
            exit 1
        fi
    fi

    # Resolve project from API when not set in env: find existing project by name (app.owner) or leave unset so Terraform creates one
    if [ -z "${RAILWAY_PROJECT_ID_FOR_RUN:-}" ] && [ -n "${RAILWAY_WORKSPACE_ID:-}" ] && [ -n "$RAILWAY_TOKEN_VALUE" ]; then
        PROJECTS_QUERY=$(printf '{"query":"query($wid: String!) { workspace(workspaceId: $wid) { projects(first: 50) { edges { node { id name } } } } }", "variables": {"wid": "%s"}}' "$RAILWAY_WORKSPACE_ID")
        PROJECTS_RESPONSE=$(curl -s -X POST "https://backboard.railway.com/graphql/v2" \
            -H "Authorization: Bearer $RAILWAY_TOKEN_VALUE" \
            -H "Content-Type: application/json" \
            -d "$PROJECTS_QUERY" 2>/dev/null)
        if [ $? -eq 0 ] && [ -n "$PROJECTS_RESPONSE" ]; then
            # Parse .data.workspace.projects or .data.workspace.team.projects (API shape can vary)
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
    
    # Resolve backend and app service IDs from API. Services are named with -staging / -production suffix.
    # Parse supports both edges/node and direct array response shapes.
    discover_railway_services() {
        EXISTING_BACKEND_ID=""
        EXISTING_APP_ID=""
        [ -z "$SERVICES_RESPONSE" ] && return
        # Try edges/node (GraphQL connection style)
        EXISTING_BACKEND_ID=$(echo "$SERVICES_RESPONSE" | jq -r --arg name "$BACKEND_NAME" '.data.project.services.edges[]? | select(.node.name == $name) | .node.id // empty' 2>/dev/null | head -1)
        EXISTING_APP_ID=$(echo "$SERVICES_RESPONSE" | jq -r --arg name "$APP_SERVICE_NAME" '.data.project.services.edges[]? | select(.node.name == $name) | .node.id // empty' 2>/dev/null | head -1)
        # Fallback: direct array (some API versions)
        if [ -z "$EXISTING_BACKEND_ID" ] || [ "$EXISTING_BACKEND_ID" = "null" ]; then
            EXISTING_BACKEND_ID=$(echo "$SERVICES_RESPONSE" | jq -r --arg name "$BACKEND_NAME" '.data.project.services[]? | select(.name == $name) | .id // empty' 2>/dev/null | head -1)
        fi
        if [ -z "$EXISTING_APP_ID" ] || [ "$EXISTING_APP_ID" = "null" ]; then
            EXISTING_APP_ID=$(echo "$SERVICES_RESPONSE" | jq -r --arg name "$APP_SERVICE_NAME" '.data.project.services[]? | select(.name == $name) | .id // empty' 2>/dev/null | head -1)
        fi
    }
    EXISTING_BACKEND_ID=""
    EXISTING_APP_ID=""
    BACKEND_NAME="backend-$ENVIRONMENT"
    APP_SERVICE_NAME="$APP_SLUG-$ENVIRONMENT"
    if [ -n "${RAILWAY_PROJECT_ID_FOR_RUN:-}" ] && [ -n "${RAILWAY_TOKEN_VALUE:-}" ]; then
        SERVICES_QUERY='{"query":"query($projectId: String!) { project(id: $projectId) { services { edges { node { id name } } } } }", "variables": {"projectId": "'"$RAILWAY_PROJECT_ID_FOR_RUN"'"}}'
        SERVICES_RESPONSE=$(curl -s -X POST "https://backboard.railway.com/graphql/v2" \
            -H "Authorization: Bearer $RAILWAY_TOKEN_VALUE" \
            -H "Content-Type: application/json" \
            -d "$SERVICES_QUERY" 2>/dev/null)
        discover_railway_services
    fi
    # Self-heal: if backend was invalidated (404), ignore discovered ID so Terraform creates a new backend on retry
    if [ -f "$PROJECT_ROOT/.railway-backend-invalidated" ]; then
        EXISTING_BACKEND_ID=""
    fi
    if [ -n "$EXISTING_BACKEND_ID" ] && [ "$EXISTING_BACKEND_ID" != "null" ]; then
        echo -e "${GREEN}✅${NC} Backend service already exists: skipping create (use --force-backend to force code redeploy)"
        TF_VARS+=(-var="railway_backend_service_id=$EXISTING_BACKEND_ID")
    else
        echo -e "${CYAN}ℹ️${NC}  Backend service \"$BACKEND_NAME\" not found; Terraform will create it during apply"
    fi

    if [ -n "$EXISTING_APP_ID" ] && [ "$EXISTING_APP_ID" != "null" ]; then
        echo -e "${GREEN}✅${NC} App service \"$APP_SERVICE_NAME\" already exists: skipping create (code will still deploy)"
        TF_VARS+=(-var="railway_service_id=$EXISTING_APP_ID")
    fi
else
    echo -e "${RED}❌ Railway is required. Add \"railway\" to config/deploy.json platform array.${NC}"
    exit 1
fi

echo ""
echo -e "${BLUE}🚀 Running terraform apply...${NC}"
echo ""

# Change to terraform directory
cd "$SCRIPT_DIR"

# Ensure backend and providers are initialized (idempotent; no-op if already inited)
if ! terraform init -reconfigure -input=false; then
    echo ""
    echo -e "${RED}❌ terraform init failed${NC}"
    exit 1
fi

# Remove legacy single "backend" resource from state if present (we now use backend-staging / backend-production).
if terraform state list 2>/dev/null | grep -q 'module.railway_owner\[0\].railway_service.backend\[0\]'; then
    echo -e "${CYAN}ℹ️  Removing legacy backend from state (replaced by backend-staging / backend-production)...${NC}"
    terraform state rm 'module.railway_owner[0].railway_service.backend[0]' 2>/dev/null || true
fi

# When we pass an existing backend ID, Terraform must not manage backend-staging/backend-production (count becomes 0),
# or it will DESTROY the live service. Remove them from state so Terraform does not plan to destroy them.
if [ -n "${EXISTING_BACKEND_ID:-}" ] && [ "$EXISTING_BACKEND_ID" != "null" ]; then
    for res in 'module.railway_owner[0].railway_service.backend_staging[0]' 'module.railway_owner[0].railway_service.backend_production[0]'; do
        if terraform state list 2>/dev/null | grep -qF "$res"; then
            echo -e "${CYAN}ℹ️  Removing $res from state (using existing backend; avoid destroying live service)...${NC}"
            terraform state rm "$res" 2>/dev/null || true
        fi
    done
fi

# When we pass an existing app ID, Terraform must not manage the app service (count becomes 0),
# or it will DESTROY the live service. Remove from state so we reuse it and update outputs only.
if [ -n "${EXISTING_APP_ID:-}" ] && [ "$EXISTING_APP_ID" != "null" ]; then
    if terraform state list 2>/dev/null | grep -qF 'module.railway_app[0].railway_service.app[0]'; then
        echo -e "${CYAN}ℹ️  Removing app service from state (using existing app; avoid destroying live service)...${NC}"
        terraform state rm 'module.railway_app[0].railway_service.app[0]' 2>/dev/null || true
    fi
fi

# Run terraform apply - show output in real-time, capture for retry check
# Using -auto-approve since we're in a script and user has already confirmed via setup.sh
set +e  # Don't exit on error, we'll check exit code
TF_APPLY_LOG="/tmp/tf-apply-$$.log"
terraform apply -auto-approve "${TF_VARS[@]}" 2>&1 | tee "$TF_APPLY_LOG"
TERRAFORM_EXIT=${PIPESTATUS[0]}
set -e  # Re-enable exit on error

# If apply failed with "already exists" (service created outside Terraform), discover and re-apply with existing ID
if [ $TERRAFORM_EXIT -ne 0 ] && grep -q "already exists in this project" "$TF_APPLY_LOG" 2>/dev/null; then
    echo ""
    echo -e "${BLUE}🔧 Service already exists; discovering and re-applying with existing ID...${NC}"
    SERVICES_RESPONSE=$(curl -s -X POST "https://backboard.railway.com/graphql/v2" \
        -H "Authorization: Bearer $RAILWAY_TOKEN_VALUE" \
        -H "Content-Type: application/json" \
        -d "$SERVICES_QUERY" 2>/dev/null)
    discover_railway_services
    if [ -n "$EXISTING_BACKEND_ID" ] && [ "$EXISTING_BACKEND_ID" != "null" ]; then
        for res in 'module.railway_owner[0].railway_service.backend_staging[0]' 'module.railway_owner[0].railway_service.backend_production[0]'; do
            terraform state rm "$res" 2>/dev/null || true
        done
        TF_VARS+=(-var="railway_backend_service_id=$EXISTING_BACKEND_ID")
        echo -e "${GREEN}✅ Using existing backend service: $EXISTING_BACKEND_ID${NC}"
    fi
    if [ -n "$EXISTING_APP_ID" ] && [ "$EXISTING_APP_ID" != "null" ]; then
        terraform state rm 'module.railway_app[0].railway_service.app[0]' 2>/dev/null || true
        TF_VARS+=(-var="railway_service_id=$EXISTING_APP_ID")
        echo -e "${GREEN}✅ Using existing app service: $EXISTING_APP_ID${NC}"
    fi
    echo ""
    terraform apply -auto-approve "${TF_VARS[@]}"
    TERRAFORM_EXIT=$?
fi
# If apply failed due to backend not initialized, run init and retry once (idempotent recovery)
if [ $TERRAFORM_EXIT -ne 0 ] && [ -f "$TF_APPLY_LOG" ] && grep -q "Backend initialization required\|please run \"terraform init\"" "$TF_APPLY_LOG" 2>/dev/null; then
    echo ""
    echo -e "${CYAN}🔄 Backend not initialized; running terraform init and retrying apply...${NC}"
    if terraform init -reconfigure -input=false && terraform apply -auto-approve "${TF_VARS[@]}"; then
        TERRAFORM_EXIT=0
    fi
fi
rm -f "$TF_APPLY_LOG"

if [ $TERRAFORM_EXIT -ne 0 ]; then
    echo ""
    echo -e "${RED}❌ Terraform apply failed${NC}"
    echo -e "${CYAN}Review the error messages above for details.${NC}"
    echo ""
    echo -e "${YELLOW}Common issues:${NC}"
    echo "  - State lock: Another Terraform process may be running"
    echo "  - Missing variables: Check that all required tokens are set"
    echo "  - Invalid configuration: Review Terraform error messages above"
    echo ""
    
    exit 1
fi

# Output was already shown in real-time above, no need to echo again

# If Railway was deployed successfully, automatically deploy code
if [ "$HAS_RAILWAY" = "true" ]; then
    echo ""
    echo -e "${BLUE}🚀 Deploying code to Railway...${NC}"
    echo "=========================================="
    echo ""
    
    # Get Railway service IDs and project ID from Terraform outputs
    SERVICE_ID=$(terraform output -raw railway_service_id 2>/dev/null || echo "")
    BACKEND_SERVICE_ID=$(terraform output -raw railway_backend_service_id 2>/dev/null || echo "")
    # When we passed an existing backend ID, use it if output is empty (e.g. right after state rm)
    if [ -z "$BACKEND_SERVICE_ID" ] || [ "$BACKEND_SERVICE_ID" = "null" ]; then
        [ -n "${EXISTING_BACKEND_ID:-}" ] && [ "$EXISTING_BACKEND_ID" != "null" ] && BACKEND_SERVICE_ID="$EXISTING_BACKEND_ID"
    fi
    PROJECT_ID=$(terraform output -raw railway_project_id 2>/dev/null || echo "")
    
    # Get environment from script argument (staging or production)
    # ENVIRONMENT already set from script args (default staging)
    
    if [ -z "$SERVICE_ID" ] || [ "$SERVICE_ID" = "null" ]; then
        echo -e "${YELLOW}⚠️  Could not get Railway service ID from Terraform outputs${NC}"
        echo "Skipping code deployment"
    else
        echo -e "${GREEN}✅ Found Railway service: $SERVICE_ID${NC}"
        echo -e "${GREEN}✅ Found Railway project: $PROJECT_ID${NC}"
        echo -e "${GREEN}✅ Deploying to environment: $ENVIRONMENT${NC}"
        echo ""
        
        # Navigate to project root
        cd "$PROJECT_ROOT"
        
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
        
        # Link directory to Railway service
        if [ ! -d ".railway" ]; then
            echo -e "${BLUE}🔗 Linking directory to Railway service...${NC}"
            railway link --service "$SERVICE_ID" --project "$PROJECT_ID" 2>/dev/null || {
                # Fallback: create .railway directory manually
                mkdir -p .railway
                echo "$SERVICE_ID" > .railway/service
                echo "$PROJECT_ID" > .railway/project
            }
        else
            # Verify link is correct
            LINKED_SERVICE=$(cat .railway/service 2>/dev/null || echo "")
            if [ "$LINKED_SERVICE" != "$SERVICE_ID" ]; then
                echo -e "${YELLOW}⚠️  Re-linking to correct service...${NC}"
                rm -rf .railway
                railway link --service "$SERVICE_ID" --project "$PROJECT_ID" 2>/dev/null || {
                    mkdir -p .railway
                    echo "$SERVICE_ID" > .railway/service
                    echo "$PROJECT_ID" > .railway/project
                }
            fi
        fi
        echo -e "${GREEN}✅ Linked to Railway service${NC}"
        echo ""
        
        # Ensure dependencies (e.g. Prisma) are installed before build
        if [ ! -f "node_modules/.bin/prisma" ] && [ -f "package.json" ]; then
            echo -e "${BLUE}ℹ️  Prisma/dependencies not found, running npm install...${NC}"
            npm install || { echo -e "${RED}❌ npm install failed${NC}"; exit 1; }
            echo ""
        fi
        
        # Build the project
        echo -e "${BLUE}🔨 Building project...${NC}"
        npm run build:server || {
            echo -e "${RED}❌ Build failed${NC}"
            exit 1
        }
        echo -e "${GREEN}✅ Build complete${NC}"
        echo ""
        
        # Function to handle Railway deployment with service selection and environment
        # Returns: 0 on success, 1 on failure
        # Output is captured in global variable RAILWAY_DEPLOY_OUTPUT
        # Sets NEED_PROJECT_TOKEN_FOR_ENV=1 if project token is needed for environment creation
        deploy_to_railway() {
            local TOKEN="$1"
            local PROJ_ID="$2"
            local SVC_ID="$3"
            local ENV_NAME="$4"  # staging or production
            local VERBOSE="${5:-}"  # non-empty = add --verbose (e.g. for backend to see tarball size)
            
            # Set token for Railway CLI
            export RAILWAY_TOKEN="$TOKEN"
            unset RAILWAY_API_TOKEN
            
            # Global variable to capture output
            RAILWAY_DEPLOY_OUTPUT=""
            
            # Note: Environment creation is handled BEFORE calling this function
            # This function only handles deployment
            # Pass project, service, and environment explicitly so the token doesn't "pick" a different project/env
            local UP_OPTS="--project $PROJ_ID --service $SVC_ID --environment $ENV_NAME"
            [ -n "$VERBOSE" ] && UP_OPTS="$UP_OPTS --verbose"
            # Use tee to both display output in real-time and capture it
            local OUTPUT=$(railway up $UP_OPTS 2>&1 | tee /dev/stderr)
            local EXIT_CODE=${PIPESTATUS[0]}
            
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
                OUTPUT=$(railway up --project "$PROJ_ID" --service "$SELECTED_SERVICE_ID" --environment "$ENV_NAME" 2>&1 | tee /dev/stderr)
                EXIT_CODE=${PIPESTATUS[0]}
                
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
        
        # Deploy to Railway - ensure environment exists first, then deploy
        echo -e "${BLUE}🚀 Deploying to Railway...${NC}"
        
        # Step 1: Always get PRODUCTION project token FIRST
        # This is the primary token needed for production deployments
        echo ""
        PRODUCTION_TOKEN_VAR="RAILWAY_PROJECT_TOKEN_PRODUCTION"
        PRODUCTION_TOKEN="${!PRODUCTION_TOKEN_VAR:-}"
        
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
            
            if [ -z "$PRODUCTION_TOKEN" ]; then
                echo -e "${RED}❌ No token provided. Deployment cancelled.${NC}"
                exit 1
            fi
            
            # Save to .env file
            ENV_FILE="$PROJECT_ROOT/.env"
            if [ -f "$ENV_FILE" ]; then
                # Remove existing entry if present
                if grep -q "^${PRODUCTION_TOKEN_VAR}=" "$ENV_FILE" 2>/dev/null; then
                    if [[ "$OSTYPE" == "darwin"* ]]; then
                        sed -i '' "/^${PRODUCTION_TOKEN_VAR}=/d" "$ENV_FILE"
                    else
                        sed -i "/^${PRODUCTION_TOKEN_VAR}=/d" "$ENV_FILE"
                    fi
                fi
                # Append new entry
                echo "${PRODUCTION_TOKEN_VAR}=${PRODUCTION_TOKEN}" >> "$ENV_FILE"
            else
                echo "${PRODUCTION_TOKEN_VAR}=${PRODUCTION_TOKEN}" > "$ENV_FILE"
            fi
            echo -e "${GREEN}✅ Saved PRODUCTION token to .env as $PRODUCTION_TOKEN_VAR${NC}"
            echo ""
        else
            echo -e "${GREEN}✅ Found PRODUCTION project token from environment variable${NC}"
            echo ""
        fi
        
        # Step 2: Always check if staging environment should be created
        # This happens regardless of which environment we're deploying to
        STAGING_TOKEN_VAR="RAILWAY_PROJECT_TOKEN_STAGING"
        STAGING_TOKEN="${!STAGING_TOKEN_VAR:-}"
        
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
                    
                    if [ -z "$STAGING_TOKEN" ]; then
                        echo -e "${RED}❌ No token provided. Staging setup incomplete.${NC}"
                        echo -e "${YELLOW}   You can add the token later by setting RAILWAY_PROJECT_TOKEN_STAGING${NC}"
                        echo -e "${YELLOW}   Continuing with $ENVIRONMENT deployment only...${NC}"
                        echo ""
                    else
                        # Save to .env file
                        ENV_FILE="$PROJECT_ROOT/.env"
                        if [ -f "$ENV_FILE" ]; then
                            # Remove existing entry if present
                            if grep -q "^${STAGING_TOKEN_VAR}=" "$ENV_FILE" 2>/dev/null; then
                                if [[ "$OSTYPE" == "darwin"* ]]; then
                                    sed -i '' "/^${STAGING_TOKEN_VAR}=/d" "$ENV_FILE"
                                else
                                    sed -i "/^${STAGING_TOKEN_VAR}=/d" "$ENV_FILE"
                                fi
                            fi
                            # Append new entry
                            echo "${STAGING_TOKEN_VAR}=${STAGING_TOKEN}" >> "$ENV_FILE"
                        else
                            echo "${STAGING_TOKEN_VAR}=${STAGING_TOKEN}" > "$ENV_FILE"
                        fi
                        echo -e "${GREEN}✅ Saved STAGING token to .env as $STAGING_TOKEN_VAR${NC}"
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
            PROJECT_TOKEN="$STAGING_TOKEN"
        else
            # For production, use production token
            PROJECT_TOKEN="$PRODUCTION_TOKEN"
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
        
        # Step 4: Deploy using Railway CLI with environment-specific project token
        DEPLOY_INVALIDATED_SERVICE=0
        echo -e "${BLUE}🚀 Deploying to Railway ($ENVIRONMENT environment)...${NC}"
        export RAILWAY_SERVICE="$SERVICE_ID"
        export RAILWAY_PROJECT="$PROJECT_ID"
        export RAILWAY_TOKEN="$PROJECT_TOKEN"
        unset RAILWAY_API_TOKEN  # Clear account token so project token takes precedence
        
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
                # Check if it was a token error
                if echo "$RAILWAY_DEPLOY_OUTPUT" | grep -qiE "Invalid RAILWAY_TOKEN|invalid.*token|token.*invalid"; then
                    echo ""
                    echo -e "${RED}❌ Token validation failed - the ${ENVIRONMENT^^} token is invalid or expired${NC}"
                    echo ""
                    
                    # Determine which token variable to update
                    if [ "$ENVIRONMENT" = "staging" ]; then
                        TOKEN_VAR="RAILWAY_PROJECT_TOKEN_STAGING"
                    else
                        TOKEN_VAR="RAILWAY_PROJECT_TOKEN_PRODUCTION"
                    fi
                    
                    # Clear stale token from .env
                    if [ -f "$PROJECT_ROOT/.env" ]; then
                        if grep -q "^${TOKEN_VAR}=" "$PROJECT_ROOT/.env" 2>/dev/null; then
                            if [[ "$OSTYPE" == "darwin"* ]]; then
                                sed -i '' "/^${TOKEN_VAR}=/d" "$PROJECT_ROOT/.env"
                            else
                                sed -i "/^${TOKEN_VAR}=/d" "$PROJECT_ROOT/.env"
                            fi
                            echo -e "${YELLOW}🗑️  Cleared stale $TOKEN_VAR from .env${NC}"
                        fi
                    fi
                    
                    # Prompt for new token
                    echo -e "${YELLOW}📝 Please provide a valid ${ENVIRONMENT^^} project token:${NC}"
                    echo -e "${BLUE}🔗 Get it from: https://railway.app/project/$PROJECT_ID/settings/tokens${NC}"
                    echo -e "${CYAN}   Note: Input will not be shown for security${NC}"
                    read -sp "${ENVIRONMENT^^} Project Token: " NEW_TOKEN
                    echo ""
                    
                    if [ -z "$NEW_TOKEN" ]; then
                        echo -e "${RED}❌ No token provided. Deployment cancelled.${NC}"
                        exit 1
                    fi
                    
                    # Save new token
                    echo "${TOKEN_VAR}=${NEW_TOKEN}" >> "$PROJECT_ROOT/.env"
                    echo -e "${GREEN}✅ Saved new $TOKEN_VAR to .env${NC}"
                    
                    # Update token for retry
                    PROJECT_TOKEN="$NEW_TOKEN"
                    export RAILWAY_TOKEN="$PROJECT_TOKEN"
                    TOKEN_RETRY_COUNT=$((TOKEN_RETRY_COUNT + 1))
                    echo ""
                    echo -e "${CYAN}Retrying deployment with new token...${NC}"
                elif echo "$RAILWAY_DEPLOY_OUTPUT" | grep -qiE "404|Failed to upload code"; then
                    # Service/environment ID invalid – invalidate so setup can re-discover (same as token invalidation)
                    clear_env_var_in_file "RAILWAY_APP_SERVICE_ID"
                    echo -e "${RED}❌ App deployment failed (service or environment invalid)${NC}"
                    echo ""
                    echo -e "${CYAN}   Re-run: ./scripts/setup.sh --setup-deployment (or with --force-backend) to re-discover services.${NC}"
                    exit 2
                else
                    # Non-token error, don't retry
                    echo -e "${RED}❌ Deployment failed${NC}"
                    echo ""
                    echo -e "${YELLOW}💡 Tip: Make sure the token is a project token for the $ENVIRONMENT environment${NC}"
                    echo "   Get it from: https://railway.app/project/$PROJECT_ID/settings/tokens"
                    exit 1
                fi
            fi
        done
        
        if [ "$DEPLOY_SUCCESS" = "false" ]; then
            echo -e "${RED}❌ App deployment failed after $MAX_TOKEN_RETRIES token attempts${NC}"
            exit 1
        fi
        
        # Ensure app service has a Railway-provided public domain (*.railway.app). Terraform provider has no domain resource; use CLI.
        echo -e "${BLUE}🔗 Ensuring public domain for app service...${NC}"
        (railway domain --json 2>/dev/null || railway domain 2>/dev/null) || true
        
        # Backend deploy uses only Terraform output (same project/env we just applied). Service IDs are never persisted to .env.
        BACKEND_DEPLOY_ID="$BACKEND_SERVICE_ID"
        [ -n "${FORCE_BACKEND:-}" ] && [ -n "$BACKEND_DEPLOY_ID" ] && echo -e "${CYAN}ℹ️  --force-backend: using backend service $BACKEND_DEPLOY_ID${NC}"
        if [ -n "$BACKEND_DEPLOY_ID" ] && [ "$BACKEND_DEPLOY_ID" != "null" ]; then
            echo ""
            if [ -n "${FORCE_BACKEND:-}" ]; then
                echo -e "${BLUE}🚀 Forcing backend redeploy to Railway ($ENVIRONMENT environment)...${NC}"
            else
                echo -e "${BLUE}🚀 Deploying backend service to Railway ($ENVIRONMENT environment)...${NC}"
            fi
            
            # Railway uses root railway.json for build/start. Use backend-server config for backend deploys.
            RAILWAY_JSON_ROOT="$PROJECT_ROOT/railway.json"
            RAILWAY_JSON_BACKEND="$PROJECT_ROOT/targets/backend-server/railway.json"
            RAILWAY_JSON_BAK="$PROJECT_ROOT/railway.json.app.bak"
            restore_railway_json() {
                if [ -n "${RAILWAY_JSON_BAK:-}" ] && [ -f "$RAILWAY_JSON_BAK" ]; then
                    mv "$RAILWAY_JSON_BAK" "$RAILWAY_JSON_ROOT"
                fi
            }
            if [ -f "$RAILWAY_JSON_BACKEND" ]; then
                cp "$RAILWAY_JSON_ROOT" "$RAILWAY_JSON_BAK"
                cp "$RAILWAY_JSON_BACKEND" "$RAILWAY_JSON_ROOT"
                trap restore_railway_json EXIT
            fi
            
            # Ensure dependencies are installed before backend build
            if [ ! -f "node_modules/.bin/prisma" ] && [ -f "package.json" ]; then
                echo -e "${BLUE}ℹ️  Prisma/dependencies not found, running npm install...${NC}"
                npm install || { echo -e "${RED}❌ npm install failed${NC}"; exit 1; }
                echo ""
            fi
            # Build backend server first (artifact for deploy; Railway may also build on its side using backend config)
            echo -e "${BLUE}🔨 Building backend server...${NC}"
            BACKEND_BUILD_EXIT=0
            npm run build:backend-server || {
                BACKEND_BUILD_EXIT=$?
                echo -e "${YELLOW}⚠️  Backend build failed, skipping backend deployment${NC}"
            }
            
            if [ "$BACKEND_BUILD_EXIT" -eq 0 ]; then
                BACKEND_DEPLOY_SUCCESS=false
                # Use same project token as app deploy so backend deploy is authorized (account token causes Unauthorized for railway up).
                BACKEND_DEPLOY_TOKEN="$PROJECT_TOKEN"
                export RAILWAY_TOKEN="$BACKEND_DEPLOY_TOKEN"
                unset RAILWAY_API_TOKEN
                export CI=true
                if [ -d ".railway" ]; then
                    RAILWAY_LINK_BAK_SVC=$(cat .railway/service 2>/dev/null || echo "")
                    RAILWAY_LINK_BAK_PRJ=$(cat .railway/project 2>/dev/null || echo "")
                    RAILWAY_LINK_BAK_ENV=$(cat .railway/environment 2>/dev/null || echo "")
                fi
                railway link --project "$PROJECT_ID" --service "$BACKEND_DEPLOY_ID" --environment "$ENVIRONMENT" 2>/dev/null || {
                    mkdir -p .railway
                    echo "$BACKEND_DEPLOY_ID" > .railway/service
                    echo "$PROJECT_ID" > .railway/project
                    echo "$ENVIRONMENT" > .railway/environment
                }
                if deploy_to_railway "$BACKEND_DEPLOY_TOKEN" "$PROJECT_ID" "$BACKEND_DEPLOY_ID" "$ENVIRONMENT" "verbose"; then
                    BACKEND_DEPLOY_SUCCESS=true
                    echo -e "${GREEN}✅ Backend deployment successful!${NC}"
                    rm -f "$PROJECT_ROOT/.railway-backend-invalidated"
                    # Ensure backend service has a Railway-provided public domain (*.railway.app)
                    echo -e "${BLUE}🔗 Ensuring public domain for backend service...${NC}"
                    (railway domain --json 2>/dev/null || railway domain 2>/dev/null) || true
                else
                    echo -e "${YELLOW}⚠️  Backend deployment failed${NC}"
                    if echo "$RAILWAY_DEPLOY_OUTPUT" | grep -qiE "404|Failed to upload code"; then
                        # Self-heal: remove invalid backend from state and re-run apply so Terraform creates a new backend
                        if [ "${RAILWAY_BACKEND_SELF_HEAL:-0}" = "1" ]; then
                            DEPLOY_INVALIDATED_SERVICE=1
                            echo -e "${CYAN}   Self-heal already attempted; backend still invalid. Re-run: ./scripts/setup.sh --setup-deployment${NC}"
                        else
                            echo -e "${BLUE}🔧 Self-healing: removing invalid backend from Terraform state and retrying...${NC}"
                            cd "$SCRIPT_DIR"
                            BACKEND_RES="module.railway_owner[0].railway_service.backend_${ENVIRONMENT}[0]"
                            if terraform state list 2>/dev/null | grep -qF "$BACKEND_RES"; then
                                terraform state rm "$BACKEND_RES" 2>/dev/null || true
                                echo -e "${GREEN}   Removed backend-${ENVIRONMENT} from state.${NC}"
                            fi
                            touch "$PROJECT_ROOT/.railway-backend-invalidated"
                            export RAILWAY_BACKEND_SELF_HEAL=1
                            APPLY_ARGS=("$ENVIRONMENT")
                            [ -n "${FORCE_BACKEND:-}" ] && APPLY_ARGS=("--force-backend" "$ENVIRONMENT")
                            echo -e "${BLUE}   Re-running apply to create new backend and deploy.${NC}"
                            echo ""
                            "$0" terraform apply "${APPLY_ARGS[@]}"
                        fi
                    fi
                fi
                # Restore .railway link to app service for any later commands
                if [ -d ".railway" ] && [ -n "${RAILWAY_LINK_BAK_SVC:-}" ]; then
                    echo "$RAILWAY_LINK_BAK_SVC" > .railway/service
                    [ -n "${RAILWAY_LINK_BAK_PRJ:-}" ] && echo "$RAILWAY_LINK_BAK_PRJ" > .railway/project
                    [ -n "${RAILWAY_LINK_BAK_ENV:-}" ] && echo "$RAILWAY_LINK_BAK_ENV" > .railway/environment
                fi
            fi
            
            trap - EXIT
            restore_railway_json
        fi
        
        echo ""
        echo -e "${GREEN}✅ Deployment complete!${NC}"
        echo "Your application should be live on Railway shortly."
    fi
fi

echo ""
if [ "${DEPLOY_INVALIDATED_SERVICE:-0}" = "1" ]; then
    echo -e "${YELLOW}⚠️  Backend deploy failed after self-heal retry. Re-run: ./scripts/setup.sh --setup-deployment${NC}"
    exit 2
fi
echo -e "${GREEN}✅ All done!${NC}"
