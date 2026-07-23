# Catch Dog Maintenance Specification

Status: **Normative**  
Applies to: Godot **4.6.3** project on `main`  
Last verified against source: **2026-07-23**

## 1. Purpose

This document is the authoritative maintenance specification for Catch Dog. It defines the player-visible rules, runtime ownership, public contracts, invariants, extension procedures, validation gates, and release boundaries that maintainers must preserve.

Use the words **MUST**, **MUST NOT**, **SHOULD**, and **MAY** as requirement terms:

- **MUST / MUST NOT**: required for compatibility or correctness.
- **SHOULD / SHOULD NOT**: expected unless a documented reason justifies a change.
- **MAY**: optional and safe within the surrounding constraints.

When this specification conflicts with incidental implementation details, either:

1. change the implementation to satisfy the specification; or
2. intentionally change the product contract, update this specification in the same commit, and add migration or regression coverage.

Do not silently allow the specification and production behavior to diverge.

## 2. Source-of-truth map

| Contract | Primary source |
| --- | --- |
| Product and maintenance contract | `docs/MAINTENANCE_SPEC.md` |
| Runtime ownership and data flow | `docs/architecture.md` |
| Contributor workflow and coding conventions | `CONTRIBUTING.md` |
| Setup, controls, commands, and troubleshooting | `README.md` |
| Gameplay composition | `src/session/gameplay.gd`, `src/session/gameplay.tscn` |
| Session scoring and terminal states | `src/session/game_session.gd` |
| Immutable result boundary | `src/session/session_result.gd` |
| Dog types, scores, and rarity | `src/dogs/dog_catalog.gd` |
| Dog spawning | `src/dogs/spawn_director.gd` |
| Targeting and net capture | `src/capture/` |
| Player motion and fuel | `src/vehicle/` |
| Guard pursuit and replacement | `src/guards/` |
| Map, collision, navigation, and markers | `src/world/` |
| Menus and persisted settings | `src/app/` |
| HUD, pause, and result presentation | `src/ui/` |
| Export platform definitions | `export_presets.cfg` |
| CI, releases, and Pages | `.github/workflows/`, `scripts/ci/` |
| Release evidence still required | `docs/release-checklist.md`, `docs/performance.md` |

Typed resources and production constants are the source of truth for exact numeric values. If a balance change modifies those values, update the relevant tables below in the same change.

## 3. Product contract

### 3.1 Game identity

Catch Dog is a single-player 3D arcade chase game set in a fictional, Vietnamese-inspired residential neighborhood. The player rides a fictional underbone motorcycle, locks onto dogs, and throws a humane capture net while managing fuel and avoiding guards.

Presentation MUST remain fictional and arcade-oriented:

- no real vehicle brands or protected characters;
- no blood, injury, or graphic cruelty;
- captured dogs use clear non-graphic feedback;
- player, dogs, and guards remain readable at normal play distance;
- gameplay state is never communicated by color alone.

### 3.2 Supported platforms

The intended desktop export scope is:

- Windows x86_64;
- macOS Universal 2 (`x86_64` and `arm64`), including Intel/AMD-GPU Macs.

The project MUST remain compatible with keyboard-and-mouse-only play. Forward+ is the primary renderer and the configured OpenGL fallback MUST remain usable unless a replacement support policy is approved and documented.

CI export success is not proof of physical-device compatibility. Windows and target Mac smoke/performance tests remain release-owner gates.

### 3.3 Controls

| Input action | Default key | Contract |
| --- | --- | --- |
| `steer_left` | Left Arrow | Steer left |
| `steer_right` | Right Arrow | Steer right |
| `accelerate` | Up Arrow | Accelerate and consume fuel at the throttle rate |
| `brake` | Down Arrow | Decelerate/brake; MUST NOT behave as forward throttle |
| `throw_net` | Space | Throw one net when a valid lock and cooldown allow it |
| `pause` | Escape | Open/close pause flow idempotently |

Changing a default input requires updates to `project.godot`, tutorial UI, README, site controls, tests, and this table.

## 4. Gameplay rules

### 4.1 Session

