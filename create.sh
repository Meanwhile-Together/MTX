#!/usr/bin/env bash
# Normative: mtx create <payload|org|template> … — see https://github.com/Meanwhile-Together/project-bridge/blob/main/docs/MTX_COMMAND_SURFACE.md.
# Optional name: `mtx create org Hello World!` / `mtx create payload foo` — args are plain English (joined if multiple words); org flow slugifies to org-* (org- prefix optional, never doubled).
# `mtx create template` → snapshot cwd payload into template-* (run from payload root; see https://github.com/Meanwhile-Together/project-bridge/blob/main/docs/MTX_SCAFFOLDING_MODEL.md).
# Legacy: `mtx create` with no kind keyword still runs the payload flow (prefer `mtx create payload`).
desc="Create payload-*, org-*, or template-* repos (mtx create <type>)"
nobanner=1
set -e

MTX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
declare -F warn >/dev/null || warn() { echo "[WARN] $*" >&2; }

# Defensive dispatch when invoked directly (outside mtx wrapper).
case "${1:-}" in
  payload)
    shift
    export MTX_CREATE_VARIANT=payload
    # shellcheck source=create/payload.sh
    source "$MTX_ROOT/create/payload.sh" "$@"
    return 0 2>/dev/null || exit 0
    ;;
  org)
    shift
    export MTX_CREATE_VARIANT=org
    # shellcheck source=create/org.sh
    source "$MTX_ROOT/create/org.sh" "$@"
    return 0 2>/dev/null || exit 0
    ;;
  template)
    shift
    # shellcheck source=create/template.sh
    source "$MTX_ROOT/create/template.sh" "$@"
    return 0 2>/dev/null || exit 0
    ;;
esac

if [ -n "${1:-}" ]; then
  warn "[MTX] Prefer explicit kind: mtx create payload … (see mtx help create / https://github.com/Meanwhile-Together/project-bridge/blob/main/docs/MTX_COMMAND_SURFACE.md)" >&2
fi

export MTX_CREATE_VARIANT="${MTX_CREATE_VARIANT:-payload}"
export MTX_REPO_PREFIX="payload-"
export MTX_TEMPLATE_REPO="${MTX_PAYLOAD_TEMPLATE_REPO:-template-payload}"
export MTX_KIND_LABEL="Payload"
export MTX_CREATE_CMD="mtx create payload"

# shellcheck source=lib/create-from-template.sh
source "$MTX_ROOT/lib/create-from-template.sh"
mtx_create_from_template_run "$@"
