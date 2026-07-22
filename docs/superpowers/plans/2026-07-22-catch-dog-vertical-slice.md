# Catch Dog Vertical Slice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a polished, documented, tested Godot 4.6 vertical slice that plays from menu to result, exports Windows and macOS artifacts, and publishes a GitHub Pages landing page.

**Architecture:** Build the game from typed, data-driven Godot scenes with pure domain services for deterministic rules and scene-level adapters for physics, navigation, UI, and audio. Use signals for gameplay events, explicit ownership for dependencies, a small custom headless test runner, and committed export presets. Ship repository documentation, a static site, and least-privilege GitHub Actions workflows as first-class deliverables.

**Tech Stack:** Godot 4.6.3, typed GDScript, Godot Physics, NavigationServer3D, HTML/CSS/vanilla JavaScript, Bash, GitHub Actions.

## Global Constraints

- Support Windows x86_64 and macOS Universal 2, including Intel Macs with AMD GPUs.
- Use Forward+ as the primary renderer and preserve the OpenGL Compatibility fallback.
- Keyboard controls are Arrow keys, Space, and Escape; mouse and gamepad input are excluded.
- A run lasts 600 seconds, wins at 100 points, and loses on timer expiry, guard contact, or stopping at zero fuel.
- Dog score/weight pairs are street dog 10/55, Corgi 25/25, Golden Retriever 40/13, and Shiba Inu 50/7.
- Every launched net alerts nearby guards whether it hits or misses.
- Three guard zones exist; guard vehicles have finite fuel and stop pursuing at zero.
- Fuel pickups restore 35 percentage points.
- Use typed APIs, focused files, data resources, guarded state transitions, and comments that explain intent or invariants.
- Keep animals unharmed and all capture feedback non-graphic.
- Do not commit credentials, certificates, generated exports, `.godot/`, or visual-companion state.

## File Map

- `project.godot`: renderer, input map, main scene, display, and physics configuration.
- `scripts/dev/godot.sh`: locate Godot 4.6 consistently on developer machines and CI.
- `scripts/dev/validate_project.gd`: headless validation of required actions, scenes, and resources.
- `tests/test_runner.gd`: discovers and executes `test_*` methods.
- `tests/unit/`: deterministic rule tests without rendered scenes.
- `tests/integration/`: scene and signal integration tests.
- `src/app/`: application routing, settings, menus, and result flow.
- `src/session/`: session rules and terminal-state ownership.
- `src/vehicle/`: arcade motorcycle, fuel model, camera rig, and pickup.
- `src/dogs/`: dog data, agents, weighted choice, and spawn director.
- `src/capture/`: target selection, launcher, and net projectile.
- `src/guards/`: detection, guard state machine, vehicle pursuit, and replacement policy.
- `src/world/`: neighborhood scene, authored markers, navigation, and environment.
- `src/ui/`: HUD and reusable presentation components.
- `src/audio/`: engine, effects, and chase-music direction.
- `assets/`: project-owned models, materials, textures, audio, icons, and fonts with license metadata.
- `docs/architecture.md`: ownership, signals, state machines, data flow, and extension points.
- `site/`: GitHub Pages landing page and optimized media.
- `.github/workflows/`: validation/build/release and Pages deployment.

---

### Task 1: Reproducible Godot Project Foundation

**Files:**
- Create: `project.godot`
- Create: `src/app/main.tscn`
- Create: `src/app/main.gd`
- Create: `scripts/dev/godot.sh`
- Create: `scripts/dev/validate_project.gd`
- Create: `tests/test_runner.gd`
- Create: `tests/test_case.gd`
- Create: `tests/unit/test_foundation.gd`
- Modify: `.gitignore`

**Interfaces:**
- Produces: `Main.change_screen(scene: PackedScene) -> void`
- Produces: `tests/test_runner.gd --run-tests` process contract: exit `0` when all tests pass, `1` otherwise.
- Produces: optional `CATCH_DOG_TEST_FILTER` comma-separated suite-name filter.
- Produces: `scripts/dev/godot.sh` command wrapper honoring `CATCH_DOG_GODOT_BIN`.

- [ ] **Step 1: Write the failing foundation test**

```gdscript
# tests/unit/test_foundation.gd
extends "res://tests/test_case.gd"

func test_required_actions_exist() -> void:
    for action: StringName in [&"steer_left", &"steer_right", &"accelerate", &"brake", &"throw_net", &"pause"]:
        assert(InputMap.has_action(action), "Missing input action: %s" % action)
```

- [ ] **Step 2: Add the runtime wrapper, test base, and minimal runner; then run the red test**

