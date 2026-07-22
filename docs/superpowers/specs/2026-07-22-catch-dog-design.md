# Catch Dog — Game Design and Technical Specification

**Status:** Approved  
**Date:** 2026-07-22  
**Engine:** Godot 4.6, GDScript  
**Platforms:** Windows x86_64 and macOS Universal 2 (Intel x86_64, including AMD-GPU Macs, and Apple Silicon)

## 1. Product Goal

Build a polished 3D arcade vertical slice in which the player rides a fictional underbone motorcycle through a suburban neighborhood, throws nets to capture dogs, manages fuel, and escapes fuel-limited guards. A run lasts at most ten minutes and ends in victory at 100 points.

The vertical slice prioritizes responsive vehicle control, readable targeting, satisfying capture feedback, professional semi-realistic visuals, stable performance, maintainable code, complete documentation, automated builds, and a GitHub Pages presentation site.

The game is fictional arcade entertainment. Dogs are never visibly injured, and capture feedback is non-graphic.

## 2. Scope

### Included in the vertical slice

- One complete, closed-loop 3D neighborhood.
- One player motorcycle with arcade handling.
- Keyboard-only controls.
- Four dog types with weighted random spawning.
- Automatic target locking and net throwing.
- Three active guard zones with fuel-limited pursuit vehicles.
- Player and guard fuel simulation plus fuel pickups.
- A ten-minute session, 100-point victory condition, and explicit loss conditions.
- Main menu, tutorial, pause menu, settings, HUD, and result screen.
- Semi-realistic arcade art direction, sound effects, adaptive chase music, and scalable graphics presets.
- Windows and macOS exports.
- Automated validation, tests, export artifacts, tagged-release packaging, and GitHub Pages deployment.
- Complete README, contributor guide, and architecture documentation.

### Excluded from the vertical slice

- Open world, procedural roads, multiplayer, gamepad support, combat, vehicle upgrades, multiple maps, multiple player vehicles, account systems, online leaderboards, and monetization.

## 3. Player Experience

### 3.1 Core loop

1. Start with a full fuel tank, zero points, and ten minutes.
2. Explore the neighborhood and locate randomly spawned dogs.
3. Position a dog in front of the motorcycle to acquire an automatic target lock.
4. Press `Space` to throw a net.
5. Every throw, whether it hits or misses, emits a detection event to nearby guards.
6. If the net hits, capture the dog, play clear non-graphic feedback, and add its points.
7. Evade guards while managing fuel and collecting roadside fuel pickups.
8. Win immediately on reaching 100 points.

### 3.2 Controls

| Input | Action |
|---|---|
| `Left Arrow` | Steer left |
| `Right Arrow` | Steer right |
| `Up Arrow` | Accelerate; consumes fuel faster |
| `Down Arrow` | Decelerate/brake; reduces fuel consumption |
| `Space` | Throw a net at the locked target |
| `Escape` | Pause or return from a menu |

Mouse input and gamepad input are outside the first release.

### 3.3 Win and loss conditions

- **Win:** score reaches 100 before the timer expires.
- **Lose:** ten minutes expire below 100 points, a pursuing guard vehicle touches the player, or the player reaches zero fuel and the motorcycle comes to a stop before winning.
- Win or loss is committed once. Further collision, score, or timer events are ignored after the terminal state.

## 4. Dogs, Scoring, and Spawning

| Dog type | Points | Spawn weight |
|---|---:|---:|
| Mixed-breed street dog | 10 | 55 |
| Corgi | 25 | 25 |
| Golden Retriever | 40 | 13 |
| Shiba Inu | 50 | 7 |

Weights total 100 and are used as relative probabilities for every valid dog spawn. More valuable dogs are rarer, run faster, and change direction more effectively. Exact movement values live in data resources and are tuned through playtesting without changing behavior code.

