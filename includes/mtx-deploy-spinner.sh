#!/usr/bin/env bash
# One-line status on stderr: phase label, org display name, time, ASCII spinner (fixed width; no emoji).
# Args: mtx_deploy_spinner_start <phase> [org_name]
# Disable: MTX_DEPLOY_SPINNER=0. Full tool logs: MTX_VERBOSE>=3.
MTX_DEPLOY_SPINNER_PID=""

# Clip for narrow terminals (keep line stable; avoid layout jump from long org names)
mtx_deploy_spinner_clip_org() {
  local s="${1:-}"
  s="${s//$'\n'/ }"
  s="${s//$'\r'/ }"
  if [ "${#s}" -le 40 ]; then
    printf '%s' "$s"
  else
    printf '%s…' "${s:0:39}"
  fi
}

mtx_deploy_spinner_stop() {
  local had=0
  if [ -n "${MTX_DEPLOY_SPINNER_PID:-}" ]; then
    had=1
    kill "$MTX_DEPLOY_SPINNER_PID" 2>/dev/null || true
    wait "$MTX_DEPLOY_SPINNER_PID" 2>/dev/null || true
    MTX_DEPLOY_SPINNER_PID=""
  fi
  # End the in-place status line only if we were drawing; avoids blank stderr lines and extra spacing when code calls stop "just in case".
  if [ "$had" = 1 ] && { [ -t 2 ] || [ -w /dev/tty ] 2>/dev/null; }; then
    printf '\r\033[2K\n' >&2
  fi
}

# phase = short string (e.g. staging, database, railway-up). org = display name (org.name / app name).
mtx_deploy_spinner_start() {
  local phase="${1:-deploy}"
  local org_raw="${2:-}"
  local org
  org="$(mtx_deploy_spinner_clip_org "$org_raw")"
  [ -n "$org" ] || org="—"

  mtx_deploy_spinner_stop
  [ -t 2 ] || return 0
  [ "${MTX_DEPLOY_SPINNER:-1}" = "0" ] && return 0
  [ "${MTX_VERBOSE:-1}" -ge 3 ] && return 0

  # Fixed-width: single ASCII char cycles (- \ | /) — no emoji, no braille (width-stable in all fonts).
  (
    local sp='-\|/'
    local i=0
    local t0=$SECONDS
    while :; do
      local c="${sp:$((i % 4)):1}"
      local e=$((SECONDS - t0))
      local em=$((e / 60))
      local es=$((e % 60))
      printf '\r\033[2K  %s  deploy · %s  ·  %02dm %02ds  ·  %s' \
        "$c" "$phase" "$em" "$es" "$org" >&2
      i=$((i + 1))
      sleep 0.2
    done
  ) &
  MTX_DEPLOY_SPINNER_PID=$!
  # Initial draw (so line exists before first sleep)
  printf '\r\033[2K  %s  deploy · %s  ·  %02dm %02ds  ·  %s' \
    '-' "$phase" 0 0 "$org" >&2
}
