#!/usr/bin/env bash
# MTX run android: build Android debug APK (optional: ADB install)
desc="Build Android debug APK"
set -e
echo "🔨 Android debug..."
mtx_run npm run build:android:debug
echo "✅ android done"