Dogs spawn only at authored, validated points such as sidewalks, yards, and alleys. A spawn point must be outside the active camera view, sufficiently far from the player, and free of blocking bodies. When no point is valid, the spawn director waits and retries instead of forcing a bad spawn.

A dog reacts when locked, flees using navigation, and is removed from active play only after a successful net hit. The spawn director replenishes the population after a cooldown in another valid area.

## 5. Targeting and Net Capture

- The targeting system considers only active dogs inside a forward cone, within range, and with an unobstructed line of sight.
- The best target is the closest valid dog to the motorcycle's forward axis, with distance as a tie-breaker.
- The HUD displays a clear target ring and changes its state when a throw is valid.
- `Space` launches one net toward the locked target. A short cooldown prevents spam.
- A throw without a valid target is ignored and gives readable unavailable feedback; it does not create a projectile.
- Once launched, a net throw always emits a guard-detection event, regardless of hit or miss.
- If a target becomes invalid before impact, the projectile continues on its physical trajectory and cannot reference a freed object.
- A successful hit emits exactly one capture event, awards points once, and returns the net object to its pool.

## 6. Vehicle and Fuel

The motorcycle uses custom arcade movement rather than fully simulated motorcycle balance. Steering remains stable and readable at low and high speeds, and visual leaning is separate from the collision body's stable orientation.

- Holding acceleration raises speed toward the current top-speed limit and consumes fuel at the high rate.
- Coasting or braking consumes fuel at the low idle rate.
- Remaining fuel scales the available top speed downward, so the motorcycle becomes progressively weaker rather than stopping abruptly.
- A fuel pickup restores 35 percentage points, clamped to 100%.
- At zero fuel, propulsion is disabled, the motorcycle coasts to a stop, and the session is lost if victory has not already occurred.
- Fuel drain, acceleration, braking, steering response, and top-speed curves are data-driven tuning values.

## 7. Guards and Pursuit

- Three guards patrol or wait in authored zones.
- Every launched net produces a detection event with world position and radius.
- A guard inside the radius enters pursuit, mounts or activates a vehicle, and requests a navigation path toward the player.
- Pursuers periodically refresh their path, choose a reachable intercept, and attempt contact rather than attacking.
- A guard vehicle has a smaller fuel capacity than the player's vehicle. Strong acceleration consumes its fuel faster.
- At zero fuel, a guard stops, exits the threat state, and cannot capture the player.
- Twenty seconds after a guard is exhausted, a replacement becomes eligible to spawn in another off-camera zone; the exhausted guard never refills in view.
- If navigation fails, a guard moves toward the nearest reachable recovery point or abandons the pursuit. It never teleports through geometry.

Guard contact ends the session immediately. The HUD shows chase state and directional threat indicators without revealing guards that have not detected the player.

## 8. Neighborhood and Presentation

The map contains a main road, connected side streets, alleys, yards, a fuel area, landmarks, shortcuts, and safe turning space. Routes form loops so pursuit can be escaped through driving skill, while authored dead ends are clearly readable and never contain mandatory objectives.

The camera uses a low third-person rear view. It smoothly follows position and yaw, leans subtly during turns, pulls back with speed, and uses collision avoidance to prevent clipping through buildings.

The visual direction is **semi-realistic arcade**:

- Believable proportions and surface materials.
- Golden-hour lighting, soft shadows, restrained haze, and selective reflections.
- Exaggerated motion feedback, readable silhouettes, and strong gameplay contrast.
- Dog rarity communicated through target-ring presentation and audio rather than unnatural coat recoloring.
- Graphics presets reduce shadow distance, reflection quality, volumetrics, particles, and draw distance in a controlled order.

Audio includes engine pitch driven by speed, wind, braking, net launch and impact, dog vocalizations, fuel pickup feedback, pursuit warnings, and music intensity tied to chase state.

## 9. Menus and HUD

The main menu provides Play, Tutorial, Settings, and Quit. Settings include master/music/effects volume, resolution, fullscreen, graphics preset, and camera shake strength. The pause menu provides Resume, Restart, Settings, and Main Menu.

