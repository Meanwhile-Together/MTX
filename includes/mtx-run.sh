#!/usr/bin/env bash
# MTX run wrapper: run a command respecting MTX_VERBOSE (1=normal, 2=detail, 3=full, 4=trace).
# At default -v (1), script/precond echoes show but mtx_run subprocess output is suppressed.
# Example: mtx_run npm run build
#          mtx_run "$0" compile vite
mtx_run() {
    local v=${MTX_VERBOSE:-1}
    if [ "$v" -le 1 ]; then
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
