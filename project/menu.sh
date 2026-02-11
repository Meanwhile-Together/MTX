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

show_framework_deploy_status() {
  echo ""
  echoc cyan "📋 Framework & deploy:"
  local owner slug proj_id platforms
  owner=$(read_json "$APP_JSON" "(.app.owner // \"\")")
  slug=$(read_json "$APP_JSON" "(.app.slug // \"\")")
  [ -z "$owner" ] && owner=$(read_json_field "$APP_JSON" app.owner 2>/dev/null || true)
  [ -z "$slug" ] && slug=$(read_json_field "$APP_JSON" app.slug 2>/dev/null || true)
  if [ -n "$owner" ] && [ -n "$slug" ]; then
    status ok "Project B app: $owner / $slug"
  else
    status fail "Not a Project B app (missing or empty config/app.json app.owner / app.slug)"
  fi
  if [ ! -f "$DEPLOY_JSON" ]; then
    printf "  %bPlatforms:%b (no config/deploy.json)\n" "${dim:-}" "${reset:-}"
    printf "  %bStaging:%b   ☐  %bProduction:%b  ☐  %bBackend:%b  ☐\n" "${dim:-}" "${reset:-}" "${dim:-}" "${reset:-}" "${dim:-}" "${reset:-}"
    printf "  %bApps:%b       —\n" "${dim:-}" "${reset:-}"
    return
  fi
  proj_id=$(read_json "$DEPLOY_JSON" "(.projectId // \"\")")
  platforms=$(read_json "$DEPLOY_JSON" "(.platform // [] | join(\", \"))")
  if [ -z "$platforms" ]; then platforms="none"; fi
  printf "  %bPlatforms:%b %s\n" "${dim:-}" "${reset:-}" "$platforms"
  # Deploy checkboxes: Staging / Production ✅ if env block + projectId; Backend ✅ if projectId set
  local stg_ok prd_ok backend_ok s1 s2 s3 has_stg has_prd
  has_stg=$(read_json "$DEPLOY_JSON" "(.staging != null) | tostring" 2>/dev/null || echo "false")
  has_prd=$(read_json "$DEPLOY_JSON" "(.production != null) | tostring" 2>/dev/null || echo "false")
  [ -n "$proj_id" ] && [ "$has_stg" = "true" ] && stg_ok=1 || stg_ok=
  [ -n "$proj_id" ] && [ "$has_prd" = "true" ] && prd_ok=1 || prd_ok=
  [ -n "$proj_id" ] && backend_ok=1 || backend_ok=
  [ -n "$stg_ok" ] && s1="✅" || s1="☐"
  [ -n "$prd_ok" ] && s2="✅" || s2="☐"
  [ -n "$backend_ok" ] && s3="✅" || s3="☐"
  printf "  %bStaging:%b   %s  %bProduction:%b  %s  %bBackend:%b  %s\n" "${dim:-}" "${reset:-}" "$s1" "${dim:-}" "${reset:-}" "$s2" "${dim:-}" "${reset:-}" "$s3"
  # Apps: optional .apps[] in deploy.json
  local apps_line
  apps_line=$(read_json "$DEPLOY_JSON" "(.apps // [] | .[])")
  if [ -n "$apps_line" ]; then
    printf "  %bApps:%b\n" "${dim:-}" "${reset:-}"
    while IFS= read -r app; do
      [ -z "$app" ] && continue
      printf "    ☐ %s\n" "$app"
    done <<< "$apps_line"
  else
    printf "  %bApps:%b       — (optional: add \"apps\": [\"slug\", ...] to config/deploy.json)\n" "${dim:-}" "${reset:-}"
  fi
}

show_versions() {
  echo ""
  echoc cyan "📦 Current versions:"
  local root_v web_v desk_v mob_v
  root_v=$(read_json_field "$ROOT_PKG" version)
  web_v=$(read_json_field "$CLIENT_PKG" version 2>/dev/null)
  desk_v=$(read_json_field "$DESKTOP_PKG" version 2>/dev/null)
  mob_v=$(read_json_field "$MOBILE_PKG" version 2>/dev/null)
  printf -- "  - Repo           : %s\n" "${root_v:-n/a}"
  printf -- "  - Web (client)   : %s\n" "${web_v:-n/a}"
  printf -- "  - Desktop        : %s\n" "${desk_v:-n/a}"
  printf -- "  - Mobile         : %s\n" "${mob_v:-n/a}"
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

build_menu() {
  echo ""
  echoc yellow "🔨 Build options:"
  echo "  1) Build web (vite)"
  echo "  2) Build desktop (electron)"
  echo "  3) Build Android"
  echo "  4) Build iOS"
  echo "  5) Build servers"
  echo "  6) Build all"
  echo "  7) Back"
  color yellow "Select (1-7): "; read -r choice
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
  echo ""
  echoc yellow "▶️  Dev options (foreground):"
  echo "  1) Dev server only"
  echo "  2) Dev web (client)"
  echo "  3) Dev desktop"
  echo "  4) Dev mobile (vite)"
  echo "  5) Dev all (server+client+desktop)"
  echo "  6) Back"
  color yellow "Select (1-6): "; read -r choice
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
  echo ""
  echoc yellow "🤖 Android helpers:"
  echo "  1) Build debug APK"
  echo "  2) Build debug APK and install via ADB"
  echo "  3) Install last built APK via ADB"
  echo "  4) Run with Capacitor (opens Android Studio/emulator)"
  echo "  5) Back"
  color yellow "Select (1-5): "; read -r choice
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
    echo ""
    echoc bold "===== Dev Helper ====="
    show_framework_deploy_status
    show_versions
    echo ""
    echoc cyan "Choose an action:"
    echo "  1) Set web version"
    echo "  2) Set desktop version"
    echo "  3) Set mobile version"
    echo "  4) Set ALL versions"
    echo "  5) Build..."
    echo "  6) Dev (foreground)..."
    echo "  7) Android helpers..."
    echo "  8) Quit"
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