The HUD shows score out of 100, remaining time, player fuel, locked-target state, throw cooldown, chase state, and directional guard warnings. Critical states use shape, motion, iconography, and sound in addition to color.

The result screen shows victory or loss reason, captured dogs by type, final score, remaining time, and actions to replay or return to the main menu.

## 10. Technical Architecture

### 10.1 Runtime modules

- `GameSession`: owns time, score, state transitions, pause, win, and loss.
- `PlayerVehicle`: owns input interpretation, arcade motion, fuel, and collision reporting.
- `NetLauncher`: owns target selection, throw cooldown, projectile launch, and capture handoff.
- `DogAgent`: owns dog state, flee behavior, navigation, and capture eligibility.
- `GuardAgent`: owns detection response, pursuit state, navigation, guard fuel, and exhaustion.
- `SpawnDirector`: owns weighted selection, spawn validation, population limits, cooldowns, and pickups.
- `Neighborhood`: exposes navigation regions, authored spawn groups, recovery points, and map bounds.
- `HUD`: observes session and actor signals and renders player-facing state.
- `AudioDirector`: maps gameplay state to music layers and global one-shot cues.

### 10.2 Data and communication

Dog, vehicle, guard, spawn, and difficulty parameters are typed custom `Resource` assets. Scenes consume these resources rather than embedding balance values in scripts.

Modules communicate through typed signals such as `net_thrown`, `dog_captured`, `chase_started`, `fuel_changed`, and `session_finished`. Direct references are reserved for clear ownership relationships. Global state is limited to the scene/router and settings services; gameplay rules do not depend on broad mutable singletons.

The runtime data flow is:

1. Player input updates `PlayerVehicle` and requests a throw from `NetLauncher`.
2. `NetLauncher` chooses a valid dog, launches a projectile, and emits detection data.
3. Guards within the event radius enter pursuit.
4. Projectile collision validates the dog and emits one capture event.
5. `GameSession` applies points and evaluates terminal conditions.
6. `HUD`, audio, spawning, and result presentation react through signals.

### 10.3 Code quality rules

- Use typed GDScript for public APIs, state, signal parameters, return values, and non-obvious local values.
- Each script has one clear responsibility and a small public surface.
- Names describe intent; boolean names read as conditions; units are present in names where ambiguity is possible.
- Comments explain design intent, constraints, formulas, state transitions, and engine workarounds. Comments do not merely restate a line of code.
- Public modules and data resources include concise doc comments describing usage and invariants.
- Constants replace meaningful literals. Balance values belong in resources.
- Dependencies are injected through scene ownership, exported typed references, or explicit setup methods.
- State machines use named states and guarded transitions rather than scattered boolean combinations.
- Object pooling is used for frequently spawned projectiles and short-lived effects after profiling confirms allocation pressure.
- No warning is ignored without a documented reason.

## 11. Rendering and Platform Strategy

Forward+ is the primary renderer because the game targets desktop 3D and benefits from advanced lighting. The project retains Godot's rendering fallback and provides a Low preset that avoids depending on expensive effects for gameplay readability. Compatibility behavior is verified separately because fallback rendering can look different.

Official Godot macOS export templates produce Universal 2 applications supporting Intel x86_64 and Apple Silicon. The Windows target is x86_64. Release exports are created from explicit presets stored in the repository.

References:

