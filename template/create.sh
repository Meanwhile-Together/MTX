#!/usr/bin/env bash
# Snapshot current payload dir into template-* (run from payload root). See docs/MTX_SCAFFOLDING_MODEL.md.
desc="Snapshot current payload into a template-* repo (run from payload root)"
nobanner=1
set -e

MTX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export MTX_REPO_PREFIX="template-"
export MTX_KIND_LABEL="Payload template"
export MTX_CREATE_CMD="mtx template create"

# shellcheck source=../lib/create-from-template.sh
source "$MTX_ROOT/lib/create-from-template.sh"
mtx_create_template_from_payload_run "$@"
