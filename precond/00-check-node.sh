#!/usr/bin/env bash
# Precondition: Node.js available (mtx scripts assume npm/node)
# Log your own error and exit non-zero if check fails.
set -e
if ! command -v node &>/dev/null; then
  echo "❌ precondition failed: node not found (install Node.js)" >&2
  exit 1
fi
if ! command -v npm &>/dev/null; then
  echo "❌ precondition failed: npm not found (install npm)" >&2
  exit 1
fi
