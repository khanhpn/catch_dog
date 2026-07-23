#!/usr/bin/env bash
set -euo pipefail

readonly GODOT_VERSION="4.6.3"
readonly GODOT_STATUS="stable"
readonly RELEASE_TAG="${GODOT_VERSION}-${GODOT_STATUS}"
readonly RELEASE_BASE="https://github.com/godotengine/godot-builds/releases/download/${RELEASE_TAG}"
readonly EDITOR_ASSET="Godot_v${RELEASE_TAG}_linux.x86_64.zip"
readonly TEMPLATES_ASSET="Godot_v${RELEASE_TAG}_export_templates.tpz"
# Digests published by the official godotengine/godot-builds 4.6.3 release.
readonly EDITOR_SHA256="d0bc2113065e481c9c2c2b2c37daa4e8be3fe9e27f0ab9ab0b6096e9a37907f3"
readonly TEMPLATES_SHA256="3fbe2c0e2dec9d537ab9ec97bcf8da91dcf23357fc51f67092dd068d839290a8"

readonly CACHE_DIR="${CATCH_DOG_GODOT_CACHE:-${PWD}/.cache/godot}"
readonly INSTALL_DIR="${CATCH_DOG_GODOT_INSTALL:-${RUNNER_TEMP:-/tmp}/catch-dog-godot-${GODOT_VERSION}}"
readonly DATA_ROOT="${XDG_DATA_HOME:-${HOME}/.local/share}"
readonly TEMPLATE_DIR="${DATA_ROOT}/godot/export_templates/${GODOT_VERSION}.${GODOT_STATUS}"

mkdir -p "$CACHE_DIR" "$INSTALL_DIR" "$(dirname "$TEMPLATE_DIR")"

download_and_verify() {
  local asset_name="$1"
  local expected_sha="$2"
  local destination="${CACHE_DIR}/${asset_name}"

  if [[ ! -f "$destination" ]]; then
    curl --fail --location --retry 3 --output "$destination" "${RELEASE_BASE}/${asset_name}"
  fi
  printf '%s  %s\n' "$expected_sha" "$destination" | sha256sum --check -
}

download_and_verify "$EDITOR_ASSET" "$EDITOR_SHA256"
download_and_verify "$TEMPLATES_ASSET" "$TEMPLATES_SHA256"

unzip -q -o "${CACHE_DIR}/${EDITOR_ASSET}" -d "$INSTALL_DIR"
editor_source="${INSTALL_DIR}/Godot_v${RELEASE_TAG}_linux.x86_64"
chmod +x "$editor_source"
ln -sfn "$editor_source" "${INSTALL_DIR}/godot"

templates_stage="${INSTALL_DIR}/templates-stage"
rm -rf "$templates_stage" "$TEMPLATE_DIR"
mkdir -p "$templates_stage"
unzip -q "${CACHE_DIR}/${TEMPLATES_ASSET}" -d "$templates_stage"
mv "${templates_stage}/templates" "$TEMPLATE_DIR"
rmdir "$templates_stage"

if [[ -n "${GITHUB_PATH:-}" ]]; then
  printf '%s\n' "$INSTALL_DIR" >> "$GITHUB_PATH"
fi
if [[ -n "${GITHUB_ENV:-}" ]]; then
  printf 'CATCH_DOG_GODOT_BIN=%s\n' "${INSTALL_DIR}/godot" >> "$GITHUB_ENV"
fi

"${INSTALL_DIR}/godot" --version
printf 'Godot %s and export templates installed with verified SHA-256 digests.\n' "$GODOT_VERSION"
