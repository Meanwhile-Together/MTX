#!/usr/bin/env bash
# MTX setup deploy-menu: interactive deploy menu (from shell-scripts.md §3)
desc="Interactive deploy menu: tokens, Terraform, Railway"
nobanner=1
set -e

ENV_FILE=".env"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Ensure we're in project root (mtx already cd's here; after we cd terraform we need to get back)
go_to_project_root() {
    while [ ! -f "package.json" ] && [ "$(pwd)" != "/" ]; do cd ..; done
}

# Load existing .env file if it exists
if [ -f "$ENV_FILE" ]; then
    set -a
    source "$ENV_FILE"
    set +a
fi

# Function to save environment variable to .env
save_env_var() {
    local key="$1"
    local value="$2"
    
    # Remove existing entry if present
    if grep -q "^${key}=" "$ENV_FILE" 2>/dev/null; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "/^${key}=/d" "$ENV_FILE"
        else
            sed -i "/^${key}=/d" "$ENV_FILE"
        fi
    fi
    
    # Append new entry
    echo "${key}=${value}" >> "$ENV_FILE"
    echo -e "${GREEN}✅ Saved ${key} to .env${NC}"
}

# Function to prompt for token with hidden input
prompt_token() {
    local var_name="$1"
    local description="$2"
    local link="$3"
    
    echo ""
    echo -e "${CYAN}${description}${NC}"
    if [ -n "$link" ]; then
        echo -e "${BLUE}🔗 Get it from: ${link}${NC}"
    fi
    echo -e "${YELLOW}   Note: Input will not be shown for security${NC}"
    read -sp "${var_name}: " token
    echo ""
    
    if [ -z "$token" ]; then
        echo -e "${RED}❌ No token provided${NC}"
        return 1
    fi
    
    # Save to .env
    save_env_var "$var_name" "$token"
    export "$var_name=$token"
    return 0
}

# Function to check if token exists
has_token() {
    local var_name="$1"
    if [ -n "${!var_name}" ]; then
        return 0
    fi
    return 1
}

# Function to display main menu
show_menu() {
    clear
    echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║   Deployment Setup & Management       ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
    echo ""
    
    # Only show Guided Setup if repo is not set up
    if ! is_repo_setup; then
        echo -e "${CYAN}1.${NC} Install Dependencies"
        echo -e "${CYAN}2.${NC} Manage API Tokens"
        echo -e "${CYAN}3.${NC} Provision Infrastructure (Terraform)"
        echo -e "${CYAN}4.${NC} Deploy to Railway"
        echo -e "${CYAN}5.${NC} View Current Configuration"
        echo -e "${CYAN}6.${NC} Exit"
        echo ""
        read -p "Select an option (1-6): " choice
    else
        echo -e "${CYAN}1.${NC} Install Dependencies"
        echo -e "${CYAN}2.${NC} Manage API Tokens"
        echo -e "${CYAN}3.${NC} Provision Infrastructure (Terraform)"
        echo -e "${CYAN}4.${NC} Deploy to Railway"
        echo -e "${CYAN}5.${NC} View Current Configuration"
        echo -e "${CYAN}6.${NC} Exit"
        echo ""
        read -p "Select an option (1-6): " choice
    fi
}

# Function to check if repo is set up
is_repo_setup() {
    if [ ! -f "./config/deploy.json" ]; then
        return 1  # Not set up
    fi
    
    # Check if platform array is empty or missing
    PLATFORM_COUNT=$(jq -r '.platform | length' "./config/deploy.json" 2>/dev/null || echo "0")
    if [ "$PLATFORM_COUNT" = "0" ] || [ "$PLATFORM_COUNT" = "null" ]; then
        return 1  # Not set up
    fi
    
    return 0  # Set up
}