The production gameplay session:

- starts with **180 seconds**;
- starts at score **0**;
- wins at exactly **100 points**;
- clamps score to the goal;
- accepts terminal state only once;
- freezes the gameplay runtime after a terminal result;
- presents exactly one result screen;
- supports replay by creating a new session and resetting all owned runtime state.

`Gameplay` explicitly constructs the production `SessionRules` with 180 seconds.
The reusable `session_rules.tres` currently retains a 600-second generic
default for isolated `GameSession` construction; maintainers MUST NOT interpret
that resource default as the playable-session duration.

`GameSession` state is:

```text
RUNNING ── score reaches 100 ──> WON
RUNNING ── time/caught/fuel ───> LOST
WON or LOST ── any later event ─> unchanged
```

Supported result reasons are:

| Result | Reason |
| --- | --- |
| Victory | `score_goal` |
| Timer reaches zero | `time_expired` |
| Active pursuing guard contacts player | `caught` |
| Player stops with empty fuel | `out_of_fuel` |

A terminal result MUST be immutable. Later captures, contacts, timer ticks, or fuel signals MUST NOT replace the original reason or reopen the result screen.

### 4.2 Dog catalog, score, and rarity

The active catalog is:

| Stable ID | Display type | Score | Selection weight | Run-speed multiplier |
| --- | --- | ---: | ---: | ---: |
| `street_dog` | Street dog | 10 | 55 | 0.85 |
| `corgi` | Corgi | 25 | 25 | 0.95 |
| `golden_retriever` | Golden Retriever | 40 | 13 | 1.05 |
| `shiba_inu` | Shiba Inu | 50 | 7 | 1.15 |

The weighted picker MUST:

- reject invalid or non-positive total weights safely;
- use stable catalog ordering;
- make higher-value dogs less common than lower-value dogs;
- return the selected `DogStats`, not a duplicated set of hard-coded values.

A catalog change MUST update:

- player-facing scoring copy in the site/tutorial where applicable;
- weighted-selection tests;
- capture/session integration coverage;
- this table.

### 4.3 Dog lifecycle

`DogAgent` state is:

```text
IDLE ── selected/locked ──> FLEEING
FLEEING ── lock cleared ──> IDLE
IDLE or FLEEING ── valid net hit ──> CAPTURED
CAPTURED ── feedback completes ──> freed/replaced
```

Required behavior:

- a locked dog flees away from the player with bounded lateral variation;
- clearing the lock stops the corresponding flee episode;
- capture is one-shot;
- capture points come from `DogStats`;
- a queued, freed, already captured, or otherwise invalid target cannot score;
- dog collision uses the dedicated dog collision layer;
- capture target height remains explicit so projectiles aim above ground.

### 4.4 Dog spawning

The production population limit is **6 active dogs**. A spawn candidate MUST:

- be an authored typed spawn marker;
- be inside map bounds;
- be at least **20 metres** from the player;
- be outside the active camera frustum;
- be clear of world and dog occupancy;
- not be reserved by another active dog;
- have a non-empty stable marker ID.

When no marker is valid, the director retries after **2 seconds**. It MUST own no more than one pending retry and MUST stop population maintenance while gameplay is frozen or shutting down.

The neighborhood currently authors at least 12 dog markers. Reducing this count requires an explicit map/population design change.

### 4.5 Targeting and net capture

Target selection uses:

- maximum lock range: **24 metres**;
- half-angle: **30 degrees**;
- visibility/line-of-sight validation;
- deterministic candidate ranking;
- a typed `DogAgent` target.

Net throwing uses:

- cooldown: **0.8 seconds**;
- projectile maximum range: **30 metres**;
- projectile default lifetime: **2 seconds**;
- guard detection radius: exactly **45 metres** for every accepted throw.

The guard alert is emitted when a throw is accepted, before hit/miss resolution. A hit and a miss therefore create the same guard detection event. The 45-metre radius MUST NOT become an editor-tunable value without a deliberate product-contract change.

Only dog bodies may resolve a net capture. World geometry, the source player, guards, and unrelated areas MUST NOT generate points.

