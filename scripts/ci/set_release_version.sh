#!/usr/bin/env bash
set -euo pipefail

readonly version="${1:-}"
readonly preset_file="${2:-export_presets.cfg}"

[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  echo "Invalid release version: $version" >&2
  exit 1
}
[[ -f "$preset_file" ]] || {
  echo "Export preset not found: $preset_file" >&2
  exit 1
}

temporary_file="$(mktemp)"
trap 'rm -f "$temporary_file"' EXIT
awk -v version="$version" '
  /^application\/short_version=/ {
    print "application/short_version=\"" version "\""
    replacements++
    next
  }
  /^application\/version=/ {
    print "application/version=\"" version "\""
    replacements++
    next
  }
  { print }
  END { if (replacements != 2) exit 42 }
' "$preset_file" > "$temporary_file" || {
  echo "Expected exactly two macOS version fields in $preset_file" >&2
  exit 1
}
mv "$temporary_file" "$preset_file"
trap - EXIT
