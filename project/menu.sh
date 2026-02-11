#!/usr/bin/env bash
# MTX project menu: project helper (versions, build, dev servers, Android)
desc="Project helper menu: versions, build, dev servers, Android"
nocapture=1
set -e

NODE_BIN=$(command -v node || true)
NPM_BIN=$(command -v npm || true)

if [[ -z "${NODE_BIN}" ]]; then
  echo "❌ Node.js is required. Please install Node.js >= 18." >&2
  exit 1
fi
if [[ -z "${NPM_BIN}" ]]; then
  echo "❌ npm is required. Please install npm >= 8." >&2
  exit 1
fi

CLIENT_PKG="targets/client/package.json"
DESKTOP_PKG="targets/desktop/package.json"
MOBILE_PKG="targets/mobile/package.json"
ROOT_PKG="package.json"
APP_JSON="config/app.json"
DEPLOY_JSON="config/deploy.json"

ensure_file() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo "❌ Missing file: $path" >&2
    exit 1
  fi
}

read_json_field() {
  local file="$1"; shift
  local field="$1"; shift
  node -e "const fs=require('fs');const j=JSON.parse(fs.readFileSync('$file','utf8'));const v='$field'.split('.').reduce((a,k)=>a?.[k], j); if(v==null){process.exit(2)}; console.log(String(v))" 2>/dev/null || true
}

write_json_field() {
  local file="$1"; shift
  local field="$1"; shift
  local value="$1"; shift
  node -e "const fs=require('fs');const f='$file';const j=JSON.parse(fs.readFileSync(f,'utf8'));const keys='$field'.split('.');let o=j;for(let i=0;i<keys.length-1;i++){const k=keys[i];if(typeof o[k]!=='object'||o[k]==null){o[k]={}};o=o[k]}o[keys[keys.length-1]]='$value';fs.writeFileSync(f,JSON.stringify(j,null,2)+'\n')"
}

is_semver() {
  local v="$1"
  [[ "$v" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$ ]]
}

# Read JSON with jq (for arrays and conditions). Use read_json_field for simple paths without jq.
read_json() {
  local file="$1" expr="$2"
  command -v jq &>/dev/null && [ -f "$file" ] && jq -r "$expr" "$file" 2>/dev/null || true
}

# Menu card width (match mockup); pipe|content| no extra space so walls align with +
MENU_W=82
INNER_W=80
ENV_COL_W=39
VER_COL_W=40

# Header: owner / app-name
get_framework_line() {
  local owner slug
  owner=$(read_json "$APP_JSON" "(.app.owner // \"\")")
  slug=$(read_json "$APP_JSON" "(.app.slug // \"\")")
  [ -z "$owner" ] && owner=$(read_json_field "$APP_JSON" app.owner 2>/dev/null || true)
  [ -z "$slug" ] && slug=$(read_json_field "$APP_JSON" app.slug 2>/dev/null || true)
  if [ -n "$owner" ] && [ -n "$slug" ]; then
    printf "%b%s/%s%b" "${green:-}" "$owner" "$slug" "${reset:-}"
  else
    printf "%b-%b" "${dim:-}" "${reset:-}"
  fi
}

get_versions_line() {
  local root_v
  root_v=$(read_json_field "$ROOT_PKG" version 2>/dev/null || true)
  printf "v%s" "${root_v:-?}"
}

# App name (slug) for env rows
get_app_slug() {
  local slug
  slug=$(read_json "$APP_JSON" "(.app.slug // \"\")")
  [ -z "$slug" ] && slug=$(read_json_field "$APP_JSON" app.slug 2>/dev/null || true)
  printf "%s" "${slug:-app-name}"
}

# Staging: app + backend checkboxes [x] or [ ] (ASCII)
get_staging_app_ok() {
  [ ! -f "$DEPLOY_JSON" ] && printf "0" && return
  local proj_id has_stg apps_count
  proj_id=$(read_json "$DEPLOY_JSON" "(.projectId // \"\")")
  has_stg=$(read_json "$DEPLOY_JSON" "(.staging != null) | tostring" 2>/dev/null || echo "false")
  apps_count=$(read_json "$DEPLOY_JSON" "(.apps // [] | length)" 2>/dev/null || echo "0")
  [ -n "$proj_id" ] && [ "$has_stg" = "true" ] && [ "$apps_count" -gt 0 ] 2>/dev/null && printf "1" || printf "0"
}

