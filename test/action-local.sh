#!/bin/bash
# MTX test action-local: local test for setup-environment action (from shell-scripts.md §12)
desc="Local test for setup-environment composite action"
set -e

NODE_VERSION="${1:-}"
INSTALL_DEV_DEPS="${2:-false}"
CACHE_NPM="${3:-true}"
WORKFLOW_CONFIG_PATH="${4:-.github/config/workflow-constants.json}"
DEPLOY_CONFIG_PATH="${5:-config/deploy.json}"
APP_CONFIG_PATH="${6:-config/app.json}"
LOAD_CONFIG="${7:-true}"
ENVIRONMENT="${8:-production}"

OUTPUT_DIR=$(mktemp -d)
GITHUB_OUTPUT="$OUTPUT_DIR/outputs"
GITHUB_ENV="$OUTPUT_DIR/env"

export GITHUB_REPOSITORY_OWNER="${GITHUB_REPOSITORY_OWNER:-nackloose}"
export GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-nackloose/dogfood}"
export GITHUB_EVENT_REPOSITORY_NAME="${GITHUB_EVENT_REPOSITORY_NAME:-dogfood}"

echo "🧪 Testing setup-environment action locally"
echo "=========================================="
echo "Node version: ${NODE_VERSION:-from config}"
echo "Install dev deps: $INSTALL_DEV_DEPS"
echo "Cache npm: $CACHE_NPM"
echo "Load config: $LOAD_CONFIG"
echo "Environment: $ENVIRONMENT"
echo ""

add_output() {
    echo "$1" >> "$GITHUB_OUTPUT"
}

if [ "$LOAD_CONFIG" = "true" ]; then
    echo "📋 Step 1: Loading workflow configuration..."
    CONFIG_FILE="$WORKFLOW_CONFIG_PATH"

    if [ ! -f "$CONFIG_FILE" ]; then
        echo "❌ Error: Configuration file not found at $CONFIG_FILE"
        exit 1
    fi

    echo "Loading workflow configuration from $CONFIG_FILE"

    REPO_OWNER="$GITHUB_REPOSITORY_OWNER"
    REPO_NAME="$GITHUB_EVENT_REPOSITORY_NAME"
    if [ -z "$REPO_NAME" ]; then
        REPO_NAME=$(echo "$GITHUB_REPOSITORY" | cut -d'/' -f2)
    fi
    add_output "repo-owner=$REPO_OWNER"
    add_output "repo-name=$REPO_NAME"
    add_output "branch-main=main"
    add_output "branch-staging=staging"
    add_output "branch-dev=dev"

    if command -v jq &> /dev/null; then
        TITLE_DEV_TO_STAGING=$(jq -r '.pr.title_templates.dev_to_staging' "$CONFIG_FILE")
        TITLE_STAGING_TO_MAIN=$(jq -r '.pr.title_templates.staging_to_main' "$CONFIG_FILE")
        TITLE_BACKPORT=$(jq -r '.pr.title_templates.backport' "$CONFIG_FILE")
        add_output "title-dev-to-staging=$TITLE_DEV_TO_STAGING"
        add_output "title-staging-to-main=$TITLE_STAGING_TO_MAIN"
        add_output "title-backport=$TITLE_BACKPORT"

        COMMIT_SYNC=$(jq -r '.pr.commit_templates.sync' "$CONFIG_FILE")
        COMMIT_BACKPORT=$(jq -r '.pr.commit_templates.backport' "$CONFIG_FILE")
        add_output "commit-sync=$COMMIT_SYNC"
        add_output "commit-backport=$COMMIT_BACKPORT"

        TEST_COVERAGE=$(jq -r '.workflow.test.coverage_threshold' "$CONFIG_FILE")
        TEST_NODE=$(jq -r '.workflow.test.node_version' "$CONFIG_FILE")
        add_output "test-coverage-threshold=$TEST_COVERAGE"
        add_output "test-node-version=$TEST_NODE"
    else
        echo "⚠️  Warning: jq not found, skipping JSON parsing"
    fi

    echo "✅ Workflow configuration loaded"
fi

if [ "$LOAD_CONFIG" = "true" ]; then
    echo ""
    echo "📋 Step 2: Loading deployment configuration..."
    DEPLOY_CONFIG_FILE="$DEPLOY_CONFIG_PATH"

    if [ ! -f "$DEPLOY_CONFIG_FILE" ]; then
        echo "⚠️  Warning: Deployment configuration file not found at $DEPLOY_CONFIG_FILE"
        add_output "deployment-platform=railway"
    else
        echo "Loading deployment configuration from $DEPLOY_CONFIG_FILE"
        if command -v jq &> /dev/null; then
            PLATFORM_TYPE=$(jq -r '.platform | type' "$DEPLOY_CONFIG_FILE" 2>/dev/null || echo "null")

            if [ "$PLATFORM_TYPE" = "array" ]; then
                DEPLOYMENT_PLATFORM=$(jq -r '.platform[] | select(. == "railway" or . == "vercel") | .' "$DEPLOY_CONFIG_FILE" | head -n1)
            else
                echo "⚠️  Warning: Platform must be an array in deploy.json. Found: $PLATFORM_TYPE"
                DEPLOYMENT_PLATFORM="railway"
            fi

            if [ -z "$DEPLOYMENT_PLATFORM" ]; then
                DEPLOYMENT_PLATFORM="railway"
            fi

            DEPLOYMENT_PROJECT_ID=$(jq -r '.projectId // ""' "$DEPLOY_CONFIG_FILE")
            add_output "deployment-platform=$DEPLOYMENT_PLATFORM"
            add_output "deployment-project-id=$DEPLOYMENT_PROJECT_ID"
        fi
    fi

    echo "✅ Deployment configuration loaded"
