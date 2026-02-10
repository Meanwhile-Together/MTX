#!/usr/bin/env bash
# MTX deploy production: shortcut → mtx deploy manual production
desc="Deploy to production"
set -e
"$0" deploy manual production
