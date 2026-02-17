#!/usr/bin/env bash
# MTX deploy: no args → interactive menu (staging / production), then terraform apply
desc="Interactive deploy menu (choose staging or production), then terraform apply"
nobanner=1
set -e

# Always use MTX scripts (this script lives in MTX root)
MTX_ROOT="$(cd "$(dirname "$0")" && pwd)"

# Only use $1 as env if it's a valid environment; otherwise show menu (avoids "deploy" or other junk as env)
ENV=""
case "${1:-}" in
  staging|production) ENV="$1" ;;
esac
if [ -z "$ENV" ]; then
  echo "Deploy environment:"
  echo "  1) staging"
  echo "  2) production"
  read -rp "Choice (1 or 2) [1]: " choice
  choice="${choice:-1}"
  case "$choice" in
    1|s|staging)   ENV=staging ;;
    2|p|production) ENV=production ;;
    *) echo "Invalid choice. Use 1 or 2." >&2; exit 1 ;;
  esac
fi

[ -n "${FORCE_BACKEND:-}" ] && export FORCE_BACKEND
# Run MTX's terraform/apply.sh (never project's copy)
if [ -n "${FORCE_BACKEND:-}" ]; then
  "$MTX_ROOT/terraform/apply.sh" --force-backend "$ENV"
else
  "$MTX_ROOT/terraform/apply.sh" "$ENV"
fi
# After successful deploy, ensure deploy URLs and print them (same as mtx deploy urls)
if [ -f "$MTX_ROOT/deploy/urls.sh" ]; then
  "$MTX_ROOT/deploy/urls.sh" "$ENV"
fi
