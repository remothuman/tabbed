#!/bin/sh
set -e

echo "Building and running Tabbed"


"$(dirname "$0")/build.sh"
echo "Build completed"


# Gracefully quit existing instance so it can run cleanup (e.g. expanding windows).
# If it does not exit in time, force-quit it.
if pgrep -x Tabbed >/dev/null 2>&1; then
  echo "Attempting graceful quit of existing instance"
  pkill -INT -x Tabbed 2>/dev/null || true

  timeout_seconds=3
  elapsed=0
  while pgrep -x Tabbed >/dev/null 2>&1 && [ "$elapsed" -lt "$timeout_seconds" ]; do
    sleep 1
    elapsed=$((elapsed + 1))
  done

  if pgrep -x Tabbed >/dev/null 2>&1; then
    echo "Existing instance did not quit gracefully, force quitting"
    pkill -KILL -x Tabbed 2>/dev/null || true
    sleep 1
  fi

  if pgrep -x Tabbed >/dev/null 2>&1; then
    echo "Error: failed to stop existing Tabbed instance"
    exit 1
  fi

  echo "Existing instance quit"
fi


open build/Build/Products/Debug/Tabbed.app
echo "Tabbed opened"
