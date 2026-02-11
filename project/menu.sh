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

# Menu card width (one horizontal "page")
MENU_W=72

# Build one-line summary of framework + deploy + versions for the menu header/status
get_framework_line() {
  local owner slug
  owner=$(read_json "$APP_JSON" "(.app.owner // \"\")")
  slug=$(read_json "$APP_JSON" "(.app.slug // \"\")")
  [ -z "$owner" ] && owner=$(read_json_field "$APP_JSON" app.owner 2>/dev/null || true)
  [ -z "$slug" ] && slug=$(read_json_field "$APP_JSON" app.slug 2>/dev/null || true)
  if [ -n "$owner" ] && [ -n "$slug" ]; then
    printf "%b%s / %s%b" "${green:-}" "$owner" "$slug" "${reset:-}"
  else
    printf "%bNot Project B%b" "${red:-}" "${reset:-}"
  fi
}

get_deploy_line() {
  if [ ! -f "$DEPLOY_JSON" ]; then
    printf "railway-staging Back ☐ Apps ☐  railway-production Back ☐ Apps ☐"
    return
  fi
  local proj_id has_stg has_prd stg_back stg_apps prd_back prd_apps
  local has_railway apps_count
  proj_id=$(read_json "$DEPLOY_JSON" "(.projectId // \"\")")
  has_stg=$(read_json "$DEPLOY_JSON" "(.staging != null) | tostring" 2>/dev/null || echo "false")
  has_prd=$(read_json "$DEPLOY_JSON" "(.production != null) | tostring" 2>/dev/null || echo "false")
  has_railway=$(read_json "$DEPLOY_JSON" "(.platform // [] | index(\"railway\") != null) | tostring" 2>/dev/null || echo "false")
  apps_count=$(read_json "$DEPLOY_JSON" "(.apps // [] | length)" 2>/dev/null || echo "0")
  # Each env: Back ✅ if projectId + env block; Apps ✅ if .apps has entries
  [ -n "$proj_id" ] && [ "$has_stg" = "true" ] && stg_back=1 || stg_back=
  [ -n "$proj_id" ] && [ "$has_prd" = "true" ] && prd_back=1 || prd_back=
  [ "$apps_count" -gt 0 ] 2>/dev/null && stg_apps=1 || stg_apps=
  [ "$apps_count" -gt 0 ] 2>/dev/null && prd_apps=1 || prd_apps=
  if [ "$has_railway" = "true" ]; then
    local sb sa pb pa
    [ -n "$stg_back" ] && sb="✅" || sb="☐"
    [ -n "$stg_apps" ] && sa="✅" || sa="☐"
    [ -n "$prd_back" ] && pb="✅" || pb="☐"
    [ -n "$prd_apps" ] && pa="✅" || pa="☐"
    printf "%brailway-staging%b Back %s Apps %s  %brailway-production%b Back %s Apps %s" \
      "${dim:-}" "${reset:-}" "$sb" "$sa" "${dim:-}" "${reset:-}" "$pb" "$pa"
  else
    printf "railway-staging Back ☐ Apps ☐  railway-production Back ☐ Apps ☐"
  fi
}

get_versions_line() {
  local root_v web_v desk_v mob_v
  root_v=$(read_json_field "$ROOT_PKG" version 2>/dev/null || true)
  web_v=$(read_json_field "$CLIENT_PKG" version 2>/dev/null || true)
  desk_v=$(read_json_field "$DESKTOP_PKG" version 2>/dev/null || true)
  mob_v=$(read_json_field "$MOBILE_PKG" version 2>/dev/null || true)
  # Compact: if all same, show once; else repo · web · desk · mob
  if [ "${root_v:-x}" = "${web_v:-y}" ] && [ "${root_v:-x}" = "${desk_v:-z}" ] && [ "${root_v:-x}" = "${mob_v:-w}" ]; then
    printf "v %s" "${root_v:-—}"
  else
    printf "v %s · %s · %s · %s" "${root_v:-—}" "${web_v:-—}" "${desk_v:-—}" "${mob_v:-—}"
  fi
}

