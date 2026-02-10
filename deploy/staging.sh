#!/usr/bin/env bash
# MTX deploy staging: shortcut that runs manual.sh with staging
set -e
exec "$SCRIPT_DIR/manual.sh" staging