get_staging_backend_ok() {
  [ ! -f "$DEPLOY_JSON" ] && printf "0" && return
  local proj_id has_stg
  proj_id=$(read_json "$DEPLOY_JSON" "(.projectId // \"\")")
  has_stg=$(read_json "$DEPLOY_JSON" "(.staging != null) | tostring" 2>/dev/null || echo "false")
  [ -n "$proj_id" ] && [ "$has_stg" = "true" ] && printf "1" || printf "0"
}

get_production_app_ok() {
  [ ! -f "$DEPLOY_JSON" ] && printf "0" && return
  local proj_id has_prd apps_count
  proj_id=$(read_json "$DEPLOY_JSON" "(.projectId // \"\")")
  has_prd=$(read_json "$DEPLOY_JSON" "(.production != null) | tostring" 2>/dev/null || echo "false")
  apps_count=$(read_json "$DEPLOY_JSON" "(.apps // [] | length)" 2>/dev/null || echo "0")
  [ -n "$proj_id" ] && [ "$has_prd" = "true" ] && [ "$apps_count" -gt 0 ] 2>/dev/null && printf "1" || printf "0"
}

get_production_backend_ok() {
  [ ! -f "$DEPLOY_JSON" ] && printf "0" && return
  local proj_id has_prd
  proj_id=$(read_json "$DEPLOY_JSON" "(.projectId // \"\")")
  has_prd=$(read_json "$DEPLOY_JSON" "(.production != null) | tostring" 2>/dev/null || echo "false")
  [ -n "$proj_id" ] && [ "$has_prd" = "true" ] && printf "1" || printf "0"
}

# Version strings for Repo, Web, Desktop, Mobile (ASCII only for alignment)
get_repo_ver() { printf "%s" "$(read_json_field "$ROOT_PKG" version 2>/dev/null || echo "-")"; }
get_web_ver() { printf "%s" "$(read_json_field "$CLIENT_PKG" version 2>/dev/null || echo "-")"; }
get_desktop_ver() { printf "%s" "$(read_json_field "$DESKTOP_PKG" version 2>/dev/null || echo "-")"; }
get_mobile_ver() { printf "%s" "$(read_json_field "$MOBILE_PKG" version 2>/dev/null || echo "-")"; }

