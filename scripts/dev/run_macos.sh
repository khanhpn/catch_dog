#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "run_macos.sh is intended for macOS." >&2
  exit 1
fi

# Run the source project through the installed Godot editor binary. Keeping the
# terminal attached makes GDScript errors and renderer crashes visible.
exec scripts/dev/godot.sh --path . --verbose "$@"
