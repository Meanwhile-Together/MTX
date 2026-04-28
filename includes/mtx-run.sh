#!/usr/bin/env bash
# MTX run wrapper: run a command respecting MTX_VERBOSE (1=normal, 2=detail, 3=full, 4=trace).
# At default -v (1), script/precond echoes show but mtx_run subprocess output is suppressed
# (Terraform, npm, etc. — both stdout and stderr). Use -vv / MTX_VERBOSE>=2 to stream subprocess output.
# On non-zero exit while silenced, a short hint is printed to stderr unless MTX_RUN_SILENT_FAIL_HINT=0.
# Example: mtx_run npm run build
#          mtx_run "$0" compile vite
mtx_run() {
    local v=${MTX_VERBOSE:-1}
    if [ "$v" -le 1 ]; then
        # npm, terraform, and most CLIs log progress to stderr; quiet means both streams.
        "$@" &>/dev/null
        local ec=$?
        if [ "$ec" -ne 0 ] && [ "${MTX_RUN_SILENT_FAIL_HINT:-1}" != "0" ]; then
            echo "" >&2
            echo "💡 A subprocess failed with its output hidden (MTX_VERBOSE=${v:-1}). To see full logs (e.g. Terraform), re-run with higher verbosity:" >&2
            echo "   mtx deploy <environment> -vv        # or -vvv / -vvvv / --verbose" >&2
            echo "   MTX_VERBOSE=2 mtx <same command…>    # same effect as -vv on deploy" >&2
            echo "   (Set MTX_RUN_SILENT_FAIL_HINT=0 to suppress this hint.)" >&2
        fi
        return "$ec"
    elif [ "$v" -eq 4 ]; then
        ( set -x; "$@" )
        return $?
    else
        "$@"
        return $?
    fi
}
