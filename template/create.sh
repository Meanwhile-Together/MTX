#!/usr/bin/env bash
# Create a template-* repo from a source template (GitHub name must be template-*).
desc="Create a template-* repo from a source template (register in apps[] as needed)"
nobanner=1
set -e

MTX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export MTX_REPO_PREFIX="template-"
export MTX_TEMPLATE_REPO="${MTX_TEMPLATE_SOURCE_REPO:-${MTX_PAYLOAD_TEMPLATE_REPO:-payload-basic}}"
export MTX_KIND_LABEL="Template"
export MTX_CREATE_CMD="mtx template create"

# shellcheck source=../lib/create-from-template.sh
source "$MTX_ROOT/lib/create-from-template.sh"
mtx_create_from_template_run
