#!/usr/bin/env bash
# Same as org/create.sh — use `mtx create org` or `mtx org create`.
desc="Create an org-* repo from payload-basic (GitHub + local); register in apps[]"
nobanner=1
set -e

MTX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export MTX_REPO_PREFIX="org-"
export MTX_TEMPLATE_REPO="${MTX_ORG_TEMPLATE_REPO:-payload-basic}"
export MTX_KIND_LABEL="Organization"
export MTX_CREATE_CMD="mtx create org"

# shellcheck source=../lib/create-from-template.sh
source "$MTX_ROOT/lib/create-from-template.sh"
mtx_create_from_template_run
