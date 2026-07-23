# Catch Dog

Catch Dog is a fictional, non-graphic 3D arcade game: ride through a neighborhood, lock onto dogs, throw nets, collect fuel, and stay ahead of pursuing guards. Reach 100 points before time or fuel runs out.

## Status

This repository contains the playable vertical slice. Its release targets are Windows x86_64 and macOS Universal 2. The macOS target includes Intel Macs with AMD GPUs and Apple Silicon.

Release readiness is not implied by source validation: the release owner must still verify signed/notarized macOS distribution and physical Windows and AMD-GPU Mac smoke and performance runs before publishing a build. See [the release checklist](docs/release-checklist.md).

## Setup

- Godot **4.6.3**
- A desktop system capable of running Godot's Forward+ renderer; the project retains an OpenGL 3 fallback.
- Keyboard input. Gamepad and mouse input are not supported in this vertical slice.

`scripts/dev/godot.sh` finds `godot`, `godot4`, or the macOS application bundle. Set `CATCH_DOG_GODOT_BIN` when your executable lives elsewhere.

```sh
export CATCH_DOG_GODOT_BIN="/path/to/Godot"
```

From the repository root:

```sh
scripts/dev/godot.sh --editor --path .
scripts/dev/godot.sh --path .
```

Open `project.godot` in the editor, or run the project with the second command. The main scene is `src/app/main.tscn`.

## Controls

| Key | Action |
| --- | --- |
| Left Arrow | Steer left |
| Right Arrow | Steer right |
| Up Arrow | Accelerate |
| Down Arrow | Brake / decelerate |
| Space | Throw a net at the locked dog |
| Escape | Pause or resume during gameplay |

## Testing

```sh
scripts/dev/godot.sh --headless --path . --script scripts/dev/validate_project.gd
scripts/dev/godot.sh --headless --path . --script tests/test_runner.gd
bash scripts/dev/validate_docs.sh
bash scripts/dev/validate_site.sh
scripts/dev/godot.sh --headless --path . --script scripts/dev/soak_test.gd
```

To run only matching test files, provide a comma-separated filter:

```sh
CATCH_DOG_TEST_FILTER=test_full_session scripts/dev/godot.sh --headless --path . --script tests/test_runner.gd
```

The project validator confirms Godot 4.6, input actions, the main scene, and both export presets. Tests and the soak gate are headless checks; they do not replace an interactive exported-build smoke test.

## Game loop

1. Drive to find an off-camera dog spawn.
2. Put a visible dog in front of the motorcycle to acquire a target lock.
3. Press Space to launch a net. Every launch can alert nearby guards.
4. Capture dogs for points, refuel from pickups, and evade pursuers.
5. Win at 100 points. A run ends on time expiry, guard contact, or stopping with no fuel.

Dog values range from 10-point street dogs to the rarer 50-point Shiba Inu. A session starts with a three-minute timer in the playable build.

## Repository structure

```text
assets/        Source art and license/provenance notes
docs/          Maintenance spec, architecture, performance, and release docs
scripts/dev/   Godot launcher and project validator
scripts/ci/    Pinned Godot installer and deterministic packaging
site/          Dependency-free GitHub Pages landing page
.github/       Validation/build, continuous release, and Pages workflows
src/app/       Application router, menus, and settings
src/session/   Session rules and gameplay composition
src/dogs/      Dog data, spawning, and behavior
src/guards/    Detection and pursuit behavior
src/vehicle/   Motorcycle, camera, fuel, and pickups
src/capture/   Targeting and net capture
src/world/     Neighborhood scene and navigation
src/ui/        HUD, pause, and result screens
tests/         Headless unit and integration suites
```

## Exporting

CI installs the official Linux editor and export templates for Godot 4.6.3, verifies their published SHA-256 digests, validates/tests the project, then exports both archives:

```sh
bash scripts/ci/install_godot.sh
bash scripts/ci/build_exports.sh
sha256sum --check SHA256SUMS.txt
```

On a development machine with Godot 4.6.3 and matching export templates already installed, set `CATCH_DOG_GODOT_BIN` and run only `build_exports.sh`. Outputs are `catch-dog-windows-x86_64.zip`, `catch-dog-macos-universal.zip`, and sorted `SHA256SUMS.txt`. These generated files are ignored by Git.

Pull requests build 14-day CI artifacts. Every successful unique push to
`main` reserves the next patch version, beginning at `v0.1.0`, builds both
platform archives, verifies their checksums, and publishes a GitHub Release.
Concurrent runs retry tag reservation atomically; rerunning the same commit
reuses its tag. A failed run removes only its own unpublished reserved tag.

Enable **Settings → Actions → General → Workflow permissions → Read and write**
so the workflow can create tags and releases. Conventional Commit subjects are
recommended because GitHub uses commit history to generate release notes, but
every `main` push increments the patch version regardless of prefix.

Packaging does not attest that an artifact was launched on a physical machine.

Before publishing, the release owner must complete the owner-only gates in [docs/release-checklist.md](docs/release-checklist.md), including Windows x86_64 and AMD-GPU Mac smoke tests, target-device performance capture, macOS signing, and notarization.

## Troubleshooting

- **Godot not found:** set `CATCH_DOG_GODOT_BIN` to the Godot 4.6.3 executable.
- **Export templates missing:** install the 4.6.3 templates in Godot, or use `scripts/ci/install_godot.sh` on Linux.
- **macOS certificate warning in headless output:** the local runtime can report a system CA lookup warning even when validation exits successfully; judge the command by its exit code and explicit failure lines.
- **Unsigned macOS build will not open normally:** unsigned CI output is for internal verification. Public distribution still requires owner-managed signing, notarization, and Gatekeeper testing.
- **Unexpected local files:** remove only known generated output under `builds/`, `.godot/`, or the named release archives; never discard unrelated work.

## More information

- [Maintenance specification](docs/MAINTENANCE_SPEC.md)
- [Contributing guide](CONTRIBUTING.md)
- [Architecture](docs/architecture.md)
- [Performance guidance](docs/performance.md)
- [Release checklist](docs/release-checklist.md)
- [Asset provenance](assets/LICENSES.md)
- [License](LICENSE)
