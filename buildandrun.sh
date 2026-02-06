#!/bin/sh
set -e
"$(dirname "$0")/build.sh"
open build/Build/Products/Debug/Tabbed.app