```gdscript
# tests/test_case.gd
extends Node
class_name TestCase

var failure_messages: PackedStringArray = []

func check(condition: bool, message: String) -> void:
    if not condition:
        failure_messages.append(message)

# tests/test_runner.gd
extends SceneTree

func _init() -> void:
    var failures := 0
    var filters := OS.get_environment("CATCH_DOG_TEST_FILTER").split(",", false)
    for path in _test_files("res://tests"):
        if not filters.is_empty():
            var matched := false
            for filter: String in filters:
                matched = matched or path.contains(filter)
            if not matched:
                continue
        var suite: TestCase = load(path).new()
        root.add_child(suite)
        for method in suite.get_method_list():
            var name := String(method.name)
            if name.begins_with("test_"):
                suite.call(name)
        failures += suite.failure_messages.size()
        for message in suite.failure_messages:
            printerr("FAIL %s: %s" % [path, message])
        suite.queue_free()
    quit(failures)

func _test_files(root: String) -> PackedStringArray:
    var found := PackedStringArray()
    var dir := DirAccess.open(root)
    for entry in dir.get_files():
        if entry.begins_with("test_") and entry.ends_with(".gd") and entry not in ["test_runner.gd", "test_case.gd"]:
            found.append(root.path_join(entry))
    for child in dir.get_directories():
        found.append_array(_test_files(root.path_join(child)))
    return found
```

```bash
#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${CATCH_DOG_GODOT_BIN:-}" ]]; then exec "$CATCH_DOG_GODOT_BIN" "$@"; fi
for candidate in godot godot4 /Applications/Godot.app/Contents/MacOS/Godot; do
  if command -v "$candidate" >/dev/null 2>&1; then exec "$candidate" "$@"; fi
done
echo "Godot 4.6 not found. Set CATCH_DOG_GODOT_BIN to the editor executable." >&2
exit 127
```

Run: `CATCH_DOG_GODOT_BIN=/absolute/path/to/Godot scripts/dev/godot.sh --headless --script tests/test_runner.gd`  
Expected: non-zero exit with missing input action assertion.

- [ ] **Step 3: Create the Godot 4.6 project and application root**

Set `config_version=5`, main scene `res://src/app/main.tscn`, Forward+ renderer, OpenGL fallback enabled, 1280×720 viewport, physics tick 60, and define the six actions with Arrow/Space/Escape physical keys. `Main` owns a single `screen_root: Node` and implements:

```gdscript
func change_screen(scene: PackedScene) -> void:
    for child: Node in screen_root.get_children():
        child.queue_free()
    screen_root.add_child(scene.instantiate())
```

- [ ] **Step 4: Add project validation**

`validate_project.gd` must check engine major/minor `4.6`, required input actions, main scene existence, and parse/load failures, printing one actionable line per failure.

- [ ] **Step 5: Run foundation verification**

Run: `scripts/dev/godot.sh --headless --path . --script tests/test_runner.gd`  
Expected: all foundation tests pass and exit `0`.

Run: `scripts/dev/godot.sh --headless --path . --script scripts/dev/validate_project.gd`  
Expected: `Project validation passed`.

- [ ] **Step 6: Commit**

```bash
git add project.godot src/app scripts/dev tests .gitignore
git commit -m "build: scaffold Godot project and test runner"
```

### Task 2: Deterministic Gameplay Rules and Data Resources

**Files:**
- Create: `src/dogs/dog_stats.gd`
- Create: `src/dogs/dog_catalog.gd`
- Create: `src/dogs/weighted_picker.gd`
- Create: `src/vehicle/fuel_model.gd`
- Create: `src/session/game_session.gd`
- Create: `src/session/session_rules.tres`
- Create: `tests/unit/test_weighted_picker.gd`
- Create: `tests/unit/test_fuel_model.gd`
- Create: `tests/unit/test_game_session.gd`

**Interfaces:**
- Produces: `WeightedPicker.pick_index(weights: PackedFloat32Array, roll: float) -> int`
- Produces: `FuelModel.consume(delta: float, throttle: float) -> void`, `refill(amount: float) -> void`, `top_speed_scale() -> float`
- Produces: `GameSession.add_capture(points: int) -> void`, `tick(delta: float) -> void`, `finish_loss(reason: LossReason) -> void`
- Produces signals: `score_changed(score: int)`, `time_changed(seconds: float)`, `session_finished(won: bool, reason: StringName)`

- [ ] **Step 1: Write failing pure-rule tests**