# Truncate or pad to width; strip newlines (for menu card lines)
menu_fit() {
  local w="$1" s="$2"
  s=${s//$'\n'/ }
  [ "${#s}" -gt "$w" ] && s="${s:0:$w}"
  printf "%-*s" "$w" "$s"
}

# Draw the main menu card (one screen, horizontal feel)
draw_menu_card() {
  [ -t 1 ] && clear
  local top_hr line content max_content=$((MENU_W - 4))
  top_hr=$(printf '╔%*s╗' "$((MENU_W-2))" "" | tr ' ' '═')
  printf "%b%s%b\n" "${cyan:-}" "$top_hr" "${reset:-}"
  content="Dev Helper · $(get_framework_line) · $(get_versions_line)"
  line=$(printf "║ %-*s ║" "$max_content" "$(menu_fit "$max_content" "$content")")
  printf "%b%s%b\n" "${bold:-}" "$line" "${reset:-}"
  printf "%b╠%*s╣%b\n" "${cyan:-}" "$((MENU_W-2))" "" "${reset:-}" | tr ' ' '═'
  content=$(get_deploy_line)
  line=$(printf "║ %-*s ║" "$max_content" "$(menu_fit "$max_content" "$content")")
  printf "%b%s%b\n" "${dim:-}" "$line" "${reset:-}"
  printf "%b╠%*s╣%b\n" "${cyan:-}" "$((MENU_W-2))" "" "${reset:-}" | tr ' ' '═'
  # Two-column menu (1-4 left, 5-8 right)
  local col_w=$(( (MENU_W - 4) / 2 ))
  printf "║ %-*s %-*s ║\n" "$col_w" "1) Set web version"       "$col_w" "5) Build..."
  printf "║ %-*s %-*s ║\n" "$col_w" "2) Set desktop version" "$col_w" "6) Dev (foreground)..."
  printf "║ %-*s %-*s ║\n" "$col_w" "3) Set mobile version"  "$col_w" "7) Android helpers..."
  printf "║ %-*s %-*s ║\n" "$col_w" "4) Set ALL versions"    "$col_w" "8) Quit"
  printf "%b╚%*s╝%b\n" "${cyan:-}" "$((MENU_W-2))" "" "${reset:-}" | tr ' ' '═'
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

# Draw a submenu card (title + two-column options)
draw_submenu() {
  local title="$1" opts="$2"  # opts = "1) Label|2) Label|..." (pairs separated by |)
  local col_w=$(( (MENU_W - 4) / 2 )) max_content=$((MENU_W - 4))
  [ -t 1 ] && clear
  local top_hr
  top_hr=$(printf '╔%*s╗' "$((MENU_W-2))" "" | tr ' ' '═')
  printf "%b%s%b\n" "${cyan:-}" "$top_hr" "${reset:-}"
  printf "%b║ %-*s ║%b\n" "${bold:-}" "$max_content" "$title" "${reset:-}"
  printf "%b╠%*s╣%b\n" "${cyan:-}" "$((MENU_W-2))" "" "${reset:-}" | tr ' ' '═'
  local i=0 left= right=
  while IFS='|' read -r part; do
    [ -z "$part" ] && continue
    if [ $((i % 2)) -eq 0 ]; then left="$part"; else right="$part"; printf "║ %-*s %-*s ║\n" "$col_w" "$left" "$col_w" "$right"; fi
    i=$((i+1))
  done <<< "$(echo "$opts" | tr '|' '\n')"
  [ $((i % 2)) -eq 1 ] && printf "║ %-*s %-*s ║\n" "$col_w" "$left" "$col_w" ""
  printf "%b╚%*s╝%b\n" "${cyan:-}" "$((MENU_W-2))" "" "${reset:-}" | tr ' ' '═'
}

build_menu() {
  draw_submenu "🔨 Build" "1) Build web (vite)|2) Build desktop (electron)|3) Build Android|4) Build iOS|5) Build servers|6) Build all|7) Back"
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
  draw_submenu "▶️  Dev (foreground)" "1) Dev server only|2) Dev web (client)|3) Dev desktop|4) Dev mobile (vite)|5) Dev all (server+client+desktop)|6) Back"
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
  draw_submenu "🤖 Android" "1) Build debug APK|2) Build APK + install via ADB|3) Install last APK via ADB|4) Run with Capacitor (Android Studio)|5) Back"
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
