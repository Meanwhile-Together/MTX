#!/usr/bin/env bash
# Bottom-line in-progress animation on stderr (TTY only) for long mtx deploy phases.
# Disable: MTX_DEPLOY_SPINNER=0. Full stream logging: MTX_VERBOSE>=3 (spinner off).
# Idempotent: mtx_deploy_spinner_stop is safe to call when not running.
MTX_DEPLOY_SPINNER_PID=""

mtx_deploy_spinner_stop() {
  if [ -n "${MTX_DEPLOY_SPINNER_PID:-}" ]; then
    kill "$MTX_DEPLOY_SPINNER_PID" 2>/dev/null || true
    wait "$MTX_DEPLOY_SPINNER_PID" 2>/dev/null || true
    MTX_DEPLOY_SPINNER_PID=""
  fi
  if [ -t 2 ]; then
    # Clear the spinner line
    printf '\r\033[0K' >&2
  fi
}

# Start a background braille+emoji line with elapsed time. label=short string (e.g. staging, upload)
mtx_deploy_spinner_start() {
  local label="${1:-deploy}"
  mtx_deploy_spinner_stop
  [ -t 2 ] || return 0
  [ "${MTX_DEPLOY_SPINNER:-1}" = "0" ] && return 0
  [ "${MTX_VERBOSE:-1}" -ge 3 ] && return 0

  (
    local frames=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
    local moji=(🚂 '✨' '🛤️' '🌤️')
    local i=0 j=0
    local t0=$SECONDS
    while :; do
      local f="${frames[$((i % ${#frames[@]}))]}"
      local m="${moji[$((j % ${#moji[@]}))]}"
      local e=$((SECONDS - t0))
      local em=$((e / 60))
      local es=$((e % 60))
      # Keep on one line; use spaces so a shorter string doesn't leave junk
      printf '\r\033[0K%s  %s  MTX · %s  ·  %02dm %02ds  ·  meanwhile-train chugging…' \
        "$m" "$f" "$label" "$em" "$es" >&2
      # shellcheck disable=SC2034
      i=$((i + 1))
      j=$((j + 1))
      sleep 0.11
    done
  ) &
  MTX_DEPLOY_SPINNER_PID=$!
}
