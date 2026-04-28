#!/usr/bin/env bash
# Subroutine: ensure a Railway service has a public *.up.railway.app domain.
# Source this file and call ensure_railway_domain, or run as script with args.
# Usage (function): ensure_railway_domain "$project_root" "$project_id" "$service_id" "$environment" "$label"
# Usage (script):   ./ensure-railway-domain.sh <project_root> <project_id> <service_id> <environment> <label>
# Requires: railway CLI on PATH and RAILWAY_TOKEN in environment
# (provided by org repo .env via deploy/urls.sh).

ensure_railway_domain() {
    _timeout_secs="${MTX_URLS_TIMEOUT_SEC:-20}"
    _run_cmd() {
        timeout -k 2s "${_timeout_secs}s" "$@" 2>/dev/null
    }

    local project_root="${1:?}"
    local project_id="${2:?}"
    local service_id="${3:?}"
    local environment="${4:?}"
    local label="${5:-service}"
    local service_ref="$service_id"

    if [ -z "$project_id" ] || [ "$project_id" = "null" ] || [ -z "$service_id" ] || [ "$service_id" = "null" ]; then
        return 0
    fi

    if [ -z "${RAILWAY_TOKEN:-}" ]; then
        echo -e "${YELLOW}⚠️  RAILWAY_TOKEN missing; cannot ensure domain for $label${NC}" >&2
        return 0
    fi
    export RAILWAY_TOKEN
    unset RAILWAY_API_TOKEN

    # Railway domain CLI resolves by service name more reliably than service ID.
    # Resolve service name from status JSON when possible.
    local status_json resolved_name
    status_json="$(_run_cmd railway status --json || true)"
    if [ -n "$status_json" ] && command -v jq >/dev/null 2>&1; then
        resolved_name="$(echo "$status_json" | jq -r --arg env "$environment" --arg sid "$service_id" '
          .environments.edges[]
          | select(.node.name == $env or .node.id == $env)
          | .node.serviceInstances.edges[]
          | select(.node.serviceId == $sid)
          | .node.serviceName
        ' 2>/dev/null | head -n 1)"
        if [ -n "$resolved_name" ] && [ "$resolved_name" != "null" ]; then
            service_ref="$resolved_name"
        fi
    fi

    local saved_pwd
    saved_pwd="$(pwd)"
    cd "$project_root" || return 1
    mkdir -p .railway
    echo "$project_id"   > .railway/project
    echo "$service_ref"  > .railway/service
    echo "$environment" > .railway/environment
    # Ensure CLI has a proper link (some versions need this before domain)
    _run_cmd railway link --project "$project_id" --service "$service_ref" --environment "$environment" || true

    # Generate public domain for this service.
    local out
    out=$(_run_cmd railway domain --service "$service_ref" --json) || \
    out=$(_run_cmd railway domain --service "$service_ref") || true

    cd "$saved_pwd" || true

    if [ -n "$out" ]; then
        echo "$out"
    else
        echo -e "${YELLOW}⚠️  No domain output for $label; run 'railway domain' in project root with service linked to generate.${NC}" >&2
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