# Function to prompt for initial setup
initial_setup() {
    echo -e "${BLUE}🎯 Initial Repository Setup${NC}"
    echo "=============================="
    echo ""
    echo "This appears to be a fresh repository. Let's configure it."
    echo ""
    
    # Prompt for app name
    read -p "Application name (default: My Application): " APP_NAME
    APP_NAME="${APP_NAME:-My Application}"
    
    # Prompt for deploy platforms
    echo ""
    echo -e "${CYAN}Select deployment platforms:${NC}"
    echo "1. Railway only (default)"
    echo "2. Railway + Vercel"
    echo "3. Custom selection"
    read -p "Select option (1-3, default: 1): " PLATFORM_CHOICE
    PLATFORM_CHOICE="${PLATFORM_CHOICE:-1}"
    
    case $PLATFORM_CHOICE in
        1)
            PLATFORMS='["railway"]'
            ;;
        2)
            PLATFORMS='["railway", "vercel"]'
            ;;
        3)
            echo ""
            echo "Available platforms: railway, vercel"
            read -p "Enter platforms (comma-separated, default: railway): " CUSTOM_PLATFORMS
            CUSTOM_PLATFORMS="${CUSTOM_PLATFORMS:-railway}"
            # Convert comma-separated to JSON array
            PLATFORMS=$(echo "$CUSTOM_PLATFORMS" | jq -R -s -c 'split(",") | map(select(length > 0) | gsub("^\\s+|\\s+$"; ""))')
            ;;
        *)
            PLATFORMS='["railway"]'
            ;;
    esac
    
    # Create config directory if it doesn't exist
    mkdir -p "./config"
    
    # Create/update deploy.json
    cat > "./config/deploy.json" <<EOF
{
  "platform": $PLATFORMS,
  "projectId": "",
  "staging": {
    "healthEndpoints": []
  },
  "production": {
    "healthEndpoints": []
  }
}
EOF
    
    # Create/update app.json
    if [ ! -f "./config/app.json" ]; then
        cat > "./config/app.json" <<EOF
{
  "app": {
    "name": "$APP_NAME",
    "version": "1.0.0"
  },
  "server": {
    "port": 3001,
    "mode": "production",
    "apiUrl": "http://localhost:3001",
    "debug": false
  },
  "ai": {
    "inferenceMode": "local",
    "serverMode": "local",
    "enableLogging": false
  },
  "chatbots": []
}
EOF
    else
        # Update app name in existing app.json
        APP_JSON=$(cat "./config/app.json")
        echo "$APP_JSON" | jq ".app.name = \"$APP_NAME\"" > "./config/app.json.tmp"
        mv "./config/app.json.tmp" "./config/app.json"
    fi
    
    echo ""
    echo -e "${GREEN}✅ Repository configured!${NC}"
    echo "  App name: $APP_NAME"
    echo "  Platforms: $(echo "$PLATFORMS" | jq -r 'join(", ")')"
    echo ""
    read -p "Press Enter to continue..."
}

