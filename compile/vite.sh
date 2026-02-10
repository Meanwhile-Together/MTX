#!/usr/bin/env bash
# MTX compile vite: build all Vite-based targets (client, desktop renderer, backend, mobile)
desc="Build all Vite-based targets (client, desktop, backend, mobile)"
set -e
mtx_run npm run build:client
mtx_run npm run build:desktop
mtx_run npm run build:backend
mtx_run npm run build:mobile