### 4.6 Player vehicle and fuel

Default player tuning:

| Property | Value |
| --- | ---: |
| Maximum speed | 18 m/s |
| Acceleration | 12 m/s² |
| Steering rate | 2.2 rad/s |
| Visual lean | 0.3 rad |
| Fuel capacity | 100 |
| Idle/low-speed fuel rate | 0.2 |
| Throttle fuel rate | 1.0 |

Fuel rules:

- accelerating consumes fuel faster than coasting;
- fuel is clamped between zero and capacity;
- propulsion cannot continue at zero fuel;
- `stopped_without_fuel` emits once per empty-fuel stop episode;
- collecting a fuel pickup restores **35 units**, clamped to capacity;
- replay restores fuel and the stopped-signal latch through typed reset APIs.

Motion, fuel drain, signal emission, and presentation MUST remain separate enough to test independently. UI code MUST NOT directly mutate the fuel model.

### 4.7 Guards

There are at most **3 non-retired guards**. `GuardAgent` state is:

```text
IDLE ── valid 45 m detection ──> PURSUING
PURSUING ── fuel reaches zero ──> EXHAUSTED
PURSUING ── route cannot recover ──> IDLE
EXHAUSTED ── replacement handoff ──> RETIRED
```

Default guard tuning:

| Property | Value |
| --- | ---: |
| Maximum speed | 15 m/s |
| Acceleration | 20 m/s² |
| Fuel capacity | 30 |
| Idle fuel rate | 0.3 |
| Throttle fuel rate | 3.0 |
| Path refresh | 4 Hz |
| Maximum prediction time | 1.25 s |
| Maximum prediction distance | 12 m |

Guard contracts:

- detection boundary is inclusive at 45 metres;
- pursuit predicts a bounded intercept using player velocity;
- navigation queries validate both route start and route endpoint;
- a partial path to a disconnected target is not a successful route;
- recovery uses the nearest reachable, unused world recovery marker;
- a completed recovery point cannot be selected forever in the same disconnected episode;
- when no useful recovery exists, the guard abandons pursuit without teleporting;
- only the active pursuing guard/target pair can emit player capture;
- fuel exhaustion disables propulsion and capture collision;
- each exhausted guard owns its own **20-second** replacement deadline;
- replacement waits until the exhausted guard and replacement zone are off-camera;
- replacement avoids occupied zones;
- retired guards are disconnected, removed from registries, made non-colliding/invisible, and freed.

Guard fuel is intentionally smaller and drains faster than player fuel. Exhausted guards MUST NOT be refilled and reused.

## 5. World contract

### 5.1 Neighborhood

The neighborhood MUST provide:

- a connected loop road;
- two connected alleys;
- readable yards and dead ends;
- static collision aligned with visible blockers;
- an authored `NavigationRegion3D` and committed navigation resource;
- at least 12 dog markers;
- exactly 6 fuel markers;
- exactly 3 guard zones;
- reachable world recovery markers;
- stable, unique IDs for every gameplay marker.

Visible barriers that imply a blocked route MUST have collision. Physically traversable ground where the player may drive SHOULD be represented by guard navigation unless an explicit gameplay boundary prevents access.

### 5.2 Navigation

`NavigationRegion3D` owns the navigation resource through its Node API. Production code MUST NOT mix cached Node properties with direct region RID mutation or globally force-flush the navigation server.

Navigation coverage MUST:

- include the player spawn;
- include every dog, fuel, guard, and recovery anchor within the guard route tolerance;
- exclude solid building and barrier footprints;
- preserve routes around obstacles;
- reject targets beyond the playable perimeter.

Tests that depend on navigation readiness SHOULD wait for region iteration and a real path probe with a bounded timeout. They MUST NOT treat “region exists” as proof that polygon data has synchronized.

### 5.3 Marker contract

Every gameplay marker MUST:

- use `SpawnPoint` or `WorldMarker`;
- contain a stable, non-empty `StringName` ID;
- use the correct marker kind/group;
- remain unique within the neighborhood;
- be moved together with corresponding navigation/collision changes.