# Function for guided setup
guided_setup() {
    echo -e "${BLUE}🚀 Guided Setup${NC}"
    echo "=================="
    echo ""
    
    # Step 1: Check if repo is cloned
    if [ ! -f "./package.json" ]; then
        echo -e "${YELLOW}⚠️  This doesn't appear to be the project directory${NC}"
        echo "Please make sure you've cloned the repository and are in the project root."
        read -p "Press Enter to continue or Ctrl+C to exit..."
        return 1
    fi
    
    # Step 2: Check if repo is set up
    if ! is_repo_setup; then
        initial_setup
    fi
    
    # Step 3: Install dependencies
    echo -e "${CYAN}Step 1: Installing dependencies...${NC}"
    go_to_project_root
    if ! npm install; then
        echo -e "${RED}❌ Failed to install dependencies${NC}"
        return 1
    fi
    echo -e "${GREEN}✅ Dependencies installed${NC}"
    echo ""
    
    # Step 4: Check which platforms need tokens
    PLATFORMS=$(jq -r '.platform | join(", ")' "./config/deploy.json" 2>/dev/null || echo "railway")
    echo -e "${CYAN}Step 2: Checking required API tokens...${NC}"
    echo "Platforms configured: $PLATFORMS"
    echo ""
    
    # Step 5: Collect tokens
    HAS_RAILWAY=$(jq -r '.platform | index("railway") != null' "./config/deploy.json" 2>/dev/null || echo "false")
    HAS_VERCEL=$(jq -r '.platform | index("vercel") != null' "./config/deploy.json" 2>/dev/null || echo "false")
    
    if [ "$HAS_RAILWAY" = "true" ]; then
        if ! has_token "RAILWAY_TOKEN"; then
            prompt_token "RAILWAY_TOKEN" "Railway Account Token (required for project creation)" "https://railway.app/account/tokens"
        else
            echo -e "${GREEN}✅ RAILWAY_TOKEN already set${NC}"
        fi
    fi
    
    if [ "$HAS_VERCEL" = "true" ]; then
        if ! has_token "VERCEL_TOKEN"; then
            prompt_token "VERCEL_TOKEN" "Vercel API Token" "https://vercel.com/account/tokens"
        else
            echo -e "${GREEN}✅ VERCEL_TOKEN already set${NC}"
        fi
    fi
    
    echo ""
    echo -e "${CYAN}Step 3: Initializing Terraform...${NC}"
    cd terraform
    if ! terraform init; then
        echo -e "${RED}❌ Terraform initialization failed${NC}"
        return 1
    fi
    echo -e "${GREEN}✅ Terraform initialized${NC}"
    echo ""
    
    echo -e "${CYAN}Step 4: Provisioning infrastructure...${NC}"
    echo "This will create Railway projects, services, and databases."
    read -p "Continue? (y/n): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "Skipping infrastructure provisioning"
        return 0
    fi
    
    echo ""
    if ! "$0" terraform apply 2>&1 | tee /tmp/terraform-apply.log; then
        APPLY_EXIT=${PIPESTATUS[0]}
        echo ""
        echo -e "${RED}╔════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${RED}║  Infrastructure Provisioning Failed                       ║${NC}"
        echo -e "${RED}╚════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${YELLOW}What happened:${NC}"
        echo "  Terraform failed to provision your infrastructure. This could be due to:"
        echo "  - Missing or invalid API tokens"
        echo "  - Network connectivity issues"
        echo "  - Terraform state lock (another process is running)"
        echo "  - Provider authentication errors"
        echo "  - Resource creation conflicts"
        echo ""
        echo -e "${CYAN}How to resolve:${NC}"
        echo ""
        echo -e "${BLUE}1. Check the error messages above${NC}"
        echo "   Review the Terraform output for specific error details."
        echo ""
        echo -e "${BLUE}2. Verify your API tokens${NC}"
        echo "   Run: mtx setup deploy-menu → Option 2 (Manage API Tokens)"
        echo "   Ensure all required tokens are set correctly."
        echo ""
        echo -e "${BLUE}3. Check for state lock issues${NC}"
        echo "   If you see 'Error acquiring the state lock':"
        echo "   - Check for running Terraform: ps aux | grep terraform"
        echo "   - Remove stale lock: cd terraform && rm -f .terraform.tfstate.lock.info"
        echo ""
        echo -e "${BLUE}4. Review Terraform logs${NC}"
        echo "   Full output saved to: /tmp/terraform-apply.log"
        echo ""
        echo -e "${BLUE}5. Try running manually for more details${NC}"
        echo "   cd terraform"
        echo "   terraform init"
        echo "   mtx terraform apply"
        echo ""
        echo -e "${YELLOW}💡 Tip:${NC} The error message above should contain specific details"
        echo "   about what went wrong. Look for lines starting with 'Error:'"
        echo ""
        return 1
    fi
    
    # Step 5: Deploy to Railway (if Railway is configured)
    # DATABASE_URL: When Postgres is added to the db service, Railway auto-propagates DATABASE_URL to all services in the project (backend, app, any future services). One DB per owner project.
    if [ "$HAS_RAILWAY" = "true" ]; then
        echo ""
        echo -e "${CYAN}Step 5: Deploying to Railway...${NC}"
        echo "This will deploy your code to the provisioned infrastructure."
        echo -e "${BLUE}Note: DATABASE_URL is provided by the Railway Postgres extension to all services in the project (backend, app server).${NC}"
        read -p "Continue with deployment? (y/n, default: y): " deploy_confirm
        deploy_confirm="${deploy_confirm:-y}"
        
        if [ "$deploy_confirm" = "y" ] || [ "$deploy_confirm" = "Y" ]; then
            go_to_project_root
            
            # Get project and service IDs from Terraform
            cd terraform
            PROJECT_ID=$(terraform output -raw railway_project_id 2>/dev/null || echo "")
            SERVICE_ID=$(terraform output -raw railway_service_id 2>/dev/null || echo "")
            BACKEND_SERVICE_ID=$(terraform output -raw railway_backend_service_id 2>/dev/null || echo "")
            ENVIRONMENT="${ENVIRONMENT:-staging}"
            
            if [ -n "$PROJECT_ID" ] && [ "$PROJECT_ID" != "null" ] && [ -n "$SERVICE_ID" ] && [ "$SERVICE_ID" != "null" ]; then
                go_to_project_root
                
                # Check for Railway CLI
                if ! command -v railway &> /dev/null; then
                    echo -e "${BLUE}ℹ️  Installing Railway CLI...${NC}"
                    curl -fsSL https://railway.app/install.sh | sh
                    export PATH="$HOME/.railway/bin:$PATH"
                fi
                
                # Link directory
                if [ ! -d ".railway" ]; then
                    railway link --service "$SERVICE_ID" --project "$PROJECT_ID" 2>/dev/null || {
                        mkdir -p .railway
                        echo "$SERVICE_ID" > .railway/service
                        echo "$PROJECT_ID" > .railway/project
                    }
                fi
                
                # Get project token
                ENV_TOKEN_VAR="RAILWAY_PROJECT_TOKEN_$(echo "$ENVIRONMENT" | tr '[:lower:]' '[:upper:]')"
                PROJECT_TOKEN="${!ENV_TOKEN_VAR:-}"
                
                if [ -z "$PROJECT_TOKEN" ]; then
                    echo ""
                    echo -e "${YELLOW}📝 $ENVIRONMENT Project Token Required${NC}"
                    echo "Project tokens are scoped to specific environments."
                    echo ""
                    echo -e "${BLUE}🔗 Open this link to create a $ENVIRONMENT project token:${NC}"
                    echo "   https://railway.app/project/$PROJECT_ID/settings/tokens"
                    echo ""
                    echo -e "${CYAN}After creating the $ENVIRONMENT token, paste it below:${NC}"
                    echo -e "${CYAN}   Note: Input will not be shown for security${NC}"
                    read -sp "$ENVIRONMENT Project Token: " PROJECT_TOKEN
                    echo ""
                    
                    if [ -n "$PROJECT_TOKEN" ]; then
                        save_env_var "$ENV_TOKEN_VAR" "$PROJECT_TOKEN"
                    fi
                fi
                
                if [ -n "$PROJECT_TOKEN" ]; then
                    export RAILWAY_TOKEN="$PROJECT_TOKEN"
                    echo ""
                    echo -e "${BLUE}🚀 Deploying app server to Railway ($ENVIRONMENT environment)...${NC}"
                    railway up --environment "$ENVIRONMENT" || {
                        echo -e "${YELLOW}⚠️  Deployment failed. You can retry later with option 5.${NC}"
                    }
                    # Deploy backend (backend-server + backend panel) to backend service
                    if [ -n "$BACKEND_SERVICE_ID" ] && [ "$BACKEND_SERVICE_ID" != "null" ]; then
                        echo ""
                        read -p "Deploy backend (backend-server + backend panel) to the backend service? (y/n, default: n): " deploy_backend_confirm
                        deploy_backend_confirm="${deploy_backend_confirm:-n}"
                        if [ "$deploy_backend_confirm" = "y" ] || [ "$deploy_backend_confirm" = "Y" ]; then
                            go_to_project_root
                            echo -e "${CYAN}Building backend-server and backend...${NC}"
                            npm run build:backend-server && npm run build:backend || {
                                echo -e "${RED}❌ Build failed.${NC}"
                            }
                            # Railway uses root railway.json; swap to backend config so backend service gets correct build/start
                            RAILWAY_JSON_ROOT="./railway.json"
                            RAILWAY_JSON_BACKEND="./targets/backend-server/railway.json"
                            RAILWAY_JSON_BAK="./railway.json.app.bak"
                            if [ -f "$RAILWAY_JSON_BACKEND" ]; then
                                cp "$RAILWAY_JSON_ROOT" "$RAILWAY_JSON_BAK"
                                cp "$RAILWAY_JSON_BACKEND" "$RAILWAY_JSON_ROOT"
                            fi
                            echo -e "${BLUE}Linking to backend service and deploying...${NC}"
                            railway link --service "$BACKEND_SERVICE_ID" --project "$PROJECT_ID" 2>/dev/null || true
                            railway up --environment "$ENVIRONMENT" || {
                                echo -e "${YELLOW}⚠️  Backend deployment failed. Ensure the backend service has start command: node targets/backend-server/dist/index.js${NC}"
                            }
                            if [ -f "$RAILWAY_JSON_BAK" ]; then
                                mv "$RAILWAY_JSON_BAK" "$RAILWAY_JSON_ROOT"
                            fi
                            # Restore link to app service for future runs
                            railway link --service "$SERVICE_ID" --project "$PROJECT_ID" 2>/dev/null || true
                        fi
                    fi
                else
                    echo -e "${YELLOW}⚠️  No project token provided. Skipping deployment.${NC}"
                    echo "You can deploy later with option 5 from the main menu."
                fi
            else
                echo -e "${YELLOW}⚠️  Could not get Railway project/service IDs.${NC}"
                echo "You can deploy later with option 5 from the main menu."
            fi
        else
            echo "Skipping deployment. You can deploy later with option 5 from the main menu."
        fi
    fi
    
    echo ""
    echo -e "${GREEN}✅ Guided setup complete!${NC}"
    echo ""
    read -p "Press Enter to continue..."
}

