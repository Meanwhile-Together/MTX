#!/usr/bin/env bash
# Same as top-level install.sh — use `mtx payload install` from project-bridge or org-* payload root.
desc="Install a payload and register it in config/server.json (org or project-bridge host)"
nobanner=1
set -e

MTX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../install.sh
exec bash "$MTX_ROOT/install.sh" "$@"
