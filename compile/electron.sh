#!/usr/bin/env bash
# MTX compile electron: build desktop app
desc="Build desktop app (Electron)"
set -e
mtx_run npm run build:desktop
