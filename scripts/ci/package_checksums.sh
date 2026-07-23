#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
artifacts=(
  "catch-dog-macos-universal.zip"
  "catch-dog-windows-x86_64.zip"
)

for artifact in "${artifacts[@]}"; do
  [[ -s "$artifact" ]] || {
    echo "Missing release artifact: $artifact" >&2
    exit 1
  }
done

if command -v sha256sum >/dev/null 2>&1; then
  sha256sum "${artifacts[@]}" | LC_ALL=C sort -k2 > SHA256SUMS.txt
else
  shasum -a 256 "${artifacts[@]}" | LC_ALL=C sort -k2 > SHA256SUMS.txt
fi

cat SHA256SUMS.txt