Stable IDs are data contracts. Renaming a scene node is allowed; silently changing a stable ID is not.

## 6. Runtime architecture

### 6.1 Application ownership

`src/app/main.tscn` is the project entry scene. `Main` owns one replaceable screen and routes among:

- main menu;
- tutorial;
- settings;
- gameplay.

Only the app root performs top-level screen replacement. Child screens request navigation through signals; they do not replace the app tree themselves.

### 6.2 Gameplay ownership

`Gameplay` owns and wires:

- the current `GameSession`;
- neighborhood;
- player and camera rig;
- net launcher and projectile root;
- dog spawn director;
- fuel pickup root;
- guard director;
- HUD;
- pause menu;
- result screen;
- audio director.

On replay, `Gameplay` MUST:

1. disconnect the previous session;
2. remove dynamic dogs, pickups, guards, and projectiles;
3. clear director registries/timers;
4. reset player, fuel latch, launcher target/cooldown, and camera smoothing through typed APIs;
5. repopulate authored pickups and guards;
6. create and connect a fresh session;
7. restore HUD/audio/runtime processing;
8. avoid duplicate signal connections and child leaks.

### 6.3 Public signal contracts

The following signatures are public maintenance contracts:

```gdscript
# Session
GameSession.score_changed(score: int)
GameSession.time_changed(seconds: float)
GameSession.session_finished(won: bool, reason: StringName)

# Player
PlayerVehicle.fuel_changed(percent: float)
PlayerVehicle.stopped_without_fuel

# Capture
NetLauncher.target_changed(target: DogAgent)
NetLauncher.net_thrown(origin: Vector3, detection_radius: float)
NetLauncher.capture_confirmed(stats: DogStats)
NetProjectile.capture_confirmed(stats: DogStats)

# Dogs
DogAgent.captured(stats: DogStats)

# Guards
GuardAgent.pursuit_started(guard: GuardAgent)
GuardAgent.pursuit_ended(guard: GuardAgent)
GuardAgent.player_caught
GuardDirector.threat_directions_changed(directions: Array[Vector3])
```

Changing a signal name, parameter type, ordering, or emission timing is a breaking change. Update all consumers, integration coverage, architecture documentation, and this section together.

### 6.4 Result boundary

`SessionResult` is the typed immutable result boundary. A valid result MUST contain:

- `won`;
- `reason`;
- `score`;
- `remaining_time`;
- `captures`.

Cross-field invariants:

- victory uses `score_goal` and score 100;
- a loss cannot use `score_goal`;
- `time_expired` requires remaining time approximately zero;
- score, time, and capture count cannot be negative.

Raw dictionaries MAY be produced only at presentation/serialization boundaries after typed validation.

## 7. Settings and presentation

Settings schema version is **1**, stored under `user://settings.json`.

Supported fields:

| Field | Type/range | Default |
| --- | --- | --- |
| `master_volume` | float 0–1 | 0.8 |
| `music_volume` | float 0–1 | 0.65 |
| `effects_volume` | float 0–1 | 0.8 |
| `fullscreen` | bool | false |
| `resolution` | 1280×720, 1600×900, or 1920×1080 | 1280×720 |
| `graphics_preset` | LOW, MEDIUM, HIGH | MEDIUM |
| `camera_shake` | float 0–1 | 0.65 |
| `reduced_motion` | bool | false |

Invalid fields fall back independently; one corrupt field MUST NOT discard valid neighboring settings. New schema fields require a version/migration decision and corruption coverage.

The HUD MUST show:

- score over 100;
- `mm:ss` time;
- fuel percentage;
- target lock and net cooldown;
- chase warning;
- separate directional threat indicators relative to player/camera heading.

Threat indicators update while actors move and MUST NOT stack invisibly at one position. Reduced-motion preferences apply immediately to supported camera/presentation effects.

Audio uses Master, Music, and Effects buses. Engine/wind layers may respond to vehicle speed and chase intensity may respond to active pursuers. Missing optional audio MUST fail safely without blocking gameplay.

## 8. Coding and commenting rules

Production GDScript MUST:

