#!/usr/bin/env bash
# MTX project rebrand: identity + apply-names (project name, owner, package id, scope, root name)
# Applies to config/app.json, package.json, client/desktop/mobile targets, Capacitor, electron-builder, NPM scope.
desc="Rename project, owner, package id, scope; apply to repo"
set -e

# Requires a Project B app (precond 01-is-projectb sets MTX_IS_PROJECTB=1)
if [[ -z "${MTX_IS_PROJECTB:-}" ]]; then
  echo "❌ Not a Project B app (missing config/app.json with owner/slug). Run rebrand from a project directory (e.g. project-b)." >&2
  exit 1
fi

# Ensure we run from project root (directory containing config/app.json) so find/list paths are correct
PROJECT_ROOT=""
if [[ -f "config/app.json" ]]; then
  PROJECT_ROOT="$(pwd)"
fi
if [[ -z "$PROJECT_ROOT" ]]; then
  # Try parent (e.g. workspace root with project-bridge as subdir)
  for d in . .. ../project-bridge; do
    if [[ -f "${d}/config/app.json" ]]; then
      PROJECT_ROOT="$(cd "$d" && pwd)"
      break
    fi
  done
fi
if [[ -n "$PROJECT_ROOT" ]]; then
  cd "$PROJECT_ROOT" || exit 1
fi

GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

# Helpers (same pattern as project-b scripts/setup.sh apply-names)
write_json_field() {
  local file="$1" field="$2" value="$3"
  [ -f "$file" ] || return 0
  node -e "
const fs=require('fs');
const f='$file';
const j=JSON.parse(fs.readFileSync(f,'utf8'));
const keys='$field'.split('.');
let o=j;
for(let i=0;i<keys.length-1;i++){ const k=keys[i]; if(typeof o[k]!=='object'||o[k]==null) o[k]={}; o=o[k]; }
o[keys[keys.length-1]]='$value';
fs.writeFileSync(f,JSON.stringify(j,null,2)+'\n');
" 2>/dev/null || true
}

sed_inplace() {
  local pattern="$1" file="$2"
  [ -f "$file" ] || return 0
  if sed --version 2>/dev/null | grep -q GNU; then
    sed -i "$pattern" "$file" 2>/dev/null || true
  else
    sed -i '' "$pattern" "$file" 2>/dev/null || true
  fi
}

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

# Client/desktop/mobile package.json and configs (apply-names from project-b setup.sh)
CLIENT_PKG="targets/client/package.json"
DESKTOP_PKG="targets/desktop/package.json"
CAP_CONFIG="targets/mobile/capacitor.config.ts"
ELECTRON_BUILDER="targets/desktop/electron-builder.json"

if [ -f "$CLIENT_PKG" ]; then
  write_json_field "$CLIENT_PKG" description "$PROJECT_NAME web client"
  echo -e "${GREEN}✅ $CLIENT_PKG (description)${NC}"
fi
if [ -f "$DESKTOP_PKG" ]; then
  write_json_field "$DESKTOP_PKG" build.productName "$PROJECT_NAME"
  write_json_field "$DESKTOP_PKG" build.appId "$PACKAGE_ID"
  echo -e "${GREEN}✅ $DESKTOP_PKG (build.productName, build.appId)${NC}"
fi
if [ -f "$ELECTRON_BUILDER" ]; then
  EB="$ELECTRON_BUILDER" PKG="$PACKAGE_ID" PNAME="$PROJECT_NAME" node -e "
const fs=require('fs');
const f=process.env.EB;
const j=JSON.parse(fs.readFileSync(f,'utf8'));
j.appId=process.env.PKG;
j.productName=process.env.PNAME;
fs.writeFileSync(f,JSON.stringify(j,null,2)+'\n');
" 2>/dev/null || true
  echo -e "${GREEN}✅ $ELECTRON_BUILDER (appId, productName)${NC}"
fi
if [ -f "$CAP_CONFIG" ]; then
  sed_inplace "s|appId: '[^']*'|appId: '$PACKAGE_ID'|g" "$CAP_CONFIG"
  sed_inplace "s|appName: '[^']*'|appName: '$PROJECT_NAME'|g" "$CAP_CONFIG"
  echo -e "${GREEN}✅ $CAP_CONFIG (appId, appName)${NC}"
fi

# NPM scope: discover current scope from repo (same as project-b setup.sh) when not from shared
if [ -n "$EXISTING_SCOPE" ]; then
  SCOPE_OLD="$EXISTING_SCOPE"
