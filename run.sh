#!/bin/sh
# Installs the hooks, builds the app, and relaunches it.
set -eu
cd "$(dirname "$0")"

./install-hooks.sh
./build.sh
pkill -x ClaudePill || true
open build/ClaudePill.app
