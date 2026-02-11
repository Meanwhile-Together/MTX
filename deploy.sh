#!/usr/bin/env bash
# MTX deploy: no args → interactive menu (staging / production), then terraform apply
desc="Interactive deploy menu (choose staging or production), then terraform apply"
nocapture=1
set -e

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
"$0" terraform apply "$ENV"
