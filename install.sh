#!/usr/bin/env bash
desc="Install payload in current project and register routing in config/server.json"
nobanner=1
set -e

MTX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -d "$MTX_ROOT/includes" ]; then
  # shellcheck disable=SC1091
  for f in "$MTX_ROOT"/includes/*.sh; do source "$f"; done
fi

# Fallbacks when run outside mtx wrapper/bootstrap.
declare -F echoc >/dev/null || echoc() { local _c="$1"; shift || true; echo "$*"; }
declare -F info >/dev/null || info() { echo "[INFO] $*"; }
declare -F warn >/dev/null || warn() { echo "[WARN] $*" >&2; }
declare -F error >/dev/null || error() { echo "[ERROR] $*" >&2; }
declare -F success >/dev/null || success() { echo "[SUCCESS] $*"; }
declare -F mtx_run >/dev/null || mtx_run() { "$@"; }

slugify() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/^-*\|-*$//g'
}

trim() {
  local v="$1"
  v="${v#"${v%%[![:space:]]*}"}"
  v="${v%"${v##*[![:space:]]}"}"
  echo "$v"
}

find_project_root() {
  local walk
  walk="$(pwd)"
  while [ -n "$walk" ] && [ "$walk" != "/" ]; do
    if [ -f "$walk/package.json" ] && { [ -d "$walk/config" ] || [ -f "$walk/config/app.json" ] || [ -f "$walk/server.json" ]; }; then
      echo "$walk"
      return 0
    fi
    walk="$(dirname "$walk")"
  done
  return 1
}

show_help() {
  cat <<'EOF'
Usage:
  mtx install <payload-id>

Installs a payload package/source into the current project-bridge-style repo,
then updates config/server.json (or server.json) with an idempotent apps[] entry.
EOF
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  show_help
  exit 0
fi

PAYLOAD_ID="${1:-}"
if [ -z "$PAYLOAD_ID" ]; then
  error "Missing payload id."
  echo ""
  show_help
  exit 1
fi

PROJECT_ROOT="$(find_project_root || true)"
if [ -z "$PROJECT_ROOT" ]; then
  error "Could not find a project root from current directory."
  warn "Expected package.json plus config/server.json (or server.json) in current directory or a parent."
  exit 1
fi

CONFIG_PATH="$PROJECT_ROOT/config/server.json"
[ -f "$CONFIG_PATH" ] || CONFIG_PATH="$PROJECT_ROOT/server.json"

if [ ! -f "$CONFIG_PATH" ]; then
  info "No server config found; bootstrapping one now..."
  if [ -f "$PROJECT_ROOT/config/server-multi-app.example.json" ]; then
    cp "$PROJECT_ROOT/config/server-multi-app.example.json" "$PROJECT_ROOT/config/server.json"
    CONFIG_PATH="$PROJECT_ROOT/config/server.json"
    success "Created config/server.json from config/server-multi-app.example.json"
  elif [ -f "$PROJECT_ROOT/config/server.json.example" ]; then
    cp "$PROJECT_ROOT/config/server.json.example" "$PROJECT_ROOT/config/server.json"
    CONFIG_PATH="$PROJECT_ROOT/config/server.json"
    success "Created config/server.json from config/server.json.example"
  elif [ -f "$PROJECT_ROOT/server.json.example" ]; then
    cp "$PROJECT_ROOT/server.json.example" "$PROJECT_ROOT/server.json"
    CONFIG_PATH="$PROJECT_ROOT/server.json"
    success "Created server.json from server.json.example"
  else
    CONFIG_PATH="$PROJECT_ROOT/config/server.json"
    mkdir -p "$PROJECT_ROOT/config"
    printf '{\n  "apps": []\n}\n' > "$CONFIG_PATH"
    warn "No server config template found; created minimal config/server.json with apps[]."
  fi
fi

if ! command -v node >/dev/null 2>&1; then
  error "node is required."
  exit 1
fi

if ! command -v npm >/dev/null 2>&1; then
  error "npm is required."
  exit 1
fi

PAYLOAD_SLUG="$(slugify "$PAYLOAD_ID")"
PAYLOAD_SLUG="${PAYLOAD_SLUG#payload-}"
PAYLOAD_SLUG="${PAYLOAD_SLUG#org-}"
PAYLOAD_SLUG="${PAYLOAD_SLUG#template-}"
[ -n "$PAYLOAD_SLUG" ] || PAYLOAD_SLUG="app"

DEFAULT_NAME="$(echo "$PAYLOAD_ID" | sed 's/[-_]/ /g')"
DEFAULT_PACKAGE="@meanwhile-together/$PAYLOAD_ID"
if [[ "$PAYLOAD_ID" == @*/* ]]; then
  DEFAULT_PACKAGE="$PAYLOAD_ID"