- use typed parameters, returns, signals, and public state;
- keep one clear owner-facing responsibility per script;
- prefer typed public reset/configuration methods over string-based private mutation;
- centralize meaningful balance values in constants/resources/catalogs;
- guard one-shot signals and terminal transitions;
- fail closed when a required camera, map, target, or physics adapter is unavailable;
- preserve user changes outside the current task;
- avoid hidden global mutable gameplay state.

Comments explain:

- why an invariant exists;
- Godot lifecycle/synchronization constraints;
- non-obvious geometry/math;
- one-shot ownership and cleanup reasoning.

Comments MUST NOT narrate obvious assignments or compensate for unclear naming.

## 9. Extension recipes

### 9.1 Add or rebalance a dog

1. Add/update the `DogStats` entry in `src/dogs/dog_catalog.gd`.
2. Preserve a stable ID.
3. Set score, positive weight, and positive speed multiplier.
4. Confirm rarity remains inversely related to reward unless changing the product rule.
5. Update dog visual mapping where applicable.
6. Update site/tutorial score copy.
7. Run weighted-picker, spawn, capture, and full-session coverage.
8. Update section 4.2.

### 9.2 Add a pickup

1. Place behavior and scene in the owning domain.
2. Add typed world markers with unique stable IDs.
3. Keep marker position on physically reachable ground.
4. Apply effects through the owner; clamp bounded state.
5. Define replay cleanup/repopulation.
6. Cover collection, state change, and repeated replay.

### 9.3 Change vehicle balance

1. Update `player_vehicle_stats.tres` or its typed resource.
2. Preserve correct zero-fuel and brake semantics.
3. Check camera/audio response at minimum and maximum speed.
4. Run vehicle, fuel, session-loss, and gameplay smoke coverage.
5. Update section 4.6.

### 9.4 Change guard behavior

1. Keep transition ownership in `GuardAgent`/`GuardDirector`.
2. Do not bypass typed target lifecycle.
3. Preserve route endpoint validation and non-teleport recovery.
4. Preserve independent exhaustion timers and the three-guard cap.
5. Verify retired instances do not accumulate.
6. Update section 4.7 for contract changes.

### 9.5 Change map geometry

1. Update visible geometry.
2. Update static collision.
3. Update the committed navigation resource.
4. Reproject all gameplay anchors.
5. Preserve connected routes and perimeter exclusion.
6. Run real navigation, spawn occupancy, guard route, and main scene smoke checks.

### 9.6 Add a screen or setting

1. Route screens through `Main`.
2. Provide keyboard focus and Escape/back behavior.
3. Keep pause/navigation idempotent.
4. Version or migrate persisted settings when schema compatibility changes.
5. Provide non-color feedback and reduced-motion behavior.
6. Update section 7 and user-facing documentation.

## 10. Validation contract

### 10.1 Fast change loop

Run the focused test related to the changed domain:

```sh
CATCH_DOG_TEST_FILTER=<filter> scripts/dev/godot.sh \
  --headless --path . --script tests/test_runner.gd
```

Then run:

```sh
scripts/dev/godot.sh --headless --path . --script scripts/dev/validate_project.gd
scripts/dev/godot.sh --headless --path . --script tests/test_runner.gd
bash scripts/dev/validate_docs.sh
bash scripts/dev/validate_site.sh
bash scripts/ci/validate_release_config.sh
git diff --check
```

### 10.2 Soak gate

`scripts/dev/soak_test.gd` exercises:

- 50 session lifecycles;
- 2,000 spawn attempts;
- 500 net events;
- 100 guard lifecycles;
- production active-dog reservation.

The soak gate MUST fail on violated counts or lifecycle/reservation assertions. A headless forced-exit ObjectDB warning is not a substitute for a leak investigation when node counts or repeated runs grow.

### 10.3 Required coverage by change type

| Change | Minimum validation |
| --- | --- |
| Pure documentation | docs/site/release validators and link scan |
| Balance resource | focused domain test, full suite, project validator |
| Scene/UI | focused integration, direct scene smoke, full suite |
| Navigation/map | real NavigationServer route/anchor checks and scene smoke |
| Spawn/capture/guard lifecycle | focused integration and soak |
| Settings | corrupt-field and app-flow integration |
| CI/export | static release validator and a workflow run |
| Release candidate | complete release checklist on target hardware |

