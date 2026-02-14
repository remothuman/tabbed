#!/bin/sh
set -e

echo "Building and running Tabbed"


"$(dirname "$0")/build.sh"
echo "Build completed"


# Gracefully quit existing instance so it can run cleanup (e.g. expanding windows)
pkill -INT -x Tabbed 2>/dev/null && sleep 1 || true
echo "Existing instance quit"


open build/Build/Products/Debug/Tabbed.app
echo "Tabbed opened"