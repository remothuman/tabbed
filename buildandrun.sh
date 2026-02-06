#!/bin/sh
set -e

# Kill existing instance if running
pkill -x Tabbed 2>/dev/null && sleep 0.5 || true

"$(dirname "$0")/build.sh"
open build/Build/Products/Debug/Tabbed.app
