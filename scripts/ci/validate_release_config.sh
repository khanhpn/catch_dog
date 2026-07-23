#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

required_files=(
  export_presets.cfg
  scripts/ci/install_godot.sh
  scripts/ci/build_exports.sh
  scripts/ci/package_checksums.sh
  scripts/ci/next_patch_version.sh
  scripts/ci/set_release_version.sh
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
grep -Fq 'scripts/dev/soak_test.gd' scripts/ci/build_exports.sh
grep -Fq -- '--editor --import' scripts/ci/build_exports.sh
import_line="$(grep -n -m1 -- '--editor --import' scripts/ci/build_exports.sh | cut -d: -f1)"
validator_line="$(grep -n -m1 'scripts/dev/validate_project.gd' scripts/ci/build_exports.sh | cut -d: -f1)"
[[ "$import_line" -lt "$validator_line" ]] || {
  echo "Godot asset import must run before project validation" >&2
  exit 1
}
grep -Fq 'user://test_settings_store.json' tests/integration/test_app_flow.gd

grep -Fq 'branches: [main]' .github/workflows/release.yml
grep -Fq 'scripts/ci/next_patch_version.sh' .github/workflows/release.yml
grep -Fq 'scripts/ci/set_release_version.sh' .github/workflows/release.yml
grep -Fq 'git push origin "refs/tags/${tag}"' .github/workflows/release.yml
grep -Fq 'gh release create "${RELEASE_TAG}"' .github/workflows/release.yml
grep -Fq 'if: failure()' .github/workflows/release.yml
grep -Fq 'git push origin ":refs/tags/${RELEASE_TAG}"' .github/workflows/release.yml

[[ "$(bash scripts/ci/next_patch_version.sh "")" == "0.1.0" ]]
[[ "$(bash scripts/ci/next_patch_version.sh "v0.1.0")" == "0.1.1" ]]
[[ "$(bash scripts/ci/next_patch_version.sh "v1.9.99")" == "1.9.100" ]]
if bash scripts/ci/next_patch_version.sh "invalid" >/dev/null 2>&1; then
  echo "Version calculator must reject malformed tags" >&2
  exit 1
fi

version_fixture="$(mktemp)"
trap 'rm -f "$version_fixture"' EXIT
cp export_presets.cfg "$version_fixture"
bash scripts/ci/set_release_version.sh "0.1.42" "$version_fixture"
[[ "$(grep -Fc '="0.1.42"' "$version_fixture")" -eq 2 ]]
rm -f "$version_fixture"
trap - EXIT

for script in scripts/ci/*.sh scripts/dev/validate_docs.sh scripts/dev/validate_site.sh; do
  bash -n "$script"
done

grep -Fq 'retention-days: 14' .github/workflows/validate-build.yml
grep -Fq 'pages: write' .github/workflows/pages.yml
grep -Fq 'id-token: write' .github/workflows/pages.yml

echo "Release configuration validation passed"
