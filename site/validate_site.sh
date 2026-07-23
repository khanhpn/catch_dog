#!/bin/sh
# Validate the GitHub Pages bundle without requiring Node, a network connection, or a build tool.
set -eu

SITE_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
HTML="$SITE_DIR/index.html"
CSS="$SITE_DIR/styles.css"
ASSET="$SITE_DIR/assets/catch-dog-key-art.png"

fail() { printf '%s\n' "Site validation failed: $1" >&2; exit 1; }
require_text() { grep -Fq "$1" "$2" || fail "missing '$1' in $(basename "$2")"; }

test -s "$HTML" || fail "index.html is missing or empty"
test -s "$CSS" || fail "styles.css is missing or empty"
test -s "$ASSET" || fail "local key art is missing or empty"

for text in '<main id="main-content"' '<section class="hero"' 'id="game-loop"' 'id="dog-tiers"' 'id="controls"' 'id="platform-status"' 'Download for Windows' 'Download for macOS' 'releases/latest/download/catch-dog-windows-x86_64.zip' 'releases/latest/download/catch-dog-macos-universal.zip' 'Skip to content'; do
  require_text "$text" "$HTML" || true
done
if grep -Fq 'Downloads are not published yet.' "$HTML"; then
  fail "published builds must not be described as unavailable"
fi
require_text 'prefers-reduced-motion' "$CSS"
require_text 'src="assets/catch-dog-key-art.png"' "$HTML"
require_text 'href="styles.css"' "$HTML"
require_text '<meta name="viewport"' "$HTML"

H1_COUNT=$(grep -Eo '<h1([[:space:]>])' "$HTML" | wc -l | tr -d ' ')
test "$H1_COUNT" -eq 1 || fail "expected exactly one h1, found $H1_COUNT"
grep -Eq '<img[^>]+alt="[^"]+"' "$HTML" || fail "content images need non-empty alt text"

if grep -Eq '<(script|iframe|embed|object)[[:space:]>]' "$HTML"; then
  fail "external runtime markup is not permitted"
fi
if grep -Eq 'http://' "$HTML" "$CSS"; then
  fail "mixed-content HTTP URLs are not permitted"
fi

for ref in $(grep -Eo 'href="#[A-Za-z0-9_-]+"' "$HTML" | sed 's/href="#//;s/"//'); do
  grep -Fq "id=\"$ref\"" "$HTML" || fail "anchor '#$ref' has no target"
done

for local_ref in styles.css assets/catch-dog-key-art.png; do
  test -s "$SITE_DIR/$local_ref" || fail "local target '$local_ref' is missing"
done

printf '%s\n' 'Site validation passed: local files, semantics, accessibility, and link targets.'
