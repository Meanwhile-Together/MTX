#!/usr/bin/env bash
# Backward-compatible: `mtx create` = payload from payload-basic. Prefer `mtx create payload` or `mtx payload create`.
desc="Create payload-* repo from payload-basic (same as mtx payload create / mtx create payload)"
nobanner=1
set -e

MTX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export MTX_REPO_PREFIX="payload-"
export MTX_TEMPLATE_REPO="${MTX_PAYLOAD_TEMPLATE_REPO:-payload-basic}"
export MTX_KIND_LABEL="Payload"
export MTX_CREATE_CMD="mtx create"

# shellcheck source=lib/create-from-template.sh
source "$MTX_ROOT/lib/create-from-template.sh"
mtx_create_from_template_run
