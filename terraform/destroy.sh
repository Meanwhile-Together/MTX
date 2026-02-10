#!/usr/bin/env bash
# MTX terraform destroy: run from project root (wrapper sets cwd); use project's terraform dir
desc="Destroy Terraform-managed resources for environment"
set -e

PROJECT_ROOT="$(pwd)"
SCRIPT_DIR="$PROJECT_ROOT/terraform"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${RED}🗑️  Terraform Destroy - Smart API Key Detection${NC}"
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

# Get app name
APP_NAME=$(jq -r '.app.name' "$PROJECT_ROOT/config/app.json" 2>/dev/null || echo "")
if [ -z "$APP_NAME" ]; then
    echo "⚠️  app.name not found in config/app.json, using default"
    APP_NAME="My Application"
fi

# Get environment from script argument (default: staging)
ENVIRONMENT="${1:-staging}"

if [ "$ENVIRONMENT" != "staging" ] && [ "$ENVIRONMENT" != "production" ]; then
    echo -e "${RED}❌ Environment must be 'staging' or 'production'${NC}"
    exit 1
fi

echo -e "${YELLOW}⚠️  WARNING: This will destroy all Terraform-managed resources for:${NC}"
echo -e "   Environment: ${RED}$ENVIRONMENT${NC}"
echo -e "   Platforms: ${RED}$PLATFORMS${NC}"
echo ""
echo -e "${YELLOW}This action cannot be undone!${NC}"
echo ""
read -p "Type 'yes' to confirm destruction: " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo -e "${BLUE}ℹ️  Destruction cancelled${NC}"
    exit 0
fi

echo ""
echo -e "${BLUE}🔐 Checking API keys...${NC}"
echo ""

# Build Terraform variables array
TF_VARS=(
    -var="environment=$ENVIRONMENT"
)

# Railway (same token order as apply.sh: RAILWAY_TOKEN, RAILWAY_ACCOUNT_TOKEN, TF_VAR_railway_token)
if [ "$HAS_RAILWAY" = "true" ]; then
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
        echo -e "${YELLOW}⚠️${NC}  Railway token not found - Terraform will prompt for it"
    fi
    
    # Resolve workspace ID from app owner name (config/app.json); no manual RAILWAY_WORKSPACE_ID needed
    if [ -n "${RAILWAY_WORKSPACE_ID:-}" ]; then
        echo -e "${GREEN}✅${NC} RAILWAY_WORKSPACE_ID found in environment: $RAILWAY_WORKSPACE_ID"
        TF_VARS+=(-var="railway_workspace_id=$RAILWAY_WORKSPACE_ID")
    elif [ -n "$RAILWAY_TOKEN_VALUE" ]; then
        APP_OWNER=$(jq -r '.app.owner // ""' "$PROJECT_ROOT/config/app.json" 2>/dev/null || echo "")
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
            else
                echo -e "${YELLOW}⚠️${NC}  Could not resolve workspace from Railway API"
                echo -e "${YELLOW}   Terraform will prompt for railway_workspace_id"
            fi
        else
            echo -e "${YELLOW}⚠️${NC}  Could not fetch workspaces (API call failed)"
            echo -e "${YELLOW}   Terraform will prompt for railway_workspace_id"
        fi
    else
        echo -e "${YELLOW}⚠️${NC}  No Railway token found - cannot resolve workspace from owner"
        echo -e "${YELLOW}   Terraform will prompt for both token and workspace ID"
    fi
else
    echo -e "${RED}❌ Railway is required. Add \"railway\" to config/deploy.json platform array.${NC}"
    exit 1
fi

echo ""
echo -e "${RED}🗑️  Running terraform destroy...${NC}"
echo ""

# Change to terraform directory
cd "$SCRIPT_DIR"

# Run terraform destroy
if ! terraform destroy "${TF_VARS[@]}"; then
    echo -e "${RED}❌ Terraform destroy failed${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}✅ Destruction complete!${NC}"
echo ""
echo -e "${BLUE}ℹ️  Note: Some resources may take time to fully delete${NC}"
echo "   Check your platform dashboards to confirm all resources are removed."
