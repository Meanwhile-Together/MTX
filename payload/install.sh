#!/usr/bin/env bash
# Canonical: mtx payload install — registers a payload on a host (see docs/MTX_COMMAND_SURFACE.md).
desc="Install a payload and register it in config/server.json (org or project-bridge host)"
nobanner=1
set -e

MTX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/install-payload.sh
source "$MTX_ROOT/lib/install-payload.sh"
mtx_install_payload_main "$@"