fi

if [ "$LOAD_CONFIG" = "true" ]; then
    echo ""
    echo "📋 Step 3: Loading app configuration..."
    APP_CONFIG_FILE="$APP_CONFIG_PATH"

    if [ ! -f "$APP_CONFIG_FILE" ]; then
        echo "⚠️  Warning: App configuration file not found at $APP_CONFIG_FILE"
    else
        echo "Loading app configuration from $APP_CONFIG_FILE"
        if command -v jq &> /dev/null; then
            APP_NAME=$(jq -r '.app.name // ""' "$APP_CONFIG_FILE")
            APP_VERSION=$(jq -r '.app.version // ""' "$APP_CONFIG_FILE")
            add_output "app-name=$APP_NAME"
            add_output "app-version=$APP_VERSION"
        fi
    fi

    echo "✅ App configuration loaded"
fi

echo ""
echo "📋 Step 4: Setting Node.js version..."
if [ -n "$NODE_VERSION" ]; then
    FINAL_NODE_VERSION="$NODE_VERSION"
    echo "Using Node.js version from input: $FINAL_NODE_VERSION"
elif [ "$LOAD_CONFIG" = "true" ] && [ -f "$GITHUB_OUTPUT" ] && grep -q "test-node-version" "$GITHUB_OUTPUT"; then
    FINAL_NODE_VERSION=$(grep "test-node-version" "$GITHUB_OUTPUT" | cut -d'=' -f2)
    echo "Using Node.js version from config: $FINAL_NODE_VERSION"
else
    FINAL_NODE_VERSION="24"
    echo "Using default Node.js version: $FINAL_NODE_VERSION"
fi
add_output "node-version=$FINAL_NODE_VERSION"

echo ""
echo "📋 Step 5: Setting up Node.js..."
if command -v nvm &> /dev/null || [ -s "$HOME/.nvm/nvm.sh" ]; then
    source "$HOME/.nvm/nvm.sh" 2>/dev/null || true
    nvm use "$FINAL_NODE_VERSION" 2>/dev/null || nvm install "$FINAL_NODE_VERSION"
    echo "✅ Node.js version set via nvm"
elif command -v node &> /dev/null; then
    CURRENT_VERSION=$(node --version | sed 's/v//')
    echo "Current Node.js version: $CURRENT_VERSION"
    echo "⚠️  Note: Install nvm to switch versions automatically"
else
    echo "⚠️  Warning: Node.js not found. Please install Node.js $FINAL_NODE_VERSION"
fi

echo ""
echo "📋 Step 6: Setting up npm 11.6.1..."
if command -v npm &> /dev/null; then
    npm install -g npm@11.6.1
    echo "✅ npm version: $(npm --version)"
else
    echo "⚠️  Warning: npm not found"
fi

echo ""
echo "📋 Step 7: Verifying package-lock.json..."
if [ ! -f package-lock.json ]; then
    echo "❌ Error: package-lock.json not found!"
    exit 1
fi
echo "✅ package-lock.json found!"
echo "   File size: $(wc -c < package-lock.json) bytes"

echo ""
echo "📋 Step 8: Rebuilding native dependencies..."
if command -v npm &> /dev/null; then
    npm rebuild
    echo "✅ Native dependencies rebuilt"
else
    echo "⚠️  Warning: npm not found, skipping rebuild"
fi

echo ""
echo "📋 Step 9: Installing dependencies..."
if command -v npm &> /dev/null; then
    if [ "$INSTALL_DEV_DEPS" = "true" ]; then
        echo "Installing all dependencies (including dev dependencies)"
        npm ci
    else
        echo "Installing production dependencies only"
        npm ci --omit=dev
    fi
    echo "✅ Dependencies installed"
else
    echo "⚠️  Warning: npm not found, skipping install"
fi

echo ""
echo "📋 Step 10: Node.js information..."
if command -v node &> /dev/null; then
    node --version
    npm --version
    echo "Node.js path: $(which node)"
    echo "npm path: $(which npm)"
else
    echo "⚠️  Warning: Node.js not found"
fi

echo ""
echo "✅ Action completed successfully!"
echo ""
echo "Outputs saved to: $GITHUB_OUTPUT"
echo "Environment variables saved to: $GITHUB_ENV"
echo ""
echo "To view outputs:"
echo "  cat $GITHUB_OUTPUT"

trap "rm -rf $OUTPUT_DIR" EXIT
