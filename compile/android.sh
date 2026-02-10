#!/usr/bin/env bash
# MTX compile android: build Android debug APK
desc="Build Android debug APK"
set -e
mtx_run npm run build:android:debug