fi

echo ""
echoc cyan "Install payload into project"
echoc dim "Project root: $PROJECT_ROOT"
echoc dim "Config file:  $CONFIG_PATH"
echo ""

read -rp "$(echo -e "${bold:-}Display name:${reset:-} [${DEFAULT_NAME}] ")" INPUT_NAME
INPUT_NAME="$(trim "${INPUT_NAME:-$DEFAULT_NAME}")"
[ -n "$INPUT_NAME" ] || INPUT_NAME="$DEFAULT_NAME"

read -rp "$(echo -e "${bold:-}Slug:${reset:-} [${PAYLOAD_SLUG}] ")" INPUT_SLUG
INPUT_SLUG="$(slugify "$(trim "${INPUT_SLUG:-$PAYLOAD_SLUG}")")"
[ -n "$INPUT_SLUG" ] || INPUT_SLUG="$PAYLOAD_SLUG"

echo ""
echo "Payload source type:"
echo "  1) package (npm install)"
echo "  2) path"
echo "  3) git"
read -rp "Choice [1]: " SRC_CHOICE
SRC_CHOICE="${SRC_CHOICE:-1}"

SOURCE_KIND="package"
SOURCE_VALUE=""
SOURCE_REF=""
case "$SRC_CHOICE" in
  1|package)
    SOURCE_KIND="package"
    read -rp "Package name [${DEFAULT_PACKAGE}]: " SOURCE_VALUE
    SOURCE_VALUE="$(trim "${SOURCE_VALUE:-$DEFAULT_PACKAGE}")"
    [ -n "$SOURCE_VALUE" ] || SOURCE_VALUE="$DEFAULT_PACKAGE"
    ;;
  2|path)
    SOURCE_KIND="path"
    read -rp "Path (relative to project root, or absolute): " SOURCE_VALUE
    SOURCE_VALUE="$(trim "$SOURCE_VALUE")"
    [ -n "$SOURCE_VALUE" ] || { error "Path source requires a value."; exit 1; }
    ;;
  3|git)
    SOURCE_KIND="git"
    read -rp "Git URL (https://... or git@...): " SOURCE_VALUE
    SOURCE_VALUE="$(trim "$SOURCE_VALUE")"
    [ -n "$SOURCE_VALUE" ] || { error "Git source requires URL."; exit 1; }
    read -rp "Git ref [main]: " SOURCE_REF
    SOURCE_REF="$(trim "${SOURCE_REF:-main}")"
    ;;
  *)
    error "Invalid source choice."
    exit 1
    ;;
esac

echo ""
read -rp "Set as default/fallback app for unmatched hosts? [y/N]: " MAKE_DEFAULT
MAKE_DEFAULT="$(echo "${MAKE_DEFAULT:-n}" | tr '[:upper:]' '[:lower:]')"

ROUTE_PATH_PREFIX=""
DOMAINS_CSV=""
if [ "$MAKE_DEFAULT" = "y" ] || [ "$MAKE_DEFAULT" = "yes" ]; then
  ROUTE_PATH_PREFIX=""
