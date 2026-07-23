#!/usr/bin/env bash
set -euo pipefail

readonly current_tag="${1:-}"
if [[ -z "$current_tag" ]]; then
  echo "0.1.0"
  exit 0
fi

version="${current_tag#v}"
if [[ ! "$version" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  echo "Invalid release tag: $current_tag" >&2
  exit 1
fi

echo "${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.$((10#${BASH_REMATCH[3]} + 1))"
