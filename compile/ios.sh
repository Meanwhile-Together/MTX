#!/usr/bin/env bash
# MTX compile ios: build iOS app
desc="Build iOS app"
set -e
if ! command -v xcodebuild &>/dev/null; then
  echo "[WARN] xcodebuild not found (not on macOS or Xcode not installed); skipping iOS build."
  exit 0
fi
if ! npm run build:mobile:ios; then
  echo "[WARN] iOS build failed; continuing."
  exit 0
fi
