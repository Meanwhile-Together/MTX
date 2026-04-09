#!/usr/bin/env bash
# Backward-compatible: `mtx create` = payload from template-basic. Prefer `mtx create payload|org|template` or `mtx payload create`.
desc="Create payload-* repo from template-basic (same as mtx payload create / mtx create payload)"
nobanner=1
set -e

MTX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Defensive dispatch when invoked directly (outside mtx wrapper).
case "${1:-}" in
  payload)
    shift
    # shellcheck source=create/payload.sh
    source "$MTX_ROOT/create/payload.sh" "$@"
    return 0 2>/dev/null || exit 0
    ;;
  org)
    shift
    # shellcheck source=create/org.sh
    source "$MTX_ROOT/create/org.sh" "$@"
    return 0 2>/dev/null || exit 0
    ;;
  template)
    shift
    # shellcheck source=create/template.sh
    source "$MTX_ROOT/create/template.sh" "$@"
    return 0 2>/dev/null || exit 0
    ;;
esac

export MTX_REPO_PREFIX="payload-"
export MTX_TEMPLATE_REPO="${MTX_PAYLOAD_TEMPLATE_REPO:-template-basic}"
export MTX_KIND_LABEL="Payload"
export MTX_CREATE_CMD="mtx create"

# shellcheck source=lib/create-from-template.sh
source "$MTX_ROOT/lib/create-from-template.sh"
mtx_create_from_template_run
