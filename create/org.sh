#!/usr/bin/env bash
# Create an org-* repo via `mtx create org` (single entry point for org scaffolding).
# Prefer one shared org payload + config for tenants; use this when you need a separate org-* product repo. See https://github.com/Meanwhile-Together/project-bridge/blob/main/docs/MTX_SCAFFOLDING_MODEL.md.
desc="Create an org-* repo from org host template (default template-basic; override MTX_ORG_TEMPLATE_REPO)"
nobanner=1
set -e

MTX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export MTX_CREATE_VARIANT=org
export MTX_REPO_PREFIX="org-"
# GitHub has no template-org yet; template-basic is the org-shaped starter (see https://github.com/Meanwhile-Together/project-bridge/blob/main/docs/MTX_SCAFFOLDING_MODEL.md).
export MTX_TEMPLATE_REPO="${MTX_ORG_TEMPLATE_REPO:-template-basic}"
export MTX_KIND_LABEL="Organization"
export MTX_CREATE_CMD="mtx create org"

# shellcheck source=../lib/create-from-template.sh
source "$MTX_ROOT/lib/create-from-template.sh"
mtx_create_from_template_run "$@"
