#!/usr/bin/env bash
# MTX compile vite: build all Vite-based targets (client, desktop renderer, backend, mobile)
desc="Build all Vite-based targets (client, desktop, backend, mobile)"
set -e
npm run build:client
npm run build:desktop
npm run build:backend
npm run build:mobile
