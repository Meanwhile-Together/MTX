#!/usr/bin/env bash
# MTX dev android-debug: run npm run build:android:debug from repo root
desc="Build Android debug APK (optional: ADB install)"
set -e
npm run build:android:debug
