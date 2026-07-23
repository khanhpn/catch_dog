#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

required_docs=(
  README.md
  CONTRIBUTING.md
  LICENSE
  docs/architecture.md
  docs/performance.md
  docs/release-checklist.md
)
for file in "${required_docs[@]}"; do
  [[ -s "$file" ]] || {
    echo "Missing documentation file: $file" >&2
    exit 1
  }
done

for heading in "## Setup" "## Controls" "## Testing" "## Exporting" "## Repository structure" "## Troubleshooting"; do
  grep -Fq "$heading" README.md || {
    echo "README is missing required section: $heading" >&2
    exit 1
  }
done
for heading in "## GDScript style" "## Comments" "### Adding a dog" "### Adding a pickup" "### Guard behavior" "## Pull requests"; do
  grep -Fq "$heading" CONTRIBUTING.md || {
    echo "CONTRIBUTING is missing required section: $heading" >&2
    exit 1
  }
done

while IFS=: read -r source reference; do
  case "$reference" in
    http://*|https://*|mailto:*|\#*) continue ;;
  esac
  target="${reference%%#*}"
  [[ -z "$target" ]] && continue
  resolved="$(dirname "$source")/$target"
  [[ -e "$resolved" ]] || {
    echo "Broken local documentation link in $source: $reference" >&2
    exit 1
  }
done < <(
  for source in README.md CONTRIBUTING.md docs/*.md; do
    grep -Eo '\[[^][]+\]\([^)]+\)' "$source" \
      | sed -E 's/.*\(([^)]+)\)/\1/' \
      | sed "s|^|$source:|"
  done
)

if rg -n "TBD|TODO|FIXME|localhost|example\\.com" README.md CONTRIBUTING.md docs/architecture.md docs/performance.md docs/release-checklist.md; then
  echo "Placeholder text remains in release documentation" >&2
  exit 1
fi

echo "Documentation validation passed"
