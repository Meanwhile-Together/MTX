#!/usr/bin/env bash
# MTX run wrapper: run a command respecting MTX_VERBOSE (1=quiet, 2=detail, 3=full, 4=trace).
# Use in scripts so subprocess output is suppressed unless verbosity is 3 or 4.
# Example: mtx_run npm run build
#          mtx_run "$0" compile vite
mtx_run() {
    local v=${MTX_VERBOSE:-1}
    if [ "$v" -le 2 ]; then
        "$@" 1>/dev/null
        return $?
    elif [ "$v" -eq 4 ]; then
        ( set -x; "$@" )
        return $?
    else
        "$@"
        return $?
    fi
}