# Function to manage API tokens
manage_tokens() {
    while true; do
        clear
        echo -e "${BLUE}🔐 API Token Management${NC}"
        echo "======================"
        echo ""
        echo -e "${CYAN}1.${NC} Set Railway Token"
        echo -e "${CYAN}2.${NC} Set Vercel Token"
        echo -e "${CYAN}3.${NC} View Current Tokens (masked)"
        echo -e "${CYAN}4.${NC} Clear All Tokens"
        echo -e "${CYAN}5.${NC} Back to Main Menu"
        echo ""
        read -p "Select an option (1-5): " token_choice
        
        case $token_choice in
            1)
                prompt_token "RAILWAY_TOKEN" "Railway Account Token" "https://railway.app/account/tokens"
                read -p "Press Enter to continue..."
                ;;
            2)
                prompt_token "VERCEL_TOKEN" "Vercel API Token" "https://vercel.com/account/tokens"
                read -p "Press Enter to continue..."
                ;;
            3)
                echo ""
                echo -e "${CYAN}Current Tokens:${NC}"
                if has_token "RAILWAY_TOKEN"; then
                    echo -e "${GREEN}✅ RAILWAY_TOKEN: ${RAILWAY_TOKEN:0:10}...${NC}"
                else
                    echo -e "${YELLOW}⚠️  RAILWAY_TOKEN: Not set${NC}"
                fi
                if has_token "VERCEL_TOKEN"; then
                    echo -e "${GREEN}✅ VERCEL_TOKEN: ${VERCEL_TOKEN:0:10}...${NC}"
                else
                    echo -e "${YELLOW}⚠️  VERCEL_TOKEN: Not set${NC}"
                fi
                read -p "Press Enter to continue..."
                ;;
            4)
                echo -e "${YELLOW}⚠️  This will remove all tokens from .env${NC}"
                read -p "Are you sure? (y/n): " confirm
                if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
                    if [ -f "$ENV_FILE" ]; then
                        if [[ "$OSTYPE" == "darwin"* ]]; then
                            sed -i '' '/^RAILWAY_TOKEN=/d; /^VERCEL_TOKEN=/d' "$ENV_FILE"
                        else
                            sed -i '/^RAILWAY_TOKEN=/d; /^VERCEL_TOKEN=/d' "$ENV_FILE"
                        fi
                        echo -e "${GREEN}✅ All tokens cleared${NC}"
                    fi
                fi
                read -p "Press Enter to continue..."
                ;;
            5)
                break
                ;;
            *)
                echo -e "${RED}Invalid option${NC}"
                read -p "Press Enter to continue..."
                ;;
        esac
    done
}


