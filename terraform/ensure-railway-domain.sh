#!/usr/bin/env bash
# Subroutine: ensure a Railway service has a public *.up.railway.app domain.
# Source this file and call ensure_railway_domain, or run as script with args.
# Usage (function): ensure_railway_domain "$project_root" "$project_id" "$service_id" "$environment" "$label"
# Usage (script):   ./ensure-railway-domain.sh <project_root> <project_id> <service_id> <environment> <label>
# Requires: RAILWAY_TOKEN (project token) set in environment; railway CLI on PATH.

ensure_railway_domain() {
    local project_root="${1:?}"
    local project_id="${2:?}"
    local service_id="${3:?}"
    local environment="${4:?}"
    local label="${5:-service}"

    if [ -z "$project_id" ] || [ "$project_id" = "null" ] || [ -z "$service_id" ] || [ "$service_id" = "null" ]; then
        return 0
    fi

    if [ -z "${RAILWAY_TOKEN:-}" ]; then
        echo -e "${YELLOW}⚠️  RAILWAY_TOKEN not set; skipping domain ensure for $label${NC}" >&2
        return 0
    fi

    export RAILWAY_TOKEN
    unset RAILWAY_API_TOKEN

    local saved_pwd
    saved_pwd="$(pwd)"
    cd "$project_root" || return 1
    mkdir -p .railway
    echo "$project_id"   > .railway/project
    echo "$service_id"   > .railway/service
    echo "$environment" > .railway/environment

    local out
    out=$(railway domain --service "$service_id" --environment "$environment" --json 2>/dev/null) || \
    out=$(railway domain --service "$service_id" --environment "$environment" 2>/dev/null) || true

    cd "$saved_pwd" || true

    if [ -n "$out" ]; then
        echo "$out"
    fi
    return 0
}

# When run as script (e.g. from deploy/urls.sh)
if [ -n "${BASH_SOURCE[0]:-}" ] && [ "${BASH_SOURCE[0]}" = "$0" ]; then
    # Minimal colors if not already set
    [ -z "${NC:-}" ] && NC='\033[0m'
    [ -z "${YELLOW:-}" ] && YELLOW='\033[1;33m'
    ensure_railway_domain "$@"
fi
