#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${CATCH_DOG_GODOT_BIN:-}" ]]; then exec "$CATCH_DOG_GODOT_BIN" "$@"; fi
for candidate in godot godot4 /Applications/Godot.app/Contents/MacOS/Godot; do
  if command -v "$candidate" >/dev/null 2>&1; then exec "$candidate" "$@"; fi
done
echo "Godot 4.6 not found. Set CATCH_DOG_GODOT_BIN to the editor executable." >&2
exit 127
