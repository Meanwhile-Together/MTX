#!/usr/bin/env bash
# MTX run electron: run desktop dev (Electron + nodemon etc.)
desc="Run Electron desktop dev"
set -e

mtx_run npm run dev:desktop
