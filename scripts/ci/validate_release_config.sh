#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

required_files=(
  export_presets.cfg
  scripts/ci/install_godot.sh
  scripts/ci/build_exports.sh
  scripts/ci/package_checksums.sh
  .github/workflows/validate-build.yml
  .github/workflows/release.yml
  .github/workflows/pages.yml
)
for file in "${required_files[@]}"; do
  [[ -s "$file" ]] || {
    echo "Missing release configuration: $file" >&2
    exit 1
  }
done

grep -Fq 'name="Windows Desktop"' export_presets.cfg
grep -Fq 'binary_format/architecture="x86_64"' export_presets.cfg
grep -Fq 'name="macOS"' export_presets.cfg
grep -Fq 'binary_format/architecture="universal"' export_presets.cfg
grep -Fq 'readonly GODOT_VERSION="4.6.3"' scripts/ci/install_godot.sh
grep -Eq 'EDITOR_SHA256="[0-9a-f]{64}"' scripts/ci/install_godot.sh
grep -Eq 'TEMPLATES_SHA256="[0-9a-f]{64}"' scripts/ci/install_godot.sh

for script in scripts/ci/*.sh scripts/dev/validate_docs.sh scripts/dev/validate_site.sh; do
  bash -n "$script"
done

grep -Fq 'retention-days: 14' .github/workflows/validate-build.yml
grep -Fq 'tags:' .github/workflows/release.yml
grep -Fq 'pages: write' .github/workflows/pages.yml
grep -Fq 'id-token: write' .github/workflows/pages.yml

echo "Release configuration validation passed"