else
  SCOPE_OLD=$(node -e "
try {
  const s = require('./shared/package.json').name;
  if (typeof s === 'string' && s.startsWith('@') && s.includes('/')) {
    console.log(s.split('/')[0].slice(1));
    process.exit(0);
  }
} catch (e) {}
try {
  const r = require('./package.json').name;
  if (typeof r === 'string') {
    console.log(r.startsWith('@') ? r.split('/')[0].slice(1) : r);
    process.exit(0);
  }
} catch (e) {}
console.log('app');
" 2>/dev/null || echo "app")
fi
if [ -n "$SCOPE_NEW" ] && [ "$SCOPE_NEW" != "$SCOPE_OLD" ]; then
  echo -e "\n${CYAN}♻️  Scope: @$SCOPE_OLD → @$SCOPE_NEW${NC}"
  update_pkg_scope_json() {
    local file="$1" from="$2" to="$3"
    [ -f "$file" ] || return 0
    FILE="$file" FROM="$from" TO="$to" node -e "
const fs=require('fs');
const f=process.env.FILE;
const j=JSON.parse(fs.readFileSync(f,'utf8'));
const from=process.env.FROM, to=process.env.TO;
const rename=(name)=>typeof name==='string'&&name.startsWith('@'+from+'/')?'@'+to+name.slice(from.length+1):name;
if(j.name) j.name=rename(j.name);
const bump=(obj)=>obj?Object.fromEntries(Object.entries(obj).map(([k,v])=>[rename(k),v])):obj;
j.dependencies=bump(j.dependencies);
j.devDependencies=bump(j.devDependencies);
if(j.peerDependencies) j.peerDependencies=bump(j.peerDependencies);
if(j.optionalDependencies) j.optionalDependencies=bump(j.optionalDependencies);
let out=JSON.stringify(j,null,2)+'\n';
out=out.replace(new RegExp('@'+from.replace(/[.*+?^\${}()|[\]\\\\]/g,'\\\\$&')+'/','g'), '@'+to+'/');
fs.writeFileSync(f,out);
" 2>/dev/null || true
  }
  # Update every package.json in the repo (not just a fixed list)
  while IFS= read -r -d '' pkg; do
    update_pkg_scope_json "$pkg" "$SCOPE_OLD" "$SCOPE_NEW" || true
  done < <(find . -type f -name "package.json" -not -path "*/node_modules/*" -print0 2>/dev/null || true)
  # Replace scope in all source, config, docs, and workflow files
  while IFS= read -r -d '' f; do
    [ -f "$f" ] && sed_inplace "s|@${SCOPE_OLD}/|@${SCOPE_NEW}/|g" "$f"
  done < <(find . -type f \( -name "*.ts" -o -name "*.tsx" -o -name "*.mts" -o -name "*.cts" -o -name "*.js" -o -name "*.jsx" -o -name "*.json" -o -name "*.mjs" -o -name "*.cjs" -o -name "*.md" -o -name "*.html" -o -name "*.yml" -o -name "*.yaml" \) -not -path "*/node_modules/*" -not -path "*/dist/*" -not -path "*/build/*" -not -path "*/.git/*" -print0 2>/dev/null || true)
  echo -e "${GREEN}✅ Scope updated; re-running npm install${NC}"
  npm install
fi

# Capacitor: add platforms (Node >= 20) and optional cap sync (same flow as project-b setup.sh)
add_platform_if_needed() {
  local platform="$1"
  local dir="targets/mobile/$platform"
  if [[ -d "$dir" ]]; then
    echo -e "${GREEN}✅ Capacitor platform already added: $platform${NC}"
    return 0
  fi
  echo -e "${CYAN}➕ Adding Capacitor platform: $platform${NC}"
  (cd targets/mobile && npx cap add "$platform")
}
NODE_MAJOR=$(node -v 2>/dev/null | sed -n 's/^v\([0-9]*\).*/\1/p' || echo "0")
if [[ -f "targets/mobile/capacitor.config.ts" ]] && [[ "${NODE_MAJOR:-0}" -ge 20 ]]; then
  read -rp "Capacitor platforms to add (android, ios, or both) [android]: " CAP_PLATFORMS_RAW
  CAP_PLATFORMS_RAW="${CAP_PLATFORMS_RAW:-android}"
  for p in $(echo "$CAP_PLATFORMS_RAW" | tr ',' ' '); do
    pp=$(echo "$p" | tr '[:upper:]' '[:lower:]' | xargs)
    case "$pp" in
      android|ios) add_platform_if_needed "$pp" ;;
      "") ;;
      *) echo -e "${CYAN}⚠️  Unknown platform: $pp (skipping)${NC}" ;;
    esac
  done
  read -rp "Run Capacitor sync (build packages + mobile + cap sync)? (y/N): " DO_SYNC
  if [[ "${DO_SYNC:-n}" =~ ^[yY] ]]; then
    echo -e "\n${CYAN}🏗️  Building packages...${NC}"
    npm run build:packages 2>/dev/null || npm run build 2>/dev/null || true
    if [[ -f "targets/mobile/package.json" ]]; then
      echo -e "\n${CYAN}🏗️  Building mobile...${NC}"
      (cd targets/mobile && npm run build) || true
    fi
    if [[ -d "targets/mobile/dist" ]]; then
      echo -e "\n${CYAN}🔄 Capacitor sync...${NC}"
      (cd targets/mobile && npx cap sync) || true
    fi
  fi
elif [[ -f "targets/mobile/capacitor.config.ts" ]] && [[ "${NODE_MAJOR:-0}" -lt 20 ]]; then
  echo -e "${CYAN}⚠️  Node $(node -v) < 20. Skipping Capacitor platform add/sync.${NC}"
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
