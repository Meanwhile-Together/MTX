#!/usr/bin/env bash
# MTX compile: build all targets (runs all compile/* subcommands)
desc="Build all targets; use mtx compile <vite|electron|android|ios|servers> for one"
set -e
for target in vite electron android ios servers; do
  echo "🔨 $target..."
  mtx_run "$0" compile "$target"
done
echo "✅ compile done"
