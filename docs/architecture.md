# Architecture

The normative gameplay and maintenance contracts live in
[MAINTENANCE_SPEC.md](MAINTENANCE_SPEC.md). This document explains the current
architecture that implements those contracts.

## Overview

Catch Dog is a Godot 4.6.3 project built around a scene-owned runtime. `res://src/app/main.tscn` is the configured entry point. `Main` replaces a single screen-root child to switch among the main menu, tutorial, settings, and `res://src/session/gameplay.tscn`; it loads persisted settings before gameplay begins.

The game uses Forward+ as its primary desktop renderer and retains Godot's OpenGL fallback. Windows x86_64 and macOS Universal 2 are the intended export scope. Performance and visual acceptance on physical Windows and AMD-GPU Mac hardware are release gates, not an implication of this architecture.

## Runtime ownership

| Owner | Owns / coordinates |
| --- | --- |
| `src/app/main.gd` | Screen routing and settings application |
| `src/session/gameplay.gd` | Session lifecycle, gameplay wiring, replay reset, terminal freeze |
| `src/session/game_session.gd` | Time, score, and exactly-once win/loss transition |
| `src/vehicle/player_vehicle.gd` | Keyboard-driven arcade motion, fuel, and contact reporting |
| `src/capture/net_launcher.gd` | Target selection, cooldown, projectile launch, capture handoff |
| `src/dogs/spawn_director.gd` / `dog_agent.gd` | Weighted dog selection, valid spawning, flee lifecycle |
| `src/guards/guard_director.gd` / `guard_agent.gd` | Detection, pursuit, recovery, exhaustion, threat data |
| `src/world/neighborhood.gd` | Authored map markers, navigation, and recovery/guard-zone access |
| `src/ui/` | HUD, pause, and result presentation |
| `src/audio/audio_director.gd` | Runtime engine, wind, and chase intensity layers |

`Gameplay` owns the replaceable `GameSession`, player, launcher, dog/guard directors, fuel-pickup and projectile roots, HUD, pause UI, result UI, audio director, and neighborhood references. A replay disconnects the previous session, clears dynamic actors/projectiles, restores runtime state, repopulates authored objects, and starts a new session.

## Data flow

```text
Keyboard input → PlayerVehicle → NetLauncher → target / projectile
                                      │              │
                                      └→ guard detection   └→ capture
                                                              │
World markers → SpawnDirector / GuardDirector ───────────────┤
                                                              ↓
                         GameSession ← score, time, fuel, contact
                              │
                              ├→ HUD / AudioDirector
                              └→ immutable SessionResult → ResultScreen
```

Modules use direct references only across clear ownership boundaries and otherwise communicate with typed signals. Examples include launcher capture/target signals, player fuel signals, guard-contact signals, and `GameSession.session_finished`. After a terminal result, gameplay disables its runtime subtree so later collisions, score events, or timer ticks cannot replace the result.

## State and resources

`GameSession` has `RUNNING`, `WON`, and `LOST` states. It clamps score to the goal and translates loss causes into `time_expired`, `caught`, or `out_of_fuel`. `SessionResult` validates the boundary payload used by the result screen.

Reusable balance data is typed `Resource` data. `DogStats` holds the stable dog ID, score, weight, and run-speed multiplier; `DogCatalog` supplies the active entries. Vehicle, guard, and session tuning follow the same resource-oriented boundary where applicable. Authored world markers expose stable IDs and positions to spawning and recovery logic.

Settings are managed by `SettingsStore` and stored as versioned JSON under `user://settings.json`. It independently validates persisted values before applying audio, window, graphics, and motion preferences. Settings are local runtime data and are not source-controlled.

## World, navigation, and rendering

`src/world/neighborhood.tscn` contains the playable map's visible geometry, static collision, authored markers, and a committed navigation resource. Runtime uses the authored navigation map; it does not generate a broad walkable plane. Dogs and guards should recover or abandon invalid routes rather than teleporting through geometry.

Graphics presets are applied when gameplay starts. The current Low preset disables glow/fog and lowers directional-shadow distance; other presets retain the higher shadow distance. The project configuration is 1280×720 with 60 physics ticks per second. These are implementation settings, not measured frame-rate claims; see [performance guidance](performance.md).

## Extension rules

- Add gameplay behavior inside its owning domain and provide typed signals for observers.
- Keep session terminal conditions centralized in `GameSession`/`Gameplay`.
- Keep reusable tuning in resources and preserve stable world marker IDs.
- Update tests for behavior changes, and update this document when changing ownership, public signals, input actions, or folder boundaries.
- Treat builds, signing, notarization, and target-hardware verification as release-system concerns. They do not belong in runtime gameplay logic.

## Validation and delivery boundaries

`scripts/dev/validate_project.gd` checks the engine line, required inputs, main scene, and the committed Windows/macOS export presets. `tests/test_runner.gd` discovers typed unit and integration suites. `scripts/dev/soak_test.gd` repeatedly resets the composed gameplay scene and exercises high-volume domain lifecycles. The static site has a dependency-free validator.

GitHub Actions uses the official Godot 4.6.3 Linux editor and export templates
after verifying pinned SHA-256 digests. Pull requests produce bounded-retention
archives. Every successful unique `main` push atomically reserves the next
patch tag, builds that commit, and publishes its GitHub Release; failed runs
remove only their own unpublished tag. A dependent job then deploys only
`site/` to Pages, so build or release failure blocks deployment. CI artifacts
remain unsigned and do not satisfy physical hardware, macOS signing,
notarization, or performance gates.
