#!/usr/bin/env bash
# Build unified server artifacts for the project root (tree with config/app.json).
# Same npm steps as mtx deploy uses before railway up; does not provision infra or upload.
# Org hosts (config/app.json + project-bridge): before build, primes resolved project-bridge with
# npm install and db:generate (same as project/org-build-server.sh).
# Org deploy roots (unified host): run MTX project/prepare-railway-artifact.sh — produces
# targets/server/dist, npm-packs, and deploy manifests for Railway.
# Path payloads: MTX runs lib/vendor-payloads-from-config.sh on the deploy root before prepare.
# Terraform: when terraform/main.tf exists, MTX runs lib/vendor-terraform-from-bridge.sh to re-sync
# project-bridge/terraform if its fingerprint changed since the last mtx deploy digest.
# Usage: mtx build [server|backend|all]   (default: all)
desc="Build server artifacts (no deploy); optional: server, backend, or all"
nobanner=1
set -e

MTX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
export MTX_ROOT
# shellcheck source=includes/mtx-run.sh
[ -f "$MTX_ROOT/includes/mtx-run.sh" ] && source "$MTX_ROOT/includes/mtx-run.sh"
# shellcheck source=includes/verify-pb-framework-identity.sh
[ -f "$MTX_ROOT/includes/verify-pb-framework-identity.sh" ] && source "$MTX_ROOT/includes/verify-pb-framework-identity.sh"
# mtx exports MTX_VERBOSE before sourcing; plain `bash build.sh` leaves it unset — pass subprocess output through
if [ -z "${MTX_VERBOSE+x}" ]; then
  mtx_run() { "$@"; }
fi
declare -F mtx_run &>/dev/null || mtx_run() { "$@"; }

# One-line status while quiet prepare-railway runs (otherwise mtx_run hides all output; long silence).
# shellcheck source=includes/mtx-deploy-spinner.sh
[ -f "$MTX_ROOT/includes/mtx-deploy-spinner.sh" ] && source "$MTX_ROOT/includes/mtx-deploy-spinner.sh" || {
  mtx_deploy_spinner_start() { :; }
  mtx_deploy_spinner_stop() { :; }
}

mtx_build_spinner_org_name() {
  local f n
  for f in "$PROJECT_ROOT/config/org.json" "$PROJECT_ROOT/config/app.json"; do
    [ -f "$f" ] || continue
    if command -v jq >/dev/null 2>&1; then
      n=$(jq -r '(.org.name // .app.name) // empty' "$f" 2>/dev/null) || n=""
      n="${n//$'\n'/ }"
      n="${n//$'\r'/ }"
      if [ -n "$n" ] && [ "$n" != "null" ]; then
        printf '%s' "$n"
        return 0
      fi
    fi
  done
  printf '%s' "$(basename "$PROJECT_ROOT")"
}

# Match deploy/terraform/apply.sh PROJECT_ROOT resolution
PROJECT_ROOT=""
if [ -f "config/app.json" ] || [ -f "config/org.json" ]; then
  PROJECT_ROOT="$(pwd)"
fi
if [ -z "$PROJECT_ROOT" ] && { [ -f "../config/app.json" ] || [ -f "../config/org.json" ]; }; then
  PROJECT_ROOT="$(cd .. && pwd)"
fi
if [ -z "$PROJECT_ROOT" ]; then
  for d in . .. ../project-bridge; do
    [ -f "${d}/config/app.json" ] || [ -f "${d}/config/org.json" ] || continue
    PROJECT_ROOT="$(cd "$d" && pwd)"
    break
  done
fi
[ -z "$PROJECT_ROOT" ] && PROJECT_ROOT="$(pwd)"
cd "$PROJECT_ROOT" || exit 1

TARGET="${1:-all}"
case "$TARGET" in
  server|app|s) TARGET=server ;;
  backend|b) TARGET=backend ;;
  all|a|'') TARGET=all ;;
  -h|--help|help)
    echo "Usage: mtx build [server|backend|all]"
    echo "  server   — unified deploy roots: MTX project/prepare-railway-artifact.sh; else MTX project/org-build-server.sh or npm run build:server (path payloads: vendor-payloads-from-config.sh first)"
    echo "  backend  — npm run build:backend-server (or same prepare bundle when unified)"
    echo "  all      — both (default; org repos run one unified build if backend aliases to server)"
    echo "  Org repos: project-bridge is primed with npm install + db:generate first (sibling, vendor/, or PROJECT_BRIDGE_ROOT)."
    exit 0
    ;;
  *)
    echo "Unknown target: $TARGET" >&2
    echo "Usage: mtx build [server|backend|all]" >&2
    exit 1
    ;;