```gdscript
func test_weight_boundaries() -> void:
    var weights := PackedFloat32Array([55.0, 25.0, 13.0, 7.0])
    assert(WeightedPicker.pick_index(weights, 0.00) == 0)
    assert(WeightedPicker.pick_index(weights, 0.55) == 1)
    assert(WeightedPicker.pick_index(weights, 0.80) == 2)
    assert(WeightedPicker.pick_index(weights, 0.93) == 3)

func test_refill_clamps_and_low_fuel_reduces_speed() -> void:
    var fuel := FuelModel.new(100.0, 1.0, 4.0)
    fuel.consume(10.0, 1.0)
    assert(fuel.amount == 60.0)
    assert(fuel.top_speed_scale() < 1.0)
    fuel.refill(35.0)
    assert(fuel.amount == 95.0)

func test_score_100_finishes_once() -> void:
    var session := GameSession.new()
    session.add_capture(50)
    session.add_capture(50)
    session.add_capture(50)
    assert(session.score == 100)
    assert(session.state == GameSession.State.WON)
```

- [ ] **Step 2: Run tests and verify red state**

Run: `scripts/dev/godot.sh --headless --path . --script tests/test_runner.gd`  
Expected: load failures for undefined rule classes.

- [ ] **Step 3: Implement minimal typed domain objects**

```gdscript
static func pick_index(weights: PackedFloat32Array, roll: float) -> int:
    assert(not weights.is_empty())
    var total := 0.0
    for weight in weights: total += maxf(weight, 0.0)
    var cursor := clampf(roll, 0.0, 0.999999) * total
    for index in weights.size():
        cursor -= maxf(weights[index], 0.0)
        if cursor < 0.0: return index
    return weights.size() - 1
```

Implement `FuelModel` as `RefCounted`, clamp `amount` to `[0, capacity]`, consume `lerpf(idle_rate, throttle_rate, absf(throttle))`, and return top-speed scale `lerpf(0.35, 1.0, amount / capacity)`. Implement `GameSession` with named `RUNNING/WON/LOST` states, 600 seconds, 100-point goal, idempotent terminal transitions, and score clamped to 100.

- [ ] **Step 4: Add exact dog catalog resources**

Create four `DogStats` resources with ids `street_dog`, `corgi`, `golden_retriever`, and `shiba_inu`; assign score/weight `10/55`, `25/25`, `40/13`, `50/7`; set relative run-speed multipliers `0.85`, `0.95`, `1.05`, `1.15`.

- [ ] **Step 5: Run tests and commit**

Run: `scripts/dev/godot.sh --headless --path . --script tests/test_runner.gd`  
Expected: all deterministic rule tests pass.

```bash
git add src/dogs src/vehicle/fuel_model.gd src/session tests/unit
git commit -m "feat: add data-driven session fuel and dog rules"
```

### Task 3: Player Motorcycle, Camera, and Fuel Pickup

**Files:**
- Create: `src/vehicle/player_vehicle.gd`
- Create: `src/vehicle/player_vehicle.tscn`
- Create: `src/vehicle/camera_rig.gd`
- Create: `src/vehicle/fuel_pickup.gd`
- Create: `src/vehicle/fuel_pickup.tscn`
- Create: `src/vehicle/player_vehicle_stats.gd`
- Create: `src/vehicle/player_vehicle_stats.tres`
- Create: `tests/integration/test_player_vehicle.gd`

**Interfaces:**
- Consumes: `FuelModel` from Task 2.
- Produces: `PlayerVehicle.fuel_percent() -> float`, `refill_fuel(amount: float) -> void`, `is_stopped_without_fuel() -> bool`
- Produces signals: `fuel_changed(percent: float)`, `stopped_without_fuel`

- [ ] **Step 1: Write failing movement/fuel integration tests**

```gdscript
func test_acceleration_consumes_more_than_coasting() -> void:
    var vehicle := preload("res://src/vehicle/player_vehicle.tscn").instantiate()
    add_child(vehicle)
    var initial := vehicle.fuel_percent()
    vehicle.simulate_controls(1.0, 0.0, 1.0)
    var accelerated := initial - vehicle.fuel_percent()
    vehicle.refill_fuel(100.0)
    vehicle.simulate_controls(0.0, 0.0, 1.0)
    var coasted := 1.0 - vehicle.fuel_percent()
    assert(accelerated > coasted)
```

- [ ] **Step 2: Run the focused test and confirm it fails**

Run: `CATCH_DOG_TEST_FILTER=test_player_vehicle scripts/dev/godot.sh --headless --path . --script tests/test_runner.gd`  
Expected: missing player vehicle scene.

- [ ] **Step 3: Implement custom arcade movement**

Use `CharacterBody3D`; read Arrow actions in `_physics_process`; calculate forward speed with `move_toward`, yaw from steer input scaled down at very low speed, gravity, and `move_and_slide`. Keep visual lean on a child pivot only. Expose this deterministic seam:

```gdscript
func simulate_controls(throttle: float, steer: float, delta: float) -> void:
    fuel.consume(delta, throttle)
    var speed_limit := stats.max_speed_mps * fuel.top_speed_scale()
    forward_speed = move_toward(forward_speed, throttle * speed_limit, stats.acceleration_mps2 * delta)
    rotation.y -= steer * stats.steer_radians_per_second * delta * speed_ratio()
```