# Function to view current configuration
view_config() {
    clear
    echo -e "${BLUE}📋 Current Configuration${NC}"
    echo "========================"
    echo ""
    
    echo -e "${CYAN}Deploy Configuration:${NC}"
    if [ -f "./config/deploy.json" ]; then
        cat "./config/deploy.json" | jq '.' 2>/dev/null || cat "./config/deploy.json"
    else
        echo -e "${YELLOW}⚠️  config/deploy.json not found${NC}"
    fi
    
    echo ""
    echo -e "${CYAN}Environment Variables:${NC}"
    if [ -f "$ENV_FILE" ]; then
        # Show non-sensitive vars and mask sensitive ones
        grep -v "^RAILWAY_TOKEN=" "$ENV_FILE" | grep -v "^VERCEL_TOKEN=" | grep -v "^DATABASE_URL=" || true
        if grep -q "^RAILWAY_TOKEN=" "$ENV_FILE"; then
            TOKEN=$(grep "^RAILWAY_TOKEN=" "$ENV_FILE" | cut -d'=' -f2-)
            echo "RAILWAY_TOKEN=${TOKEN:0:10}..."
        fi
        if grep -q "^VERCEL_TOKEN=" "$ENV_FILE"; then
            TOKEN=$(grep "^VERCEL_TOKEN=" "$ENV_FILE" | cut -d'=' -f2-)
            echo "VERCEL_TOKEN=${TOKEN:0:10}..."
        fi
    else
        echo -e "${YELLOW}⚠️  .env file not found${NC}"
    fi
    
    echo ""
    read -p "Press Enter to continue..."
}