esac

# Harden: project-bridge must carry template placeholder org.json (sibling or cwd); fail before terraform/prime.
if [ -f "$MTX_ROOT/includes/verify-pb-framework-identity.sh" ] && type mtx_verify_project_bridge_identity_for_build_context >/dev/null 2>&1; then
  mtx_verify_project_bridge_identity_for_build_context "$PROJECT_ROOT" "$MTX_ROOT" || exit 1
else
  echo "❌ MTX missing or incomplete includes/verify-pb-framework-identity.sh; cannot verify framework org identity" >&2
  exit 1
fi

# Org host: config/app.json + resolvable project-bridge (same unified build as mtx build server → project/org-build-server.sh).
mtx_is_org_unified_host() {
  local root="${1:-$PROJECT_ROOT}"
  [ -f "$root/config/app.json" ] || [ -f "$root/config/org.json" ] || return 1
  mtx_resolve_org_project_bridge "$root" &>/dev/null
}

# Same resolution order as project/org-build-server.sh and template thin wrapper
mtx_resolve_org_project_bridge() {
  local root="$1"
  if [ -n "${PROJECT_BRIDGE_ROOT:-}" ] && [ -f "${PROJECT_BRIDGE_ROOT}/package.json" ]; then
    echo "$(cd "${PROJECT_BRIDGE_ROOT}" && pwd)"
    return 0
  fi
  local cand
  for cand in "$root/vendor/project-bridge" "$root/../project-bridge"; do
    if [ -f "$cand/package.json" ]; then
      echo "$(cd "$cand" && pwd)"
      return 0
    fi
  done
  return 1
}

mtx_prime_org_project_bridge_if_needed() {
  mtx_is_org_unified_host || return 0
  case "$TARGET" in server|backend|all) ;; *) return 0 ;; esac
  local pb
  if ! pb="$(mtx_resolve_org_project_bridge "$PROJECT_ROOT")"; then
    echo "❌ mtx build (org): project-bridge not found. Expected ../project-bridge, vendor/project-bridge, or PROJECT_BRIDGE_ROOT." >&2
    exit 1
  fi
  echo "ℹ️  Org repo: priming project-bridge at $pb (npm install, db:generate)..." >&2
  (cd "$pb" && mtx_run npm install && mtx_run npm run db:generate) || {
    echo "❌ project-bridge prime failed (npm install / db:generate)" >&2
    exit 1
  }
}

ensure_npm_deps() {
  if [ ! -f "node_modules/.bin/prisma" ] && [ -f "package.json" ]; then
    echo "ℹ️  Dependencies missing, running npm install..." >&2
    mtx_run npm install || { echo "❌ npm install failed" >&2; exit 1; }
  fi
}

# Unified org deploy root: full Railway bundle (mirrored dist + npm pack + package.deploy.json / lock).
mtx_org_use_prepare_railway() {
  mtx_is_org_unified_host "$PROJECT_ROOT"
}

