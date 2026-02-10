#!/usr/bin/env bash
# MTX project menu: project helper (versions, build, dev servers, Android)
desc="Project helper menu: versions, build, dev servers, Android"
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

show_versions() {
  echo ""
  echo "📦 Current versions:"
  local root_v web_v desk_v mob_v
  root_v=$(read_json_field "$ROOT_PKG" version)
  web_v=$(read_json_field "$CLIENT_PKG" version 2>/dev/null)
  desk_v=$(read_json_field "$DESKTOP_PKG" version 2>/dev/null)
  mob_v=$(read_json_field "$MOBILE_PKG" version 2>/dev/null)
  printf "- Repo           : %s\n" "${root_v:-n/a}"
  printf "- Web (client)   : %s\n" "${web_v:-n/a}"
  printf "- Desktop        : %s\n" "${desk_v:-n/a}"
  printf "- Mobile         : %s\n" "${mob_v:-n/a}"
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
  echo "🔨 Build options:"
  echo "1) Build web (vite)"
  echo "2) Build desktop (electron)"
  echo "3) Build Android"
  echo "4) Build iOS"
  echo "5) Build servers"
  echo "6) Build all"
  echo "7) Back"
  read -rp "Select: " choice
  case "$choice" in
    1) "$0" compile vite ;;
    2) "$0" compile electron ;;
    3) "$0" compile android ;;
    4) "$0" compile ios ;;
    5) "$0" compile servers ;;
    6) "$0" compile all ;;
    *) return ;;
  esac
}

dev_menu() {
  echo ""
  echo "▶️  Dev options (foreground):"
  echo "1) Dev server only"
  echo "2) Dev web (client)"
  echo "3) Dev desktop"
  echo "4) Dev mobile (vite)"
  echo "5) Dev all (server+client+desktop)"
  echo "6) Back"
  read -rp "Select: " choice
  case "$choice" in
    1) npm run dev:server ;;
    2) npm run dev:client ;;
    3) npm run dev:desktop ;;
    4) npm run dev:mobile ;;
    5) npm run dev:all ;;
    *) return ;;
  esac
}

android_menu() {
  echo ""
  echo "🤖 Android helpers:"
  echo "1) Build debug APK"
  echo "2) Build debug APK and install via ADB"
  echo "3) Install last built APK via ADB"
  echo "4) Run with Capacitor (opens Android Studio/emulator)"
  echo "5) Back"
  read -rp "Select: " choice
  case "$choice" in
    1)
      "$0" compile android-debug
      ;;
    2)
      "$0" compile android-debug
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
      (cd targets/mobile && npx cap run android)
      ;;
    *) return ;;
  esac
}

main_menu() {
  while true; do
    echo ""
    echo "===== Dev Helper ====="
    show_versions
    echo ""
    echo "Choose an action:"
    echo "1) Set web version"
    echo "2) Set desktop version"
    echo "3) Set mobile version"
    echo "4) Set ALL versions"
    echo "5) Build..."
    echo "6) Dev (foreground)..."
    echo "7) Android helpers..."
    echo "8) Exit"
    read -rp "Select [1-8]: " ans
    case "$ans" in
      1) read -rp "New web version (X.Y.Z): " v; [[ -z "$v" ]] || set_version web "$v" ;;
      2) read -rp "New desktop version (X.Y.Z): " v; [[ -z "$v" ]] || set_version desktop "$v" ;;
      3) read -rp "New mobile version (X.Y.Z): " v; [[ -z "$v" ]] || set_version mobile "$v" ;;
      4) read -rp "New ALL version (X.Y.Z): " v; [[ -z "$v" ]] || set_version all "$v" ;;
      5) build_menu ;;
      6) dev_menu ;;
      7) android_menu ;;
      8) echo "Bye"; exit 0 ;;
      *) echo "Unknown option" ;;
    esac
  done
}

main_menu
