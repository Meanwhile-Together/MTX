#!/usr/bin/env bash
# MTX dev run-electron: run the project's desktop dev flow (Electron + nodemon etc.)
desc="Run Electron; kill nodemon on clean exit"
set -e
echo "▶️ Electron desktop..." >&2
mtx_run npm run dev:desktop
