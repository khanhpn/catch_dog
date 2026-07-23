#!/bin/sh
# Dependency-free acceptance check for the static delivery site.
set -eu

SITE_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

test -f "$SITE_DIR/index.html"
test -f "$SITE_DIR/styles.css"
test -f "$SITE_DIR/assets/catch-dog-key-art.png"
test -x "$SITE_DIR/validate_site.sh"

"$SITE_DIR/validate_site.sh"

for required in \
  '<main' \
  'id="game-loop"' \
  'id="dog-tiers"' \
  'id="controls"' \
  'id="platform-status"' \
  'prefers-reduced-motion' \
  'Skip to content' \
  'Downloads are not published yet'; do
  grep -Fq "$required" "$SITE_DIR/index.html" "$SITE_DIR/styles.css"
done

printf '%s\n' 'Site acceptance checks passed.'