# Draw the main menu card (mockup layout)
draw_menu_card() {
  [ -t 1 ] && clear
  local w=$((MENU_W - 2))
  local app_slug stg_app stg_back prd_app prd_back
  app_slug=$(get_app_slug)
  stg_app=$(get_staging_app_ok)
  stg_back=$(get_staging_backend_ok)
  prd_app=$(get_production_app_ok)
  prd_back=$(get_production_backend_ok)

  # ASCII checkboxes so all terminals align (no Unicode)
  local cb_ok="[x]" cb_no="[ ]"
  local s_app s_back p_app p_back
  [ "$stg_app" = "1" ] && s_app="$cb_ok" || s_app="$cb_no"
  [ "$stg_back" = "1" ] && s_back="$cb_ok" || s_back="$cb_no"
  [ "$prd_app" = "1" ] && p_app="$cb_ok" || p_app="$cb_no"
  [ "$prd_back" = "1" ] && p_back="$cb_ok" || p_back="$cb_no"

  local border_hr
  border_hr=$(printf '%*s' "$w" "" | tr ' ' '-')
  local env_dash ver_dash act_dash
  env_dash=$(printf '%*s' "$ENV_COL_W" "" | tr ' ' '-')
  ver_dash=$(printf '%*s' "$VER_COL_W" "" | tr ' ' '-')
  act_dash=$(printf '%*s' "$INNER_W" "" | tr ' ' '-')

  # ASCII box: +--+ and | (no space after | so walls align with +)
  printf "%b+%s+%b\n" "${cyan:-}" "$border_hr" "${reset:-}"
  printf "|%-*s|\n" "$INNER_W" "Dev Helper . $(get_framework_line) . $(get_versions_line)"
  printf "%b+%s+%b\n" "${cyan:-}" "$border_hr" "${reset:-}"
  printf "|%-*s|%-*s|\n" "$ENV_COL_W" "ENVIRONMENTS" "$VER_COL_W" "VERSIONS"
  printf "|%-*s|%-*s|\n" "$ENV_COL_W" "$env_dash" "$VER_COL_W" "$ver_dash"
  printf "|%-*s|%-*s|\n" "$ENV_COL_W" "staging       $app_slug       $s_app" "$VER_COL_W" "Repo:    v$(get_repo_ver)"
  printf "|%-*s|%-*s|\n" "$ENV_COL_W" "  - backend-staging         $s_back" "$VER_COL_W" "Web:     v$(get_web_ver)"
  printf "|%-*s|%-*s|\n" "$ENV_COL_W" "" "$VER_COL_W" "Desktop: v$(get_desktop_ver)"
  printf "|%-*s|%-*s|\n" "$ENV_COL_W" "production    $app_slug       $p_app" "$VER_COL_W" "Mobile:  v$(get_mobile_ver)"
  printf "|%-*s|%-*s|\n" "$ENV_COL_W" "  - backend-production      $p_back" "$VER_COL_W" ""
  printf "%b+%s+%b\n" "${cyan:-}" "$border_hr" "${reset:-}"
  printf "|%-*s|\n" "$INNER_W" "ACTIONS"
  printf "|%-*s|\n" "$INNER_W" "$act_dash"
  local act_col=$(( INNER_W / 2 ))
  printf "|%-*s%-*s|\n" "$act_col" "1) Set web version" "$act_col" "2) Set desktop version"
  printf "|%-*s%-*s|\n" "$act_col" "3) Set mobile version" "$act_col" "4) Set ALL versions"
  printf "|%-*s%-*s|\n" "$act_col" "5) Build..." "$act_col" "6) Dev (foreground)..."
  printf "|%-*s%-*s|\n" "$act_col" "7) Android helpers..." "$act_col" "8) Quit"
  printf "%b+%s+%b\n" "${cyan:-}" "$border_hr" "${reset:-}"
}

set_version() {
  local target="$1"; local version="$2"
  if ! is_semver "$version"; then
    echo "❌ Invalid semver: $version (expected X.Y.Z)" >&2
    return 1
  fi
  case "$target" in
    web)
      ensure_file "$CLIENT_PKG"; write_json_field "$CLIENT_PKG" version "$version" ;;
    desktop)
      ensure_file "$DESKTOP_PKG"; write_json_field "$DESKTOP_PKG" version "$version" ;;
    mobile)
      ensure_file "$MOBILE_PKG"; write_json_field "$MOBILE_PKG" version "$version" ;;
    all)
      ensure_file "$ROOT_PKG"; ensure_file "$CLIENT_PKG"; ensure_file "$DESKTOP_PKG"; ensure_file "$MOBILE_PKG"
      write_json_field "$ROOT_PKG" version "$version"
      write_json_field "$CLIENT_PKG" version "$version"
      write_json_field "$DESKTOP_PKG" version "$version"
      write_json_field "$MOBILE_PKG" version "$version" ;;
    *)
      echo "❌ Unknown target: $target (expected web|desktop|mobile|all)" >&2; return 1 ;;
  esac
  echo "✅ Set $target version to $version"
}

# Draw a submenu card (title + two-column options); ASCII only
draw_submenu() {
  local title="$1" opts="$2"  # opts = "1) Label|2) Label|..." (pairs separated by |)
  local col_w=$(( (MENU_W - 4) / 2 )) max_content=$((MENU_W - 4)) w=$((MENU_W - 2))
  [ -t 1 ] && clear
  local border_hr
  border_hr=$(printf '%*s' "$w" "" | tr ' ' '-')
  printf "%b+%s+%b\n" "${cyan:-}" "$border_hr" "${reset:-}"
  printf "| %-*s |\n" "$max_content" "$title"
  printf "%b+%s+%b\n" "${cyan:-}" "$border_hr" "${reset:-}"
  local i=0 left= right=
  while IFS='|' read -r part; do
    [ -z "$part" ] && continue
    if [ $((i % 2)) -eq 0 ]; then left="$part"; else right="$part"; printf "| %-*s %-*s |\n" "$col_w" "$left" "$col_w" "$right"; fi
    i=$((i+1))
  done <<< "$(echo "$opts" | tr '|' '\n')"
  [ $((i % 2)) -eq 1 ] && printf "| %-*s %-*s |\n" "$col_w" "$left" "$col_w" ""
  printf "%b+%s+%b\n" "${cyan:-}" "$border_hr" "${reset:-}"
}