Configure camera smoothing, speed pullback, subtle turn roll, and a `ShapeCast3D` camera collision probe. Add useful comments only at the collision recovery and visual/body separation invariants.

- [ ] **Step 4: Implement pickup and terminal fuel signal**

`FuelPickup` uses `Area3D`; on player body entry call `refill_fuel(35.0)`, emit `collected`, disable collision immediately, and queue free after its effect completes. Emit `stopped_without_fuel` only once when fuel is zero and horizontal speed is below `0.2 m/s`.

- [ ] **Step 5: Verify and commit**

Run: `CATCH_DOG_TEST_FILTER=test_player_vehicle scripts/dev/godot.sh --headless --path . --script tests/test_runner.gd`  
Expected: movement/fuel/pickup tests pass.

```bash
git add src/vehicle tests/integration/test_player_vehicle.gd
git commit -m "feat: add arcade motorcycle camera and fuel pickup"
```

### Task 4: Dogs, Navigation, and Weighted Spawning

**Files:**
- Create: `src/dogs/dog_agent.gd`
- Create: `src/dogs/dog_agent.tscn`
- Create: `src/dogs/spawn_director.gd`
- Create: `src/dogs/spawn_point.gd`
- Create: `tests/integration/test_dog_spawning.gd`

**Interfaces:**
- Consumes: `DogCatalog`, `WeightedPicker`.
- Produces: `DogAgent.begin_flee(threat_position: Vector3) -> void`, `capture() -> bool`
- Produces: `SpawnDirector.request_dog_spawn() -> DogAgent`
- Produces signal: `DogAgent.captured(stats: DogStats)`

- [ ] **Step 1: Write failing spawn and capture tests**

```gdscript
func test_capture_is_idempotent() -> void:
    var dog := preload("res://src/dogs/dog_agent.tscn").instantiate()
    assert(dog.capture())
    assert(not dog.capture())

func test_director_rejects_visible_or_blocked_markers() -> void:
    var director := SpawnDirector.new()
    director.set_test_markers([visible_marker, blocked_marker, valid_marker])
    assert(director.choose_spawn_marker() == valid_marker)
```

- [ ] **Step 2: Run red tests**

Run: `CATCH_DOG_TEST_FILTER=test_dog_spawning scripts/dev/godot.sh --headless --path . --script tests/test_runner.gd`  
Expected: missing dog and director classes.

- [ ] **Step 3: Implement dog state machine**

Use named `IDLE/FLEEING/CAPTURED` states. `begin_flee` requests a navigation target away from the threat with bounded random lateral variation. `_physics_process` follows `NavigationAgent3D.get_next_path_position()`. `capture()` guards the state transition, disables collision/navigation, emits once, plays feedback, and frees after the effect.

- [ ] **Step 4: Implement validated weighted spawning**

Markers are valid only when outside the camera frustum, at least 20 meters from the player, inside map bounds, and clear by `PhysicsShapeQueryParameters3D`. Choose dog stats using one RNG roll and catalog weights. Keep six active dogs; on failure schedule one retry after two seconds rather than recursing.

- [ ] **Step 5: Verify and commit**

Run: `CATCH_DOG_TEST_FILTER=test_dog_spawning scripts/dev/godot.sh --headless --path . --script tests/test_runner.gd`  
Expected: capture and spawn validation tests pass.

```bash
git add src/dogs tests/integration/test_dog_spawning.gd
git commit -m "feat: add fleeing dogs and weighted spawn director"
```

### Task 5: Automatic Targeting and Net Projectile

**Files:**
- Create: `src/capture/target_selector.gd`
- Create: `src/capture/net_launcher.gd`
- Create: `src/capture/net_projectile.gd`
- Create: `src/capture/net_projectile.tscn`
- Create: `tests/unit/test_target_selector.gd`
- Create: `tests/integration/test_net_capture.gd`

**Interfaces:**
- Consumes: `DogAgent.capture()`.
- Produces: `TargetSelector.select(origin: Transform3D, dogs: Array[DogAgent], space: PhysicsDirectSpaceState3D) -> DogAgent`
- Produces: `TargetSelector.select_from_candidates(origin: Transform3D, dogs: Array[DogAgent], has_line_of_sight: Callable) -> DogAgent` as the deterministic test seam used by `select`.
- Produces: `NetLauncher.try_throw() -> bool`
- Produces signals: `target_changed(target: DogAgent)`, `net_thrown(origin: Vector3, detection_radius: float)`, `capture_confirmed(stats: DogStats)`

- [ ] **Step 1: Write failing target and projectile tests**

