#!/usr/bin/env bash
# Precondition: walk up from cwd looking for a workspace file (*.code-workspace).
# If found, print its location and set MTX_WORKSPACE_FILE / MTX_WORKSPACE_ROOT. Always passes.
set -e

MTX_WORKSPACE_FILE=""
MTX_WORKSPACE_ROOT=""
walk="$(pwd)"
while [ -n "$walk" ] && [ "$walk" != "/" ]; do
  for f in "$walk"/*.code-workspace; do
    if [ -f "$f" ]; then
      MTX_WORKSPACE_FILE="$f"
      MTX_WORKSPACE_ROOT="$walk"
      echo "workspace: $MTX_WORKSPACE_FILE" >&2
      export MTX_WORKSPACE_FILE
      export MTX_WORKSPACE_ROOT
      break 2
    fi
  done
  walk="$(dirname "$walk")"
done
true
