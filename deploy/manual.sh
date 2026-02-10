#!/usr/bin/env bash
# MTX deploy manual: prompt for env or use arg, then mtx terraform apply
set -e

ENV="${1:-}"
if [ -z "$ENV" ]; then
  read -rp "Environment (staging): " ENV
  ENV="${ENV:-staging}"
fi

[ -n "${FORCE_BACKEND:-}" ] && export FORCE_BACKEND
"$0" terraform apply "$ENV"
