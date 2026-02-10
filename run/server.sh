#!/usr/bin/env bash
# MTX run server: run backend server in dev (with prisma watch)
desc="Run backend server in dev"
set -e

mtx_run npm run dev:server
