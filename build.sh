#!/usr/bin/env bash
# Build unified server artifacts for the project root (tree with config/app.json).
# Same npm steps as mtx deploy uses before railway up; does not provision infra or upload.
# Org hosts (config/app.json + project-bridge): before build, primes resolved project-bridge with
# npm install and db:generate (same as project/org-build-server.sh).
# Org repos with scripts/prepare-railway-artifact.sh: run npm run prepare:railway instead of
# build:server — produces targets/server/dist, npm-packs, and deploy manifests for Railway.
# Path payloads: MTX runs lib/vendor-payloads-from-config.sh on the org root before prepare:railway.
# Terraform: when terraform/main.tf exists, MTX runs lib/vendor-terraform-from-bridge.sh to re-sync
# project-bridge/terraform if its fingerprint changed since the last mtx deploy digest.
# Implementation: compile/build-impl.sh (server, backend, prepare:railway, terraform sync, bridge prime).
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

# One-line status while quiet `npm run prepare:railway` runs (otherwise mtx_run hides all output; long silence).
# shellcheck source=includes/mtx-deploy-spinner.sh
[ -f "$MTX_ROOT/includes/mtx-deploy-spinner.sh" ] && source "$MTX_ROOT/includes/mtx-deploy-spinner.sh" || {
  mtx_deploy_spinner_start() { :; }
  mtx_deploy_spinner_stop() { :; }
}

# Match deploy/terraform/apply.sh PROJECT_ROOT resolution
PROJECT_ROOT=""
if [ -f "config/app.json" ]; then
  PROJECT_ROOT="$(pwd)"
fi
if [ -z "$PROJECT_ROOT" ] && [ -f "../config/app.json" ]; then
  PROJECT_ROOT="$(cd .. && pwd)"
fi
if [ -z "$PROJECT_ROOT" ]; then
  for d in . .. ../project-bridge; do
    [ -f "${d}/config/app.json" ] && PROJECT_ROOT="$(cd "$d" && pwd)" && break
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
    echo "  server   — org hosts: MTX project/org-build-server.sh; else npm run build:server. With prepare:railway scripts, runs prepare:railway (path payloads: vendor-payloads-from-config.sh first)"
    echo "  backend  — npm run build:backend-server (or same prepare:railway when unified)"
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

# shellcheck source=compile/build-impl.sh
source "$MTX_ROOT/compile/build-impl.sh"
