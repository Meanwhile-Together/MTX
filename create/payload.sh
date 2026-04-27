#!/usr/bin/env bash
# Normative: mtx create payload … (see https://github.com/Meanwhile-Together/project-bridge/blob/main/docs/MTX_COMMAND_SURFACE.md).
# New payload templates: `mtx create template` from a payload root snapshots into template-* (see https://github.com/Meanwhile-Together/project-bridge/blob/main/docs/MTX_SCAFFOLDING_MODEL.md).
desc="Create a payload-* repo from template-payload (GitHub + local); from inside an existing payload-* folder, publishes cwd when the name would target a different sibling (see MTX_CREATE_FORCE_SIBLING_PAYLOAD)"
nobanner=1
set -e

MTX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export MTX_CREATE_VARIANT=payload
export MTX_REPO_PREFIX="payload-"
export MTX_TEMPLATE_REPO="${MTX_PAYLOAD_TEMPLATE_REPO:-template-payload}"
export MTX_KIND_LABEL="Payload"
export MTX_CREATE_CMD="mtx create payload"

# shellcheck source=../lib/create-from-template.sh
source "$MTX_ROOT/lib/create-from-template.sh"
mtx_create_from_template_run "$@"