else
  read -rp "Route path prefix (empty for root, e.g. /portal): " ROUTE_PATH_PREFIX
  ROUTE_PATH_PREFIX="$(trim "$ROUTE_PATH_PREFIX")"
  if [ -n "$ROUTE_PATH_PREFIX" ] && [ "$ROUTE_PATH_PREFIX" != "/" ] && [[ "$ROUTE_PATH_PREFIX" != /* ]]; then
    ROUTE_PATH_PREFIX="/$ROUTE_PATH_PREFIX"
  fi
  [ "$ROUTE_PATH_PREFIX" = "/" ] && ROUTE_PATH_PREFIX=""
  read -rp "Domains/hosts (comma-separated, optional): " DOMAINS_CSV
  DOMAINS_CSV="$(trim "$DOMAINS_CSV")"
fi

read -rp "API prefix (blank = default /api/<slug>): " API_PREFIX
API_PREFIX="$(trim "$API_PREFIX")"
if [ -n "$API_PREFIX" ] && [[ "$API_PREFIX" != /* ]]; then
  API_PREFIX="/$API_PREFIX"
fi

if [ "$SOURCE_KIND" = "package" ]; then
  echo ""
  info "Installing package in $PROJECT_ROOT ..."
  (
    cd "$PROJECT_ROOT"
    mtx_run npm install "$SOURCE_VALUE"
  )
  success "Installed package: $SOURCE_VALUE"
fi

echo ""
info "Updating $CONFIG_PATH ..."

PAYLOAD_ID="$PAYLOAD_ID" \
APP_NAME="$INPUT_NAME" \
APP_SLUG="$INPUT_SLUG" \
SOURCE_KIND="$SOURCE_KIND" \
SOURCE_VALUE="$SOURCE_VALUE" \
SOURCE_REF="$SOURCE_REF" \
ROUTE_PATH_PREFIX="$ROUTE_PATH_PREFIX" \
DOMAINS_CSV="$DOMAINS_CSV" \
API_PREFIX="$API_PREFIX" \
CONFIG_PATH="$CONFIG_PATH" \
node <<'EOF'
const fs = require("fs");

const configPath = process.env.CONFIG_PATH;
const payloadId = process.env.PAYLOAD_ID;
const appName = process.env.APP_NAME;
const appSlug = process.env.APP_SLUG;
const sourceKind = process.env.SOURCE_KIND;
const sourceValue = process.env.SOURCE_VALUE;
const sourceRef = process.env.SOURCE_REF;
const routePathPrefix = process.env.ROUTE_PATH_PREFIX || "";
const domainsCsv = process.env.DOMAINS_CSV || "";
const apiPrefix = process.env.API_PREFIX || "";

const raw = fs.readFileSync(configPath, "utf8");
const json = JSON.parse(raw);

if (!json || typeof json !== "object") {
  throw new Error("Invalid server config JSON.");
}

const appsKey = Array.isArray(json.apps) ? "apps" : (Array.isArray(json.payloads) ? "payloads" : "apps");
if (!Array.isArray(json[appsKey])) json[appsKey] = [];

let source;
if (sourceKind === "package") {
  source = { package: sourceValue };
} else if (sourceKind === "path") {
  source = { path: sourceValue };
} else if (sourceKind === "git") {
  source = { git: { url: sourceValue, ref: sourceRef || "main" } };
} else {
  throw new Error(`Unsupported source kind: ${sourceKind}`);
}

const domainList = domainsCsv
  .split(",")
  .map((s) => s.trim().toLowerCase())
  .filter(Boolean);

const nextEntry = {
  id: payloadId,
  name: appName,
  slug: appSlug,
  source
};

nextEntry.pathPrefix = routePathPrefix;
if (domainList.length > 0) nextEntry.domains = domainList;
if (apiPrefix) nextEntry.apiPrefix = apiPrefix;

const idx = json[appsKey].findIndex((e) => e && typeof e === "object" && e.id === payloadId);
if (idx >= 0) {
  const prev = json[appsKey][idx] || {};
  const merged = {
    ...prev,
    ...nextEntry,
    source: nextEntry.source,
  };
  if (domainList.length === 0) delete merged.domains;
  if (!apiPrefix) delete merged.apiPrefix;
  json[appsKey][idx] = merged;
} else {
  json[appsKey].push(nextEntry);
}

fs.writeFileSync(configPath, JSON.stringify(json, null, 2) + "\n");
EOF

success "Updated payload entry '$PAYLOAD_ID' in $(basename "$CONFIG_PATH")"
echo ""
echo "Next steps:"
echo "  1) Build host/server:"
echo "     npm run build:server"
echo "  2) Restart local server or redeploy:"
echo "     npm run dev:server"
echo "     # or: mtx deploy staging|production"
echo "  3) Verify routes:"
echo "     - UI route host/path matches domains + pathPrefix"
echo "     - API route uses ${API_PREFIX:-/api/$INPUT_SLUG} (or payload default)"
