#!/usr/bin/env bash
# MTX compile android: build Android debug APK
desc="Build Android debug APK"
set -e

build_out=$(mktemp)
trap 'rm -f "$build_out"' EXIT

if ! mtx_run npm run build:android:debug >"$build_out" 2>&1; then
  if grep -qE "Could not find method java\(\)|BUILD FAILED" "$build_out" 2>/dev/null; then
    warn "Gradle/cache corrupted; removing android and ios, re-adding with Capacitor, then retrying."
    rm -rf targets/mobile/android targets/mobile/ios
    (cd targets/mobile && npx cap add android && (npx cap add ios || true))
    mtx_run npm run build:mobile
    mtx_run npm run build:android:debug
  else
    cat "$build_out" 1>&2
    exit 1
  fi
fi
