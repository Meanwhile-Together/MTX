#!/usr/bin/env bash
# Create an organization payload repo: GitHub name must be org-*.
# Prefer one shared org source + routing; this scaffolds a new org-* product repo when needed. See docs/MTX_SCAFFOLDING_MODEL.md.
desc="Create an org-* organization payload repo from template (tenant/org surface; register in apps[])"
nobanner=1
set -e

MTX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export MTX_REPO_PREFIX="org-"
export MTX_TEMPLATE_REPO="${MTX_ORG_TEMPLATE_REPO:-template-basic}"
export MTX_KIND_LABEL="Organization"
export MTX_CREATE_CMD="mtx org create"

# shellcheck source=../lib/create-from-template.sh
source "$MTX_ROOT/lib/create-from-template.sh"
mtx_create_from_template_run "$@"
