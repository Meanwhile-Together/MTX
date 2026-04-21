#!/usr/bin/env bash
# Create an org-* repo via `mtx create org` (single entry point for org scaffolding).
# Prefer one shared org payload + config for tenants; use this when you need a separate org-* product repo. See https://github.com/Meanwhile-Together/project-bridge/blob/main/docs/MTX_SCAFFOLDING_MODEL.md.
desc="Create an org-* repo from org host template (default template-org; override MTX_ORG_TEMPLATE_REPO)"
nobanner=1
set -e

MTX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export MTX_CREATE_VARIANT=org
export MTX_REPO_PREFIX="org-"
# Canonical org-host scaffold is `template-org` (rule-of-law §1 2026-04-20). The legacy
# `template-basic` name is still accepted via MTX_ORG_TEMPLATE_REPO=template-basic for
# operators who haven't migrated their local clone yet, but new scaffolds should land on
# template-org. See https://github.com/Meanwhile-Together/project-bridge/blob/main/docs/MTX_SCAFFOLDING_MODEL.md.
export MTX_TEMPLATE_REPO="${MTX_ORG_TEMPLATE_REPO:-template-org}"
export MTX_KIND_LABEL="Organization"
export MTX_CREATE_CMD="mtx create org"

# shellcheck source=../lib/create-from-template.sh
source "$MTX_ROOT/lib/create-from-template.sh"
mtx_create_from_template_run "$@"
