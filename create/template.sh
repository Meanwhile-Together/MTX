#!/usr/bin/env bash
# Same as template/create.sh — use `mtx create template` or `mtx template create`.
desc="Create a template-* repo from a source template (default payload-basic; override MTX_TEMPLATE_SOURCE_REPO)"
nobanner=1
set -e

MTX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export MTX_REPO_PREFIX="template-"
export MTX_TEMPLATE_REPO="${MTX_TEMPLATE_SOURCE_REPO:-${MTX_PAYLOAD_TEMPLATE_REPO:-payload-basic}}"
export MTX_KIND_LABEL="Template"
export MTX_CREATE_CMD="mtx create template"

# shellcheck source=../lib/create-from-template.sh
source "$MTX_ROOT/lib/create-from-template.sh"
mtx_create_from_template_run
