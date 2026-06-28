#!/usr/bin/env bash
set -euo pipefail

GODOT="${GODOT_BIN:-godot}"

rm -f violations.json

"$GODOT" --headless -s addons/gut/gut_cmdln.gd "$@"