run_prepare_railway_bundle() {
  echo "🔨 Building Railway deploy bundle (MTX project/prepare-railway-artifact.sh)..." >&2
  if [ ! -f "$MTX_ROOT/project/prepare-railway-artifact.sh" ]; then
    echo "❌ Missing $MTX_ROOT/project/prepare-railway-artifact.sh" >&2
    exit 1
  fi
  # Path payloads: vendor + build from config/server.json (canonical MTX lib; do not duplicate in org scripts/).
  if [ "${MTX_SKIP_PAYLOAD_VENDOR:-}" != "1" ] && [ -f "$PROJECT_ROOT/config/server.json" ]; then
    if [ ! -f "$MTX_ROOT/lib/vendor-payloads-from-config.sh" ]; then
      echo "❌ MTX lib missing: $MTX_ROOT/lib/vendor-payloads-from-config.sh" >&2
      exit 1
    fi
    echo "==> mtx build: vendor path payloads from config/server.json (MTX lib)" >&2
    # Vendor script prints one TTY status line per payload (dots); npm inside it uses mtx_run for quiet.
    bash "$MTX_ROOT/lib/vendor-payloads-from-config.sh" "$PROJECT_ROOT"
    # prepare-railway-artifact runs the same vendor if MTX_SKIP_PAYLOAD_VENDOR is unset — duplicates
    # work. MTX has already vended; skip the second pass.
    export MTX_SKIP_PAYLOAD_VENDOR=1
  fi
  # At MTX_VERBOSE<=1, mtx_run hides long subprocess output — show one-line status so the gap is not blank.
  if [ "${MTX_VERBOSE:-1}" -le 1 ]; then
    mtx_deploy_spinner_start "prepare" "$(mtx_build_spinner_org_name)"
    set +e
    mtx_run bash "$MTX_ROOT/project/prepare-railway-artifact.sh" "$PROJECT_ROOT"
    pr_ec=$?
    set -e
    mtx_deploy_spinner_stop
    if [ $pr_ec -ne 0 ]; then
      echo "❌ prepare-railway-artifact failed" >&2
      exit 1
    fi
  else
    mtx_run bash "$MTX_ROOT/project/prepare-railway-artifact.sh" "$PROJECT_ROOT" || {
      echo "❌ prepare-railway-artifact failed" >&2
      exit 1
    }
  fi
  echo "✅ prepare-railway-artifact complete" >&2
  # After payload vendor/build: portable MTX pre-deploy (hook + root-path HTML/Vite fixes). See includes/mtx-predeploy.sh + fixes/root-paths-lib.sh.
  if [ -f "$MTX_ROOT/includes/mtx-predeploy.sh" ]; then
    # shellcheck source=includes/mtx-predeploy.sh
    source "$MTX_ROOT/includes/mtx-predeploy.sh"
    mtx_predeploy_after_payload_assembly "$PROJECT_ROOT" || {
      echo "❌ mtx pre-deploy after prepare-railway-artifact failed" >&2
      exit 1
    }
  fi
}

run_server_build() {
  if mtx_org_use_prepare_railway; then
    run_prepare_railway_bundle
    return
  fi
  if mtx_is_org_unified_host; then
    echo "🔨 Building org unified server (MTX project/org-build-server.sh)..." >&2
    if [ ! -f "$MTX_ROOT/project/org-build-server.sh" ]; then
      echo "❌ Missing $MTX_ROOT/project/org-build-server.sh" >&2
      exit 1
    fi
    bash "$MTX_ROOT/project/org-build-server.sh" "$PROJECT_ROOT" || { echo "❌ org unified server build failed" >&2; exit 1; }
    echo "✅ org unified server build complete" >&2
    return
  fi
  echo "🔨 Building app server (npm run build:server)..." >&2
  ensure_npm_deps
  mtx_run npm run build:server || { echo "❌ build:server failed" >&2; exit 1; }
  echo "✅ build:server complete" >&2
}

run_backend_build() {
  if mtx_org_use_prepare_railway; then
    run_prepare_railway_bundle
    return
  fi
  echo "🔨 Building backend server (npm run build:backend-server)..." >&2
  ensure_npm_deps
  mtx_run npm run build:backend-server || { echo "❌ build:backend-server failed" >&2; exit 1; }
  echo "✅ build:backend-server complete" >&2
}

# When this tree has vendored terraform/, refresh from project-bridge if the canonical tree changed
# since the last mtx deploy (see terraform/.mtx-bridge-terraform.sha256) or first run.
if [ -f "$PROJECT_ROOT/terraform/main.tf" ] && [ -f "$MTX_ROOT/lib/vendor-terraform-from-bridge.sh" ]; then
  bash "$MTX_ROOT/lib/vendor-terraform-from-bridge.sh" --sync-mode=auto "$PROJECT_ROOT"
fi

mtx_prime_org_project_bridge_if_needed

case "$TARGET" in
  server) run_server_build ;;
  backend) run_backend_build ;;
  all)
    run_server_build
    # org host: build:backend-server aliases to the same unified build — avoid duplicate work
    if ! mtx_is_org_unified_host; then
      run_backend_build
    fi
    ;;
esac