```gdscript
func test_prefers_dog_closest_to_forward_axis() -> void:
    var selected := selector.select_from_candidates(Transform3D.IDENTITY, [side_dog, front_dog])
    assert(selected == front_dog)

func test_hit_awards_one_capture_and_miss_still_emits_throw() -> void:
    launcher.try_throw()
    assert(throw_events == 1)
    projectile.simulate_hit(dog)
    projectile.simulate_hit(dog)
    assert(capture_events == 1)
```

- [ ] **Step 2: Run red tests**

Run: `CATCH_DOG_TEST_FILTER=target,net scripts/dev/godot.sh --headless --path . --script tests/test_runner.gd`  
Expected: missing targeting and net classes.

- [ ] **Step 3: Implement selection and lock lifecycle**

Filter active dogs to a 30-degree half-angle forward cone, 24-meter range, and unobstructed ray. Rank by angular error then distance. Store the lock as `WeakRef`, clear it on exit/capture, and emit only when the selected identity changes.

- [ ] **Step 4: Implement launch, cooldown, and idempotent hit**

Use a 0.8-second cooldown. A valid throw instantiates or checks out one projectile, snapshots target position/velocity for initial aim, and emits `net_thrown` before impact. The projectile uses `Area3D`, one guarded `resolved` flag, a 30-meter lifetime/range limit, and calls `DogAgent.capture()` only after type/state validation.

- [ ] **Step 5: Verify and commit**

Run: `CATCH_DOG_TEST_FILTER=target,net scripts/dev/godot.sh --headless --path . --script tests/test_runner.gd`  
Expected: all targeting and capture tests pass.

```bash
git add src/capture tests/unit/test_target_selector.gd tests/integration/test_net_capture.gd
git commit -m "feat: add auto-targeting and net capture"
```

### Task 6: Guard Detection, Pursuit, and Exhaustion

**Files:**
- Create: `src/guards/guard_stats.gd`
- Create: `src/guards/guard_stats.tres`
- Create: `src/guards/guard_agent.gd`
- Create: `src/guards/guard_agent.tscn`
- Create: `src/guards/guard_director.gd`
- Create: `tests/integration/test_guard_pursuit.gd`

**Interfaces:**
- Consumes: `NetLauncher.net_thrown`, player global position, `FuelModel`.
- Produces: `GuardAgent.on_detection(position: Vector3, radius: float) -> void`
- Produces signals: `pursuit_started(guard: GuardAgent)`, `pursuit_ended(guard: GuardAgent)`, `player_caught`

- [ ] **Step 1: Write failing guard tests**

```gdscript
func test_hit_and_miss_both_start_nearby_guard() -> void:
    launcher.net_thrown.emit(Vector3.ZERO, 45.0)
    assert(near_guard.state == GuardAgent.State.PURSUING)
    assert(far_guard.state == GuardAgent.State.IDLE)

func test_guard_stops_when_fuel_is_empty() -> void:
    guard.begin_pursuit(player)
    guard.simulate_pursuit(guard.fuel.capacity / guard.stats.throttle_fuel_rate)
    assert(guard.state == GuardAgent.State.EXHAUSTED)
```

- [ ] **Step 2: Run red tests**

Run: `CATCH_DOG_TEST_FILTER=test_guard_pursuit scripts/dev/godot.sh --headless --path . --script tests/test_runner.gd`  
Expected: missing guard classes.

- [ ] **Step 3: Implement guarded state machine and pursuit**

Use `IDLE/PURSUING/EXHAUSTED/RETIRED`. Detection starts only inside the 45-meter event radius. Refresh `NavigationAgent3D.target_position` four times per second, steer toward the next path point, and use a bounded predicted intercept based on player velocity. Fuel drains through `FuelModel`; at zero, propulsion and capture collision are disabled and `pursuit_ended` emits once.

- [ ] **Step 4: Implement director and replacement policy**

Author exactly three guard-zone markers. `GuardDirector` routes detection to guards, aggregates HUD threat direction, and schedules one off-camera replacement 20 seconds after exhaustion. It never exceeds three non-retired guards.

- [ ] **Step 5: Verify and commit**

Run: `CATCH_DOG_TEST_FILTER=test_guard_pursuit scripts/dev/godot.sh --headless --path . --script tests/test_runner.gd`  
Expected: detection, fuel exhaustion, contact, and replacement-cap tests pass.

```bash
git add src/guards tests/integration/test_guard_pursuit.gd
git commit -m "feat: add fuel-limited guard pursuit"
```

### Task 7: Playable Neighborhood and End-to-End Session

**Files:**
- Create: `src/world/neighborhood.tscn`
- Create: `src/world/neighborhood.gd`
- Create: `src/world/environment.tres`
- Create: `src/session/gameplay.tscn`
- Create: `src/session/gameplay.gd`
- Create: `src/ui/hud.tscn`
- Create: `src/ui/hud.gd`
- Create: `src/ui/result_screen.tscn`
- Create: `src/ui/result_screen.gd`
- Create: `tests/integration/test_full_session.gd`

