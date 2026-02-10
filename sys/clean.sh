#!/usr/bin/env bash
# MTX sys clean: remove build artifacts (from shell-scripts.md §8)
desc="Remove build artifacts and generated files"
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

cd "$ROOT_"

echo -e "${BLUE}🧹 Project Clean${NC}"
echo "This will remove build artifacts and generated files."
echo ""

echo -e "${BLUE}📊 Calculating current size...${NC}"
BEFORE_SIZE=$(du -sh --exclude=node_modules --exclude=.git . 2>/dev/null | awk '{print $1}')
echo -e "Current size (excluding node_modules): ${YELLOW}$BEFORE_SIZE${NC}"
echo ""

read -p "Continue with clean? (y/N): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Clean cancelled.${NC}"
    exit 0
fi

echo ""
echo -e "${BLUE}🗑️  Starting clean...${NC}"
echo ""

remove_dir() {
    local dir="$1"
    local desc="$2"
    if [ -d "$dir" ]; then
        local size=$(du -sh "$dir" 2>/dev/null | awk '{print $1}')
        echo -e "${YELLOW}Removing $desc...${NC} ($size)"
        rm -rf "$dir"
        echo -e "${GREEN}✅ Removed $desc${NC}"
    else
        echo -e "${BLUE}⏭️  Skipping $desc (not found)${NC}"
    fi
}

remove_file() {
    local file="$1"
    local desc="$2"
    if [ -f "$file" ]; then
        local size=$(du -h "$file" 2>/dev/null | awk '{print $1}')
        echo -e "${YELLOW}Removing $desc...${NC} ($size)"
        rm -f "$file"
        echo -e "${GREEN}✅ Removed $desc${NC}"
    else
        echo -e "${BLUE}⏭️  Skipping $desc (not found)${NC}"
    fi
}

echo -e "${BLUE}━━━ Desktop Build Artifacts ━━━${NC}"
remove_dir "targets/desktop/release" "Desktop release builds"
remove_dir "targets/desktop/dist" "Desktop dist folder"
remove_dir "targets/desktop/build" "Desktop build folder"

echo ""
echo -e "${BLUE}━━━ Mobile Build Artifacts ━━━${NC}"
remove_dir "targets/mobile/android/app/build" "Android app build artifacts"
remove_dir "targets/mobile/android/.gradle" "Android Gradle cache"
remove_dir "targets/mobile/android/build" "Android build folder"
remove_dir "targets/mobile/ios/build" "iOS build folder"
remove_dir "targets/mobile/dist" "Mobile dist folder"

echo ""
echo -e "${BLUE}━━━ Server Build Artifacts ━━━${NC}"
remove_dir "targets/server/dist" "Server dist folder"
remove_dir "targets/server/src/db/generated" "Prisma generated files (will be regenerated on next build)"

echo ""
echo -e "${BLUE}━━━ Client Build Artifacts ━━━${NC}"
remove_dir "targets/client/dist" "Client dist folder"
remove_dir "targets/client/build" "Client build folder"

echo ""
echo -e "${BLUE}━━━ Backend Build Artifacts ━━━${NC}"
remove_dir "targets/backend/dist" "Backend dist folder"
remove_dir "targets/backend/build" "Backend build folder"
remove_dir "targets/backend-server/dist" "Backend-server dist folder"

echo ""
echo -e "${BLUE}━━━ Root Build Artifacts ━━━${NC}"
remove_dir "dist" "Root dist folder"

echo ""
echo -e "${BLUE}━━━ Terraform Artifacts ━━━${NC}"
remove_dir "terraform/.terraform" "Terraform provider binaries"
remove_file "terraform/terraform.tfstate" "Terraform state file"
remove_file "terraform/terraform.tfstate.backup" "Terraform state backup"
remove_file "terraform/tfplan" "Terraform plan file"
remove_file "terraform/.terraform.lock.hcl" "Terraform lock file"

echo ""
echo -e "${BLUE}━━━ Other Generated Files ━━━${NC}"
remove_dir ".railway" "Railway local config (will be recreated on next deploy)"
remove_dir ".cursor" "Cursor cache"

echo ""
echo -e "${BLUE}━━━ Package Build Artifacts ━━━${NC}"
remove_dir "application/dist" "Application dist folder"
remove_dir "application/build" "Application build folder"
remove_dir "shared/dist" "Shared dist folder"
remove_dir "shared/build" "Shared build folder"
remove_dir "engine/dist" "Engine dist folder"
remove_dir "engine/build" "Engine build folder"

echo ""
echo -e "${BLUE}━━━ Clean Summary ━━━${NC}"
AFTER_SIZE=$(du -sh --exclude=node_modules --exclude=.git . 2>/dev/null | awk '{print $1}')
echo -e "Size before: ${YELLOW}$BEFORE_SIZE${NC}"
echo -e "Size after:  ${GREEN}$AFTER_SIZE${NC}"
echo ""

echo -e "${GREEN}✅ Clean complete!${NC}"
echo ""
echo -e "${BLUE}💡 Note:${NC}"
echo "  - Prisma generated files will be regenerated on next 'npm run build:server'"
echo "  - Terraform providers will be downloaded on next 'terraform init'"
echo "  - Build artifacts will be regenerated on next build"
echo "  - Railway local config will be recreated on next deploy"
echo ""
