#!/usr/bin/env bash
# Runs the headless gameplay smoke test.
#
#   tests/run_tests.sh /path/to/godot
#   GODOT_BIN=/path/to/godot tests/run_tests.sh
#
# Exits with the test's status (0 = all checks passed).
set -euo pipefail

cd "$(dirname "$0")/.."

GODOT="${1:-${GODOT_BIN:-godot}}"
if ! command -v "$GODOT" >/dev/null 2>&1 && [ ! -x "$GODOT" ]; then
	echo "Godot binary not found: $GODOT" >&2
	echo "Pass it as the first argument or set GODOT_BIN." >&2
	exit 1
fi

echo "Importing project assets..."
"$GODOT" --headless --path . --import

exec "$GODOT" --headless --path . res://tests/smoke_test.tscn