**Interfaces:**
- Consumes all gameplay modules from Tasks 2–6.
- Produces: playable `res://src/session/gameplay.tscn` and result payload `{won, reason, score, remaining_time, captures}`.

- [ ] **Step 1: Write failing full-session tests**

```gdscript
func test_100_points_wins_and_freezes_gameplay_once() -> void:
    gameplay.capture_for_test(50)
    gameplay.capture_for_test(50)
    gameplay.capture_for_test(10)
    assert(gameplay.session.state == GameSession.State.WON)
    assert(gameplay.result_open_count == 1)

func test_timer_guard_and_empty_fuel_have_distinct_loss_reasons() -> void:
    assert(gameplay.simulate_timeout() == &"time_expired")
    gameplay.reset_for_test()
    assert(gameplay.simulate_guard_contact() == &"caught")
```

- [ ] **Step 2: Run red test**

Run: `CATCH_DOG_TEST_FILTER=test_full_session scripts/dev/godot.sh --headless --path . --script tests/test_runner.gd`  
Expected: missing gameplay scene.

- [ ] **Step 3: Assemble the graybox neighborhood**

Build a looped main road, two connected alleys, yards, readable dead ends, collision, a baked `NavigationRegion3D`, at least twelve dog markers, six fuel markers, three guard zones, and recovery points. Use project-owned primitive graybox meshes first; every authored marker carries a typed script and stable id.

- [ ] **Step 4: Wire gameplay ownership and HUD**

`Gameplay` creates/owns `GameSession`, player, directors, map, HUD, and result flow. Connect capture points to `GameSession.add_capture`, physics ticks to `tick`, guard contact to `finish_loss(CAUGHT)`, and stopped-without-fuel to `finish_loss(OUT_OF_FUEL)`. HUD displays `score/100`, `mm:ss`, fuel bar, lock/cooldown state, chase warning, and directional threats.

- [ ] **Step 5: Verify full loop and commit**

Run: `CATCH_DOG_TEST_FILTER=test_full_session scripts/dev/godot.sh --headless --path . --script tests/test_runner.gd`  
Expected: win, all loss reasons, idempotent result, and replay tests pass.

Run: `scripts/dev/godot.sh --path . --editor` then play menu → session → result → replay manually.  
Expected: no script errors and complete flow using graybox assets.

```bash
git add src/world src/session src/ui tests/integration/test_full_session.gd
git commit -m "feat: assemble playable neighborhood session"
```

### Task 8: Menus, Settings, Audio, and Visual Polish

**Files:**
- Create: `src/app/main_menu.tscn`
- Create: `src/app/main_menu.gd`
- Create: `src/app/settings_store.gd`
- Create: `src/app/settings_menu.tscn`
- Create: `src/app/settings_menu.gd`
- Create: `src/app/tutorial_screen.tscn`
- Create: `src/audio/audio_director.gd`
- Create: `src/audio/audio_director.tscn`
- Create: `assets/LICENSES.md`
- Modify: `src/world/neighborhood.tscn`
- Modify: `src/vehicle/player_vehicle.tscn`
- Modify: `src/dogs/dog_agent.tscn`
- Test: `tests/integration/test_app_flow.gd`

**Interfaces:**
- Produces: `SettingsStore.load_settings()`, `save_settings()`, `apply_graphics_preset(preset: Preset)`.
- Produces signals: `AudioDirector.chase_intensity_changed(value: float)`.

- [ ] **Step 1: Write failing settings/app-flow tests**

Test invalid settings fields reset independently, menu actions navigate correctly, pause is idempotent, reduced camera shake applies immediately, and Low preset disables volumetric fog/reflections while retaining readable shadows.

- [ ] **Step 2: Run red tests**

Run: `CATCH_DOG_TEST_FILTER=test_app_flow scripts/dev/godot.sh --headless --path . --script tests/test_runner.gd`  
Expected: missing menu/settings implementations.

- [ ] **Step 3: Implement menus and versioned settings**

Store versioned JSON under `user://settings.json`; validate each field and preserve valid neighbors. Implement master/music/effects volume, fullscreen, resolution, Low/Medium/High graphics preset, and camera shake strength. Wire Play, Tutorial, Settings, Quit, Resume, Restart, and Main Menu.

- [ ] **Step 4: Replace graybox presentation incrementally**

Add licensed/project-owned semi-realistic modular street assets, fictional underbone motorcycle, four readable dog variants, guard vehicle, fuel pickup, golden-hour environment, restrained haze, LODs, occlusion culling, baked static lighting where appropriate, and collision proxies. Record every external asset, author, license, source URL, and modified filename in `assets/LICENSES.md`.

