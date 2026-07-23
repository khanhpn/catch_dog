# Contributing to Catch Dog

Read [docs/MAINTENANCE_SPEC.md](docs/MAINTENANCE_SPEC.md) before changing public
gameplay behavior, state transitions, signals, balance constants, navigation,
settings, exports, or release gates.

## Prerequisites

- Godot **4.6.3**. Use the same editor/runtime line as CI and the project validator.
- A Git checkout with no unrelated generated files. Do not commit `.godot/`, exports, builds, logs, or local settings.

Set `CATCH_DOG_GODOT_BIN` if `scripts/dev/godot.sh` cannot find your Godot executable, then open the project with:

```sh
scripts/dev/godot.sh --editor --path .
```

Before submitting a change, run:

```sh
scripts/dev/godot.sh --headless --path . --script scripts/dev/validate_project.gd
scripts/dev/godot.sh --headless --path . --script tests/test_runner.gd
git diff --check
```

Run the relevant focused test first while iterating, for example:

```sh
CATCH_DOG_TEST_FILTER=test_net_capture scripts/dev/godot.sh --headless --path . --script tests/test_runner.gd
```

## Workflow

1. Start from the current integration branch or an issue-approved `codex/<short-name>` branch.
2. Keep a change focused: gameplay behavior, data, scene layout, UI, and documentation should each have a clear purpose.
3. Add or adjust a focused test for changed behavior, then run the full suite and validator.
4. Test the affected screen interactively in the editor when the change affects player-visible behavior.
5. Describe the behavior, validation commands, and any platform limitation in the pull request.

Use concise Conventional Commit subjects, such as
`feat: add dog spawn cooldown` or `fix: reset launcher target on replay`.
These subjects make generated release notes easier to read. Every successful
push to `main` creates the next patch release regardless of commit prefix. Do
not bundle formatting churn, generated files, or unrelated refactors.

## GDScript style

- Write typed GDScript. Give public state, signal parameters, return values, and non-obvious locals useful types.
- Give each script one owner-facing responsibility. Prefer explicit scene ownership and typed setup over global mutable state.
- Use named state transitions and signals for cross-module events. Terminal session transitions must remain idempotent.
- Keep balance data in resources or catalogs, rather than scattering meaningful values through behavior code.
- Preserve stable authored marker IDs and navigation/collision ownership in world scenes.
- Update documentation whenever a public module, input action, folder boundary, or release procedure changes.

## Comments

Use comments for intent, invariants, engine constraints, or non-obvious calculations—not line-by-line narration. A public API should be clear from its names and types; comments explain why a constraint exists.

## Directory ownership

| Area | Responsibility |
| --- | --- |
| `src/app/` | Root routing, menus, settings persistence |
| `src/session/` | Rules, results, and gameplay composition |
| `src/dogs/`, `src/guards/` | Actor data, spawning, fleeing, pursuit |
| `src/vehicle/`, `src/capture/` | Motorcycle/fuel and targeting/net flow |
| `src/world/` | Environment, navigation, collision, authored markers |
| `src/ui/`, `src/audio/` | Player feedback and presentation |
| `tests/` | Headless behavior and integration coverage |
| `scripts/dev/` | Local execution and structural validation |
| `scripts/ci/`, `.github/` | Reproducible exports and repository automation |
| `site/` | Static GitHub Pages source |

## Common changes

### Adding a dog

1. Extend `DogStats` data in `src/dogs/dog_catalog.gd` with a stable ID, score, spawn weight, and run-speed multiplier.
2. Keep weights intentional and update player-facing scoring copy if it changes.
3. Ensure the spawn director still receives valid, off-camera authored markers from `src/world/neighborhood.tscn`.
4. Add boundary or weighted-selection coverage in `tests/unit/` and a spawning/capture behavior check in `tests/integration/` when behavior changes.

### Adding a pickup

1. Put pickup behavior and its scene under `src/vehicle/` unless it owns a different gameplay domain.
2. Add markers through the neighborhood API and preserve collision/navmesh validity.
3. Wire pickup effects through the owning gameplay/session module; clamp player state at its documented bounds.
4. Cover collection, state change, and replay reset in an integration test.

### Guard behavior

1. Change `src/guards/` state and detection logic without bypassing `GuardDirector` ownership.
2. Retain safe navigation failure behavior: recover or abandon pursuit, never teleport through geometry.
3. Test detection, contact, exhaustion, and restart behavior as applicable.

### Add a UI screen or audio cue

1. Put the scene and script under `src/ui/` or `src/audio/` and connect it from its owning app/gameplay scene.
2. Make keyboard focus, Escape/back behavior, reduced-motion behavior, and non-color feedback explicit for UI.
3. Verify missing optional presentation assets fail safely rather than blocking gameplay.

### Change map content or a resource

1. Keep world geometry, static collision, navigation data, and marker placement in sync.
2. Use typed `.tres` resources for reusable tuning; do not mutate shared resource state during a run.
3. Run the affected scene smoke and relevant navigation/spawn integration tests.

## Platform and release boundaries

Source-level checks do not prove a release. The release owner, not a contributor or CI artifact, is responsible for physical Windows x86_64 and AMD-GPU Mac smoke/performance checks and for macOS code signing and notarization. Record the evidence in the release checklist rather than claiming those gates passed without verification.

Merging or pushing a commit to `main` authorizes the continuous-release workflow
to reserve the next patch tag, validate and build that exact commit, and publish
the unsigned platform archives. A failed run publishes no release and removes
its own reserved tag when safe.

## Pull requests

Every pull request should state its scope, affected player behavior, focused and full validation commands, and unverified platform limitations. Link an issue when applicable, keep review changes in the same scope, and do not mark hardware/signing gates complete from CI evidence.
