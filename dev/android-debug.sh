#!/usr/bin/env bash
# MTX dev android-debug: run npm run build:android:debug from repo root
set -e
cd "$ROOT_"
exec npm run build:android:debug
