#!/usr/bin/env bash
# MTX dev run-electron: run Electron, kill nodemon on clean exit (from shell-scripts.md §14)
desc="Run Electron; kill nodemon on clean exit"
set -e

cd "$ROOT_/targets/desktop"
cross-env NODE_ENV=development electron "$@"
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
  CURRENT_PID=$$
  while [ $CURRENT_PID -ne 1 ]; do
    PARENT_PID=$(ps -o ppid= -p $CURRENT_PID 2>/dev/null | xargs)
    if [ -z "$PARENT_PID" ] || [ "$PARENT_PID" = "1" ]; then
      break
    fi
    PARENT_CMD=$(ps -o comm= -p $PARENT_PID 2>/dev/null || echo "")
    if echo "$PARENT_CMD" | grep -qi "nodemon"; then
      kill -TERM $PARENT_PID 2>/dev/null || true
      break
    fi
    CURRENT_PID=$PARENT_PID
  done
  pkill -f "nodemon.*run-electron" 2>/dev/null || true
  exit 0
fi

exit $EXIT_CODE