Tests SHOULD assert production adapters, physical overlap, route endpoints, and actual signals rather than manually emitting or structurally inspecting behavior when a real adapter can be exercised reliably.

## 11. Delivery and release

### 11.1 CI contract

GitHub Actions MUST:

- use Godot 4.6.3 editor and export templates;
- verify pinned SHA-256 digests before extraction;
- run with least necessary permissions;
- cancel superseded validation builds;
- validate project, tests, docs/site/release configuration;
- export Windows x86_64 and macOS Universal 2;
- create sorted `SHA256SUMS.txt`;
- reject credential-like or repository metadata in archives;
- retain normal build artifacts for 14 days;
- deploy only `site/` to GitHub Pages;
- start version history at `0.1.0`;
- reserve exactly one next patch tag for every unique push to `main`;
- atomically retry tag reservation when release runs overlap;
- reuse the existing tag when the same commit is rerun;
- build and attach both platform archives and checksums before publishing;
- remove only the current run's unpublished tag when that run fails.

Expected artifact names:

- `catch-dog-windows-x86_64.zip`;
- `catch-dog-macos-universal.zip`;
- `SHA256SUMS.txt`.

Release automation uses `scripts/ci/next_patch_version.sh` to calculate the
next version and `scripts/ci/set_release_version.sh` to stamp both macOS export
version fields. The release workflow MUST have repository contents, Pages, and
OIDC write permissions. Its Pages job MUST depend on the release job and deploy
only `site/`. Conventional Commits improve generated notes but MUST NOT control
whether a release occurs: every successful unique `main` push advances the
patch version.

### 11.2 Release-owner gates

Before a public release, the owner MUST complete `docs/release-checklist.md`, including:

- physical Windows x86_64 launch and gameplay smoke;
- physical target Intel/AMD-GPU Mac smoke;
- Universal 2 slice inspection;
- input, victory, each loss reason, settings, replay, and clean quit;
- target-hardware performance measurements;
- signing/notarization decision;
- archive checksum verification;
- license/asset review.

Do not claim these gates from headless tests or unsigned CI artifacts.

## 12. Maintenance invariants checklist

Before merging a behavior change, confirm:

- [ ] Score cannot exceed 100 and terminal state is immutable.
- [ ] Capture points come from the selected `DogStats`.
- [ ] Higher-reward dogs remain rarer unless the product rule changed.
- [ ] Only a valid dog hit scores.
- [ ] Every accepted throw creates one 45-metre guard alert.
- [ ] Player and guard zero-fuel behavior remains terminal for that run/instance.
- [ ] Guard recovery never teleports or loops one spent marker forever.
- [ ] No more than 6 active dogs or 3 non-retired guards exist.
- [ ] Spawn/replacement timers do not stack or share incorrect deadlines.
- [ ] Replay clears dynamic nodes, targets, cooldowns, timers, camera state, and signals.
- [ ] Visible blockers, collision, navmesh, and marker placement agree.
- [ ] HUD threats are current, relative, and spatially distinct.
- [ ] Settings corruption is isolated per field.
- [ ] Optional presentation failures do not block gameplay.
- [ ] Documentation and this specification match the new public behavior.

## 13. Specification change policy

Update this file in the same commit when changing any of:

- controls or supported platforms;
- session duration, score goal, dog score/rarity;
- targeting, net, fuel, vehicle, dog, or guard constants;
- state transitions or terminal reasons;
- public signal signatures or emission timing;
- ownership, reset, cleanup, or replay behavior;
- map marker counts/types, navigation, or collision contracts;
- settings schema or defaults;
- artifact names, export targets, CI gates, or release responsibilities.

For editorial changes that do not alter a contract, no gameplay test is required. For normative changes, the pull request MUST state:

1. the old contract;
2. the new contract;
3. migration or compatibility impact;
4. validation evidence;
5. remaining hardware/release limitations.
