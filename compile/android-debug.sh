#!/usr/bin/env bash
# MTX compile android-debug: build Android debug APK (optional: ADB install)
desc="Build Android debug APK"
set -e

npm run build:android:debug
