#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

GODOT="${GODOT:-godot}"
"$GODOT" --headless --path . --script addons/gut/gut_cmdln.gd \
  -gconfig=.gutconfig.json \
  -gexit
