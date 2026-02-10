#!/usr/bin/env bash
# MTX compile servers: build app server and backend server
desc="Build app server and backend server"
set -e
mtx_run npm run build:server
mtx_run npm run build:backend-server
