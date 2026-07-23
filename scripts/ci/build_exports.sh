#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
readonly GODOT_BIN="${CATCH_DOG_GODOT_BIN:-godot}"

# A Git checkout intentionally excludes `.godot/`. Import assets before any
# script loads scenes that depend on generated texture resources.
"$GODOT_BIN" --headless --editor --import --path .
"$GODOT_BIN" --headless --path . --script scripts/dev/validate_project.gd
"$GODOT_BIN" --headless --path . --script tests/test_runner.gd
"$GODOT_BIN" --headless --path . --script scripts/dev/soak_test.gd

mkdir -p builds/windows builds/macos
find builds/windows builds/macos -mindepth 1 -maxdepth 1 -delete
rm -f catch-dog-windows-x86_64.zip catch-dog-macos-universal.zip SHA256SUMS.txt

"$GODOT_BIN" --headless --path . --export-release "Windows Desktop" builds/windows/CatchDog.exe
"$GODOT_BIN" --headless --path . --export-release "macOS" builds/macos/CatchDog.zip

[[ -s builds/windows/CatchDog.exe ]] || {
  echo "Windows export did not produce builds/windows/CatchDog.exe" >&2
  exit 1
}
[[ -s builds/macos/CatchDog.zip ]] || {
  echo "macOS export did not produce builds/macos/CatchDog.zip" >&2
  exit 1
}

(
  cd builds/windows
  zip -q -r ../../catch-dog-windows-x86_64.zip .
)
cp builds/macos/CatchDog.zip catch-dog-macos-universal.zip

for archive in catch-dog-windows-x86_64.zip catch-dog-macos-universal.zip; do
  if unzip -Z1 "$archive" | grep -E '(^|/)(\.git|\.env|settings\.json)(/|$)' >/dev/null; then
    echo "Forbidden repository or credential-like data found in $archive" >&2
    exit 1
  fi
done

bash scripts/ci/package_checksums.sh
