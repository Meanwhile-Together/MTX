#!/usr/bin/env bash
# MTX compile ios: build iOS app
desc="Build iOS app"
set -e
if ! command -v xcodebuild &>/dev/null; then
  echo "⏭️ iOS skipped (no xcodebuild)"
  exit 0
fi
echo "🔨 iOS..."
if ! mtx_run npm run build:mobile:ios; then
  echo "⏭️ iOS build failed; continuing."
  exit 0
fi
echo "✅ ios done"
