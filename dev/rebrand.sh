#!/usr/bin/env bash
# MTX dev rebrand: identity + apply-names (project name, owner, package id, scope, root name) from shell-scripts.md §2b
desc="Rename project, owner, package id, scope; apply to repo"
set -e

cd "$ROOT_"

GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

# Read existing config if present
EXISTING_APP_NAME=""
EXISTING_OWNER=""
EXISTING_PACKAGE_ID=""
EXISTING_SCOPE=""
EXISTING_ROOT_NAME=""
if [ -f "config/app.json" ]; then
  EXISTING_APP_NAME=$(jq -r '.app.name // ""' config/app.json 2>/dev/null || echo "")
  EXISTING_OWNER=$(jq -r '.app.owner // ""' config/app.json 2>/dev/null || echo "")
fi
if [ -f "package.json" ]; then
  EXISTING_ROOT_NAME=$(jq -r '.name // "app"' package.json 2>/dev/null || echo "app")
fi
if [ -f "targets/mobile/capacitor.config.ts" ]; then
  EXISTING_PACKAGE_ID=$(grep -Eo "appId:[[:space:]]*'[^']*'" targets/mobile/capacitor.config.ts 2>/dev/null | sed "s/appId: '\(.*\)'/\1/" | head -1 || echo "")
fi
if [ -f "shared/package.json" ]; then
  EXISTING_SCOPE=$(jq -r '.name // ""' shared/package.json 2>/dev/null | sed -n 's/^@\([^/]*\)\/.*/\1/p' || echo "")
fi

# Prompts (with defaults from existing)
read -rp "Project display name [${EXISTING_APP_NAME:-My Application}]: " PROJECT_NAME
PROJECT_NAME="${PROJECT_NAME:-${EXISTING_APP_NAME:-My Application}}"

read -rp "Owner (e.g. GitHub org/user) [${EXISTING_OWNER:-}]: " OWNER
OWNER="${OWNER:-$EXISTING_OWNER}"

read -rp "Package ID (reverse-DNS, e.g. com.example.app) [${EXISTING_PACKAGE_ID:-com.example.app}]: " PACKAGE_ID
PACKAGE_ID="${PACKAGE_ID:-${EXISTING_PACKAGE_ID:-com.example.app}}"

read -rp "NPM scope (without @) [${EXISTING_SCOPE:-app}]: " SCOPE_NEW
SCOPE_NEW="${SCOPE_NEW:-${EXISTING_SCOPE:-app}}"

read -rp "Root package name [${EXISTING_ROOT_NAME:-app}]: " ROOT_NAME_NEW
ROOT_NAME_NEW="${ROOT_NAME_NEW:-$EXISTING_ROOT_NAME}"

# Slug from project name
APP_SLUG=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/^-*\|-*$//g')
[ -z "$APP_SLUG" ] && APP_SLUG="app"

echo ""
echo -e "${CYAN}Applying names...${NC}"

mkdir -p config

# config/app.json
if [ -f "config/app.json" ]; then
  jq ".app.name = \"$PROJECT_NAME\" | .app.owner = \"$OWNER\" | .app.slug = \"$APP_SLUG\"" config/app.json > config/app.json.tmp && mv config/app.json.tmp config/app.json
else
  cat > config/app.json <<EOF
{
  "app": {
    "name": "$PROJECT_NAME",
    "owner": "$OWNER",
    "slug": "$APP_SLUG",
    "version": "1.0.0"
  }
}
EOF
fi
echo -e "${GREEN}✅ config/app.json${NC}"

# Root package.json
if [ -f "package.json" ]; then
  PROJECT_NAME="$PROJECT_NAME" ROOT_NAME_NEW="$ROOT_NAME_NEW" node -e "
const fs = require('fs');
const j = JSON.parse(fs.readFileSync('package.json', 'utf8'));
j.description = (process.env.PROJECT_NAME || '') + ' monorepo';
if (process.env.ROOT_NAME_NEW) j.name = process.env.ROOT_NAME_NEW;
fs.writeFileSync('package.json', JSON.stringify(j, null, 2) + '\n');
"
  echo -e "${GREEN}✅ package.json (name, description)${NC}"
fi

echo ""
echo -e "${CYAN}📦 npm install${NC}"
npm install

echo ""
echo -e "${GREEN}✅ Rebrand complete.${NC}"
echo "  App name: $PROJECT_NAME"
echo "  Owner: $OWNER"
echo "  Package ID: $PACKAGE_ID"
echo "  NPM scope: @$SCOPE_NEW"
echo "  Root package: $ROOT_NAME_NEW"
