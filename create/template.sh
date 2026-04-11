#!/usr/bin/env bash
# Same as template/create.sh — use `mtx create template` or `mtx template create`.
# Run from a payload repo root: snapshots the current tree into a new template-* git repo. See docs/MTX_SCAFFOLDING_MODEL.md.
desc="Create a template-* repo by snapshotting the current payload directory (run from payload root; optional name arg)"
nobanner=1
set -e

MTX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export MTX_REPO_PREFIX="template-"
export MTX_KIND_LABEL="Payload template"
export MTX_CREATE_CMD="mtx create template"

# shellcheck source=../lib/create-from-template.sh
source "$MTX_ROOT/lib/create-from-template.sh"
mtx_create_template_from_payload_run "$@"