build_menu() {
  draw_submenu "Build" "1) Build web (vite)|2) Build desktop (electron)|3) Build Android|4) Build iOS|5) Build servers|6) Build all|7) Back"
  echo ""; color yellow "Select (1-7): "; read -r choice
  case "$choice" in
    1) mtx_run "$0" compile vite ;;
    2) mtx_run "$0" compile electron ;;
    3) mtx_run "$0" compile android ;;
    4) mtx_run "$0" compile ios ;;
    5) mtx_run "$0" compile servers ;;
    6) mtx_run "$0" compile ;;
    *) return ;;
  esac
}

dev_menu() {
  draw_submenu "Dev (foreground)" "1) Dev server only|2) Dev web (client)|3) Dev desktop|4) Dev mobile (vite)|5) Dev all (server+client+desktop)|6) Back"
  echo ""; color yellow "Select (1-6): "; read -r choice
  case "$choice" in
    1) mtx_run npm run dev:server ;;
    2) mtx_run npm run dev:client ;;
    3) mtx_run npm run dev:desktop ;;
    4) mtx_run npm run dev:mobile ;;
    5) mtx_run npm run dev:all ;;
    *) return ;;
  esac
}

android_menu() {
  draw_submenu "Android" "1) Build debug APK|2) Build APK + install via ADB|3) Install last APK via ADB|4) Run with Capacitor (Android Studio)|5) Back"
  echo ""; color yellow "Select (1-5): "; read -r choice
  case "$choice" in
    1)
      mtx_run "$0" compile android-debug
      ;;
    2)
      mtx_run "$0" compile android-debug
      APK_PATH=$(npm run -s find:apk 2>/dev/null | tail -n 1 || true)
      if [[ -z "$APK_PATH" ]]; then echo "❌ APK not found"; return; fi
      if ! command -v adb >/dev/null 2>&1; then echo "❌ adb is not installed or not in PATH"; return; fi
      if adb install --help 2>&1 | grep -q "--streaming"; then
        adb install --streaming -r "$APK_PATH"
      else
        adb install -r "$APK_PATH"
      fi
      ;;
    3)
      APK_PATH=$(npm run -s find:apk 2>/dev/null | tail -n 1 || true)
      if [[ -z "$APK_PATH" ]]; then echo "❌ APK not found"; return; fi
      if ! command -v adb >/dev/null 2>&1; then echo "❌ adb is not installed or not in PATH"; return; fi
      if adb install --help 2>&1 | grep -q "--streaming"; then
        adb install --streaming -r "$APK_PATH"
      else
        adb install -r "$APK_PATH"
      fi
      ;;
    4)
      mtx_run bash -c 'cd targets/mobile && npx cap run android'
      ;;
    *) return ;;
  esac
}

main_menu() {
  while true; do
    draw_menu_card
    echo ""
    color yellow "Select (1-8): "; read -r ans
    case "$ans" in
      1) read -rp "New web version (X.Y.Z): " v; [[ -z "$v" ]] || set_version web "$v" ;;
      2) read -rp "New desktop version (X.Y.Z): " v; [[ -z "$v" ]] || set_version desktop "$v" ;;
      3) read -rp "New mobile version (X.Y.Z): " v; [[ -z "$v" ]] || set_version mobile "$v" ;;
      4) read -rp "New ALL version (X.Y.Z): " v; [[ -z "$v" ]] || set_version all "$v" ;;
      5) build_menu ;;
      6) dev_menu ;;
      7) android_menu ;;
      8|q|Q) echoc green "Bye"; exit 0 ;;
      *) warn "Unknown option (choose 1-8)" ;;
    esac
  done
}

main_menu
