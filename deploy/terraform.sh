#!/usr/bin/env bash
# Nested under deploy: mtx deploy terraform <apply|destroy> [args...]
#   mtx deploy terraform apply [staging|production]
#   mtx deploy terraform destroy [staging|production]
desc="Terraform orchestration (apply or destroy) under mtx deploy"
set -e

MTX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
BIN_DIR="$MTX_ROOT/deploy/terraform"
cmd="${1:-}"
shift || true

case "$cmd" in
  apply)
    exec "$BIN_DIR/apply.sh" "$@"
    ;;
  destroy)
    exec "$BIN_DIR/destroy.sh" "$@"
    ;;
  ""|-h|--help|help)
    echo "Usage: mtx deploy terraform <apply|destroy> [arguments...]"
    echo ""
    echo "  apply    — Full deploy pipeline (infra + build + railway up). Same engine as mtx deploy."
    echo "            Optional: --revendor (force re-sync vendored terraform from project-bridge)."
    echo "  destroy  — Tear down Terraform-managed resources for an environment."
    exit 0
    ;;
  *)
    echo "Unknown subcommand: ${cmd:-}" >&2
    echo "Use: mtx deploy terraform apply|destroy ..." >&2
    echo "Run: mtx deploy terraform --help" >&2
    exit 1
    ;;
esac
