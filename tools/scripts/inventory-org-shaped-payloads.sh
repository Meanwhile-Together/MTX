#!/usr/bin/env bash
# List payload-* repos under a workspace that look org-shaped (payloads/ + org prep scripts).
# Usage: MTX_WORKSPACE_ROOT=/path/to/parent-of-payloads ./inventory-org-shaped-payloads.sh
# Or:    ./inventory-org-shaped-payloads.sh /path/to/parent
set -euo pipefail
WS="${1:-${MTX_WORKSPACE_ROOT:-}}"
if [[ -z "$WS" ]]; then
  echo "usage: $0 <workspace-root>   (folder containing payload-*)" >&2
  exit 1
fi
WS=$(cd "$WS" && pwd)
found=0
for d in "$WS"/payload-*; do
  [[ -d "$d" ]] || continue
  base=$(basename "$d")
  [[ "$base" == payload-* ]] || continue
  [[ -d "$d/payloads" ]] || continue
  slug=${base#payload-}
  inner="$d/payloads/$slug"
  [[ -d "$inner" ]] || continue
  org=0
  if [[ -f "$d/config/app.json" ]] || [[ -f "$d/config/org.json" ]]; then
    org=1
  fi
  echo "$base	slug=$slug	org_config=$org	app_dir=$inner"
  found=$((found + 1))
done
if [[ "$found" -eq 0 ]]; then
  echo "(none matched)"
fi