- [ ] **Step 5: Add layered audio and accessibility feedback**

Drive engine pitch and wind from speed, route effects/music buses, crossfade chase music from active pursuit count, and combine color with icons/motion/sound for target, fuel, and threat states. Respect reduced-motion setting.

- [ ] **Step 6: Verify and commit**

Run full headless tests and manually inspect all three graphics presets at 1280×720 and 1920×1080.  
Expected: tests pass, no missing-resource warnings, menus remain keyboard accessible, and Low remains gameplay-readable.

```bash
git add src/app src/audio src/world src/vehicle src/dogs assets tests/integration/test_app_flow.gd
git commit -m "feat: add polished presentation menus and settings"
```

### Task 9: Complete Repository Documentation

**Files:**
- Create: `README.md`
- Create: `CONTRIBUTING.md`
- Create: `docs/architecture.md`
- Create: `LICENSE`
- Modify: `docs/superpowers/specs/2026-07-22-catch-dog-design.md`

**Interfaces:**
- Documents every public module, directory, command, extension workflow, and artifact location implemented in Tasks 1–8.

- [ ] **Step 1: Add documentation validation test**

Create a test that asserts the four files exist and that README contains `Controls`, `Setup`, `Testing`, `Exporting`, `Repository structure`, and `Troubleshooting`; CONTRIBUTING contains `GDScript style`, `Comments`, `Adding a dog`, `Adding a pickup`, `Guard behavior`, and `Pull requests`.

- [ ] **Step 2: Run red documentation test**

Run: `CATCH_DOG_TEST_FILTER=documentation scripts/dev/godot.sh --headless --path . --script tests/test_runner.gd`  
Expected: missing documentation files.

- [ ] **Step 3: Write README and contributor guide**

Use exact commands from the repository, real paths from the file map, Arrow/Space controls, Godot 4.6 requirement, platform limitations, artifact instructions, commenting rules, and step-by-step extension recipes. Do not claim signing, distribution, or performance results that have not been verified.

- [ ] **Step 4: Write architecture and license documents**

Document scene ownership, signal signatures, state diagrams, resources, navigation, spawn validation, terminal-state idempotency, settings schema, error strategy, renderer presets, tests, CI, and directory responsibilities. Create `LICENSE` with an all-rights-reserved copyright notice; replace it with an OSI license only after the repository owner explicitly chooses one.

- [ ] **Step 5: Verify links and commit**

Run: `rg -n "TBD|TODO|FIXME|localhost|example\.com" README.md CONTRIBUTING.md docs/architecture.md`  
Expected: no matches.

```bash
git add README.md CONTRIBUTING.md docs/architecture.md LICENSE docs/superpowers/specs
git commit -m "docs: add project contributor and architecture guides"
```

### Task 10: GitHub Pages Landing Page

**Files:**
- Create: `site/index.html`
- Create: `site/styles.css`
- Create: `site/app.js`
- Create: `site/assets/hero.webp`
- Create: `site/assets/gameplay.webp`
- Create: `site/assets/icon.svg`
- Create: `scripts/dev/validate_site.sh`

**Interfaces:**
- Produces a static site with no build-time secret and no runtime API dependency.

- [ ] **Step 1: Add failing site validation**

`validate_site.sh` checks required files, exactly one `h1`, viewport metadata, non-empty alt text, local link targets, absence of mixed content, and a `prefers-reduced-motion` CSS rule.

- [ ] **Step 2: Run validator and confirm failure**

Run: `bash scripts/dev/validate_site.sh`  
Expected: missing `site/index.html`.

- [ ] **Step 3: Build the responsive static page**

Include hero, short pitch, gameplay loop, four dog score tiers, controls, Windows/macOS support, development status, screenshots, repository/docs links, and a release-download link whose disabled state clearly says no public build exists. Use semantic HTML, keyboard-visible focus, responsive CSS, compressed local media, and reduced motion.

- [ ] **Step 4: Validate and commit**

Run: `bash scripts/dev/validate_site.sh`  
Expected: `Site validation passed`.

```bash
git add site scripts/dev/validate_site.sh
git commit -m "feat: add accessible game landing page"
```

### Task 11: Export Presets and GitHub Actions Artifacts

**Files:**
- Create: `export_presets.cfg`
- Create: `scripts/ci/install_godot.sh`
- Create: `scripts/ci/build_exports.sh`
- Create: `scripts/ci/package_checksums.sh`
- Create: `.github/workflows/validate-build.yml`
- Create: `.github/workflows/release.yml`
- Create: `.github/workflows/pages.yml`
- Modify: `.gitignore`

**Interfaces:**
- Produces presets `Windows Desktop` and `macOS`.
- Produces artifacts `catch-dog-windows-x86_64.zip`, `catch-dog-macos-universal.zip`, and `SHA256SUMS.txt`.