# Main loop
go_to_project_root

# Create .env file if it doesn't exist
if [ ! -f "$ENV_FILE" ]; then
    touch "$ENV_FILE"
    echo -e "${GREEN}✅ Created .env file${NC}"
fi

# Ensure .env is in .gitignore
if [ -f "./.gitignore" ]; then
    if ! grep -q "^\.env$" "./.gitignore"; then
        echo ".env" >> "./.gitignore"
    fi
fi

while true; do
    show_menu
    
    case $choice in
        1)
            echo -e "${CYAN}Installing dependencies...${NC}"
            go_to_project_root
            npm install
            echo -e "${GREEN}✅ Dependencies installed${NC}"
            read -p "Press Enter to continue..."
            ;;
        2)
            manage_tokens
            ;;
        3)
            echo -e "${CYAN}Provisioning infrastructure with Terraform...${NC}"
            cd terraform
            
            # Check for existing Terraform processes
            if pgrep -f "terraform (plan|apply)" > /dev/null; then
                echo -e "${YELLOW}⚠️  Another Terraform process is running${NC}"
                echo "Running Terraform processes:"
                ps aux | grep -E "terraform (plan|apply)" | grep -v grep
                echo ""
                read -p "Kill existing Terraform processes? (y/n): " kill_choice
                if [ "$kill_choice" = "y" ] || [ "$kill_choice" = "Y" ]; then
                    pkill -f "terraform (plan|apply)"
                    sleep 2
                    echo -e "${GREEN}✅ Killed existing Terraform processes${NC}"
                else
                    echo "Please wait for the existing process to finish or kill it manually"
                    read -p "Press Enter to continue..."
                    continue
                fi
            fi
            
            # Check for stale lock
            if [ -f "terraform.tfstate" ] && [ -s "terraform.tfstate" ]; then
                LOCK_INFO=$(terraform force-unlock -help 2>&1 | head -1 || echo "")
                # Try to check if lock is stale (older than 5 minutes)
                if [ -f ".terraform.tfstate.lock.info" ]; then
                    LOCK_AGE=$(find .terraform.tfstate.lock.info -mmin +5 2>/dev/null && echo "old" || echo "new")
                    if [ "$LOCK_AGE" = "old" ]; then
                        echo -e "${YELLOW}⚠️  Detected stale lock file${NC}"
                        read -p "Remove stale lock? (y/n): " unlock_choice
                        if [ "$unlock_choice" = "y" ] || [ "$unlock_choice" = "Y" ]; then
                            rm -f .terraform.tfstate.lock.info
                            echo -e "${GREEN}✅ Removed stale lock${NC}"
                        fi
                    fi
                fi
            fi
            
            if [ ! -d ".terraform" ]; then
                echo "Initializing Terraform..."
                terraform init
            fi
            
            echo ""
            if ! "$0" terraform apply 2>&1 | tee /tmp/terraform-apply.log; then
                APPLY_EXIT=${PIPESTATUS[0]}
                echo ""
                echo -e "${RED}╔════════════════════════════════════════════════════════════╗${NC}"
                echo -e "${RED}║  Infrastructure Provisioning Failed                       ║${NC}"
                echo -e "${RED}╚════════════════════════════════════════════════════════════╝${NC}"
                echo ""
                echo -e "${YELLOW}What happened:${NC}"
                echo "  Terraform failed to provision your infrastructure."
                echo ""
                echo -e "${CYAN}Common issues and solutions:${NC}"
                echo ""
                echo -e "${BLUE}• State lock error:${NC}"
                echo "  Another Terraform process is running or a stale lock exists."
                echo "  See the error message above for resolution steps."
                echo ""
                echo -e "${BLUE}• Missing API tokens:${NC}"
                echo "  Run: mtx setup deploy-menu → Option 2 (Manage API Tokens)"
                echo ""
                echo -e "${BLUE}• Authentication errors:${NC}"
                echo "  Verify your tokens are valid and have the correct permissions."
                echo ""
                echo -e "${BLUE}• Full error log:${NC}"
                echo "  Check: /tmp/terraform-apply.log"
                echo ""
            else
                echo -e "${GREEN}✅ Infrastructure provisioning completed successfully!${NC}"
            fi
            
            read -p "Press Enter to continue..."
            ;;
        4)
            echo -e "${CYAN}Deploying to Railway...${NC}"
            go_to_project_root
            
            # Check if Railway CLI is installed
            if ! command -v railway &> /dev/null; then
                echo -e "${BLUE}ℹ️  Installing Railway CLI...${NC}"
                curl -fsSL https://railway.app/install.sh | sh
                export PATH="$HOME/.railway/bin:$PATH"
            fi
            
            # Get project and service IDs from Terraform
            cd terraform
            if [ ! -f "terraform.tfstate" ] || [ ! -s "terraform.tfstate" ]; then
                echo -e "${RED}❌ Terraform state not found${NC}"
                echo "Please run option 3 (Provision Infrastructure) first."
                read -p "Press Enter to continue..."
                continue
            fi
            
            PROJECT_ID=$(terraform output -raw railway_project_id 2>/dev/null || echo "")
            SERVICE_ID=$(terraform output -raw railway_service_id 2>/dev/null || echo "")
            ENVIRONMENT="${ENVIRONMENT:-staging}"
            
            if [ -z "$PROJECT_ID" ] || [ "$PROJECT_ID" = "null" ]; then
                echo -e "${RED}❌ Could not get Railway project ID from Terraform${NC}"
                echo "Please run option 3 (Provision Infrastructure) first."
                read -p "Press Enter to continue..."
                continue
            fi
            
            if [ -z "$SERVICE_ID" ] || [ "$SERVICE_ID" = "null" ]; then
                echo -e "${RED}❌ Could not get Railway service ID from Terraform${NC}"
                echo "Please run option 3 (Provision Infrastructure) first."
                read -p "Press Enter to continue..."
                continue
            fi
            
            echo -e "${GREEN}✅ Found Railway project: $PROJECT_ID${NC}"
            echo -e "${GREEN}✅ Found Railway service: $SERVICE_ID${NC}"
            echo -e "${GREEN}✅ Deploying to environment: $ENVIRONMENT${NC}"
            echo ""
            
            # Check for account token (for linking)
            if ! has_token "RAILWAY_TOKEN"; then
                echo -e "${YELLOW}⚠️  RAILWAY_TOKEN (account token) not set${NC}"
                prompt_token "RAILWAY_TOKEN" "Railway Account Token (for linking)" "https://railway.app/account/tokens"
            fi
            export RAILWAY_TOKEN
            
            # Link directory to Railway if not already linked
            go_to_project_root
            if [ ! -d ".railway" ]; then
                echo -e "${BLUE}🔗 Linking directory to Railway service...${NC}"
                railway link --service "$SERVICE_ID" --project "$PROJECT_ID" 2>/dev/null || {
                    mkdir -p .railway
                    echo "$SERVICE_ID" > .railway/service
                    echo "$PROJECT_ID" > .railway/project
                }
            fi
            
            # Get environment-specific project token
            ENV_TOKEN_VAR="RAILWAY_PROJECT_TOKEN_$(echo "$ENVIRONMENT" | tr '[:lower:]' '[:upper:]')"
            PROJECT_TOKEN="${!ENV_TOKEN_VAR:-}"
            
            if [ -z "$PROJECT_TOKEN" ]; then
                echo ""
                echo -e "${YELLOW}📝 $ENVIRONMENT Project Token Required${NC}"
                echo "Project tokens are scoped to specific environments."
                echo "You need a separate project token for the $ENVIRONMENT environment."
                echo ""
                echo -e "${BLUE}🔗 Open this link to create a $ENVIRONMENT project token:${NC}"
                echo "   https://railway.app/project/$PROJECT_ID/settings/tokens"
                echo ""
                echo -e "${CYAN}After creating the $ENVIRONMENT token, paste it below:${NC}"
                echo -e "${CYAN}   Note: Input will not be shown for security${NC}"
                read -sp "$ENVIRONMENT Project Token: " PROJECT_TOKEN
                echo ""
                echo ""
                
                if [ -z "$PROJECT_TOKEN" ]; then
                    echo -e "${RED}❌ No token provided. Deployment cancelled.${NC}"
                    read -p "Press Enter to continue..."
                    continue
                fi
                
                # Save to .env
                save_env_var "$ENV_TOKEN_VAR" "$PROJECT_TOKEN"
                echo -e "${BLUE}💡 Tip: Token saved to .env as $ENV_TOKEN_VAR${NC}"
                echo ""
            else
                echo -e "${GREEN}✅ Found $ENVIRONMENT project token${NC}"
                echo ""
            fi
            
            # Deploy with project token
            export RAILWAY_TOKEN="$PROJECT_TOKEN"
            echo -e "${BLUE}🚀 Deploying to Railway ($ENVIRONMENT environment)...${NC}"
            
            # Capture output to check for errors
            RAILWAY_OUTPUT=$(railway up --environment "$ENVIRONMENT" 2>&1)
            RAILWAY_EXIT=$?
            
            # Check for "Project Token not found" error
            if echo "$RAILWAY_OUTPUT" | grep -qi "Project Token not found\|project token"; then
                echo "$RAILWAY_OUTPUT"
                echo ""
                echo -e "${RED}╔════════════════════════════════════════════════════════════╗${NC}"
                echo -e "${RED}║  Project Token Error                                      ║${NC}"
                echo -e "${RED}╚════════════════════════════════════════════════════════════╝${NC}"
                echo ""
                echo -e "${YELLOW}What happened:${NC}"
                echo "  Railway CLI requires a project token for deployment, but the"
                echo "  provided token was not found or is invalid."
                echo ""
                echo -e "${CYAN}How to resolve:${NC}"
                echo ""
                echo -e "${BLUE}1. Create a project token for the $ENVIRONMENT environment:${NC}"
                echo "   https://railway.app/project/$PROJECT_ID/settings/tokens"
                echo ""
                echo -e "${BLUE}2. Paste the token when prompted below:${NC}"
                echo ""
                read -sp "$ENVIRONMENT Project Token: " NEW_PROJECT_TOKEN
                echo ""
                
                if [ -z "$NEW_PROJECT_TOKEN" ]; then
                    echo -e "${RED}❌ No token provided. Deployment cancelled.${NC}"
                    read -p "Press Enter to continue..."
                    continue
                fi
                
                # Save new token
                save_env_var "$ENV_TOKEN_VAR" "$NEW_PROJECT_TOKEN"
                export RAILWAY_TOKEN="$NEW_PROJECT_TOKEN"
                
                # Retry deployment
                echo ""
                echo -e "${BLUE}🚀 Retrying deployment...${NC}"
                railway up --environment "$ENVIRONMENT"
            elif [ $RAILWAY_EXIT -ne 0 ]; then
                echo "$RAILWAY_OUTPUT"
                echo ""
                echo -e "${RED}❌ Deployment failed${NC}"
                echo "Review the error messages above for details."
            else
                echo "$RAILWAY_OUTPUT"
                echo ""
                echo -e "${GREEN}✅ Deployment successful!${NC}"
            fi
            
            read -p "Press Enter to continue..."
            ;;
        5)
            view_config
            ;;
        6)
            echo -e "${GREEN}Goodbye!${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid option. Please select 1-6.${NC}"
            read -p "Press Enter to continue..."
            ;;
    esac
done
