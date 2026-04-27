#!/usr/bin/env bash
desc="Create an admin-platform-* repo from template-admin (override MTX_ADMIN_PLATFORM_TEMPLATE_REPO)"
nobanner=1
set -e
MTX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export MTX_CREATE_VARIANT=payload
export MTX_REPO_PREFIX="admin-platform-"
export MTX_TEMPLATE_REPO="${MTX_ADMIN_PLATFORM_TEMPLATE_REPO:-template-admin}"
export MTX_KIND_LABEL="Admin platform"
export MTX_CREATE_CMD="mtx create admin-platform"
# shellcheck source=../lib/create-from-template.sh
source "$MTX_ROOT/lib/create-from-template.sh"
mtx_create_from_template_run "$@"