- [Godot renderer overview](https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html)
- [Godot 4.6 macOS export documentation](https://docs.godotengine.org/en/4.6/tutorials/export/exporting_for_macos.html)

Downloaded macOS builds require code signing and notarization for normal Gatekeeper distribution. Signing credentials are never committed and are supplied through protected CI secrets when available. Unsigned CI artifacts remain suitable for internal testing with the documented macOS security limitation.

## 12. Robustness

- Runtime references are validated before use and cleared on actor exit.
- Scores and fuel values are clamped to their valid ranges.
- Terminal session state is idempotent.
- Spawn requests fail closed and retry later.
- Navigation failures recover or abort without teleportation.
- Missing optional audio or presentation effects log a clear warning but do not break gameplay.
- Missing required scenes, resources, input actions, or export templates fail validation with actionable messages.
- Saveable settings are versioned, validated on load, and reset only invalid fields to defaults.

## 13. Testing and Acceptance Criteria

### 13.1 Automated tests

- Unit-level tests cover fuel drain curves, fuel clamping, scores, weighted selection boundaries, target eligibility, capture idempotency, timer expiry, and the 100-point victory transition.
- Scene integration tests cover target locking, hit and miss results, guard detection radius, pursuit/exhaustion, valid spawning, pickup collection, and menu-to-session transitions.
- Headless soak tests simulate repeated spawning and session restarts to detect leaked nodes, invalid references, and impossible spawn states.
- Project validation checks required resources, input actions, export presets, broken scene references, and script parse errors.

### 13.2 Manual acceptance

- A full loop works from menu to play, victory or each loss reason, result, and replay without restarting the application.
- Controls remain responsive at low fuel and high frame time.
- No capture awards points twice.
- Dogs, guards, pickups, and nets do not spawn inside geometry.
- The game targets 60 FPS at 1080p on the Medium preset and stays at or above 30 FPS on the Low preset on the target AMD-GPU Mac. Final preset values are accepted only after profiling on that machine.
- Windows x86_64 and macOS Universal 2 artifacts launch and complete a smoke-test session.

## 14. Repository Documentation

`README.md` is the primary entry point and includes the game pitch, screenshots or video, features, controls, supported platforms, system requirements, Godot version, project setup, run/test/export commands, repository layout, troubleshooting, artifact downloads, and documentation links.

`CONTRIBUTING.md` defines prerequisites, branch and commit conventions, pull-request workflow, GDScript style, commenting expectations, test requirements, directory ownership, and step-by-step instructions for adding or modifying a dog type, pickup, guard behavior, UI screen, audio cue, map content, and data resource.

`docs/architecture.md` describes runtime modules, scene ownership, signals, data flow, state machines, resource schemas, error strategy, rendering presets, CI boundaries, and extension points. Documentation changes accompany public API or folder-structure changes.

## 15. GitHub Pages Site

The repository includes a responsive static landing page with:

- Game title, short pitch, and hero media.
- Core gameplay loop and feature highlights.
- Semi-realistic arcade screenshots or concept art.
- Controls and platform support.
- Development status and a download link to the latest published release when available.
- Links to the repository, README, contributor guide, and license.

The site is accessible without a build-time secret, supports narrow and desktop layouts, respects reduced-motion preferences, and is deployed by a dedicated GitHub Pages workflow.

## 16. GitHub Actions

### Pull requests and pushes

- Validate project structure and parse scripts.
- Run automated tests headlessly.
- Build Windows x86_64 and macOS Universal 2 from committed export presets.
- Upload versioned build artifacts with bounded retention.
- Fail with an actionable error when export templates or required resources are missing.

### Tags and releases

- A version tag reruns validation and tests.
- Successful builds are packaged with platform-appropriate names and checksums.
- Release assets are attached to the corresponding GitHub release.
- Signing and notarization execute only when protected secrets are configured; secrets and certificates never enter source control or ordinary build artifacts.

### Pages

- Changes to the landing-page source run validation.
- Successful changes publish through GitHub's official Pages artifact and deployment flow.
- The workflow declares minimal permissions and prevents overlapping deployments.

## 17. Definition of Done

The vertical slice is complete only when all approved gameplay rules are implemented, the visual and performance acceptance criteria pass on target hardware, automated tests pass, both platform artifacts are produced, the GitHub Pages site deploys, and README, contributor, and architecture documentation accurately match the repository.
