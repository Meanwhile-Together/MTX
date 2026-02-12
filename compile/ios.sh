#!/usr/bin/env bash
# MTX compile ios: build iOS app
desc="Build iOS app"
set -e
if ! command -v xcodebuild &>/dev/null; then
  echo "⏭️ iOS skipped (no xcodebuild)" >&2
  exit 0
fi
echo "🔨 iOS..." >&2
if ! mtx_run npm run build:mobile:ios; then
  echo "⏭️ iOS build failed; continuing." >&2
  exit 0
fi
echo "✅ ios done" >&2