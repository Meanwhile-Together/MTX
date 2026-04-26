#!/usr/bin/env bash
desc="Scan standalone app -> generate payload import skeleton and warnings (non-destructive)"
nobanner=1
set -euo pipefail

MTX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORKSPACE_ROOT="${MTX_WORKSPACE_ROOT:-$(cd "$MTX_ROOT/.." && pwd)}"
PROJECT_BRIDGE_DIR="${MTX_PROJECT_BRIDGE_DIR:-$WORKSPACE_ROOT/project-bridge}"

target_dir="${1:-}"
output_dir="${2:-}"

if [ -z "$target_dir" ]; then
  echo "Usage: mtx tools import payload <standalone-app-dir> [output-dir]"
  exit 1
fi

if [ ! -d "$PROJECT_BRIDGE_DIR" ]; then
  echo "project-bridge not found at: $PROJECT_BRIDGE_DIR"
  echo "Set MTX_PROJECT_BRIDGE_DIR to a valid checkout."
  exit 1
fi

target_abs="$(cd "$target_dir" && pwd -P)"
if [ -z "$output_dir" ]; then
  output_abs="$target_abs/.mtx-import"
else
  mkdir -p "$output_dir"
  output_abs="$(cd "$output_dir" && pwd -P)"
fi

echo "Import scan (standalone -> payload)"
echo "  target: $target_abs"
echo "  output: $output_abs"
echo "  mode:   non-destructive (existing files are preserved)"

cd "$PROJECT_BRIDGE_DIR"
npx tsx scripts/import-standalone-to-payload.ts --target "$target_abs" --output "$output_abs"

echo "Done. Review:"
echo "  $output_abs/payload-manifest.skeleton.json"
echo "  $output_abs/import-warnings.txt"
echo "  $output_abs/import-plan.json"
