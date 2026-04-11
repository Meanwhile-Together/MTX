#!/usr/bin/env bash
# Create a shared payload repo: GitHub name must be payload-*.
# Custom templates: run `mtx create template` from a payload repo root (see docs/MTX_SCAFFOLDING_MODEL.md).
desc="Create a payload-* repo from template (reusable payloads; register in project-bridge apps[])"
nobanner=1
set -e

MTX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export MTX_REPO_PREFIX="payload-"
export MTX_TEMPLATE_REPO="${MTX_PAYLOAD_TEMPLATE_REPO:-template-basic}"
export MTX_KIND_LABEL="Payload"
export MTX_CREATE_CMD="mtx payload create"

# shellcheck source=../lib/create-from-template.sh
source "$MTX_ROOT/lib/create-from-template.sh"
mtx_create_from_template_run "$@"
