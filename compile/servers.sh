#!/usr/bin/env bash
# MTX compile servers: build app server and backend server
desc="Build app server and backend server"
set -e
npm run build:server
npm run build:backend-server