- [ ] **Step 1: Add export-config validation**

Extend `validate_project.gd` to require both named presets, Windows `.exe` output, macOS `.zip` output, x86_64 Windows, Universal 2 macOS, and no embedded credentials.

- [ ] **Step 2: Run red validation**

Run: `scripts/dev/godot.sh --headless --path . --script scripts/dev/validate_project.gd`  
Expected: missing export presets.

- [ ] **Step 3: Add presets and deterministic build scripts**

Use Godot 4.6.3 from the official [`godotengine/godot-builds` release](https://github.com/godotengine/godot-builds/releases/tag/4.6.3-stable). `install_godot.sh` downloads each editor/export-template asset together with its official `.sha256` file and runs `sha256sum --check` before extraction. `build_exports.sh` validates/tests first, exports release builds into `builds/windows/` and `builds/macos/`, verifies expected executables, then creates platform zips. `package_checksums.sh` writes sorted SHA-256 lines.

- [ ] **Step 4: Add validation/build workflow**

Trigger on pull requests and pushes to `main`; use Ubuntu, concurrency cancellation, read-only contents permission, dependency cache keyed by Godot version/checksums, test validation, site validation, both exports, checksum verification, and artifact upload with 14-day retention.

- [ ] **Step 5: Add tagged release and Pages workflows**

Release triggers on `v*` tags, repeats validation/build, and attaches zips/checksums with `contents: write`. Pages triggers only for `site/**` and its workflow, uses official `configure-pages`, `upload-pages-artifact`, and `deploy-pages` actions, `pages: write`, `id-token: write`, protected `github-pages` environment, and deployment concurrency.

- [ ] **Step 6: Verify workflows and local export**

Run: `scripts/dev/godot.sh --headless --path . --script scripts/dev/validate_project.gd`  
Expected: `Project validation passed`.

Run: `bash scripts/ci/build_exports.sh`  
Expected: both zip files and `SHA256SUMS.txt`; neither archive contains credentials or `.git` data.

- [ ] **Step 7: Commit**

```bash
git add export_presets.cfg scripts/ci .github/workflows .gitignore scripts/dev/validate_project.gd
git commit -m "ci: build release artifacts and deploy Pages"
```

### Task 12: Performance, Cross-Platform Smoke Test, and Release Gate

**Files:**
- Create: `docs/performance.md`
- Create: `docs/release-checklist.md`
- Create: `scripts/dev/soak_test.gd`
- Modify: performance-critical scenes/scripts identified by profiler evidence.
- Modify: `README.md`

**Interfaces:**
- Produces measured Medium/Low preset results and a repeatable release checklist.

- [ ] **Step 1: Add a failing soak-test gate**

`soak_test.gd` starts and restarts 50 deterministic sessions, cycles 2,000 spawn attempts, fires 500 net events, exhausts/replaces 100 guards, and exits non-zero on orphan-count growth, invalid references, spawn overlap, duplicate capture, or duplicate terminal events.

- [ ] **Step 2: Run soak test before optimization**

Run: `scripts/dev/godot.sh --headless --path . --script scripts/dev/soak_test.gd`  
Expected: a concrete pass/fail report with counts and peak node total.

- [ ] **Step 3: Profile and optimize only measured bottlenecks**

Capture CPU/GPU/frame-time evidence on the target AMD-GPU Mac at 1920×1080 Medium and Low. Apply LOD, visibility range, shadow distance, material batching, navigation update rate, collision simplification, or pooling only when the profiler identifies that cost. Record before/after values and the exact hardware/macOS version in `docs/performance.md`.

- [ ] **Step 4: Smoke-test exported artifacts**

On Windows x86_64 and the target Intel/AMD Mac, verify launch, menu, controls, one victory, each loss reason, settings persistence, replay, and clean quit. Confirm macOS Universal 2 contains both `x86_64` and `arm64` slices with `lipo -info`.

- [ ] **Step 5: Run the complete release gate**

Run tests, project validation, site validation, soak test, both exports, checksum verification, documentation link scan, `git diff --check`, and `git status --short`.  
Expected: every command succeeds; worktree contains only intentional release-document updates.

- [ ] **Step 6: Commit final verified results**

```bash
git add docs/performance.md docs/release-checklist.md scripts/dev/soak_test.gd README.md
git commit -m "chore: document verified release performance"
```

## Execution Checkpoints

- After Task 3: review vehicle feel and fuel curve before adding content.
- After Task 6: review the complete capture/pursuit loop in a minimal arena.
- After Task 7: approve the graybox vertical slice before asset polish.
- After Task 8: approve visual/audio quality before documentation and release automation.
- After Task 11: inspect CI artifacts and GitHub Pages preview.
- After Task 12: accept measured cross-platform release candidate.
