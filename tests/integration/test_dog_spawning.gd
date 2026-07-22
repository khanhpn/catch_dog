extends "res://tests/test_case.gd"


const DOG_SCENE_PATH := "res://src/dogs/dog_agent.tscn"
const SPAWN_DIRECTOR_PATH := "res://src/dogs/spawn_director.gd"
const SPAWN_POINT_PATH := "res://src/dogs/spawn_point.gd"
const DogAgentRule = preload("res://src/dogs/dog_agent.gd")
const DogStatsRule = preload("res://src/dogs/dog_stats.gd")
const SpawnDirectorRule = preload("res://src/dogs/spawn_director.gd")
const SpawnPointRule = preload("res://src/dogs/spawn_point.gd")


func test_capture_is_idempotent_and_emits_once() -> void:
	var dog: DogAgentRule = _make_dog()
	if dog == null:
		return
	add_child(dog)
	var captured_count := [0]
	var captured_stats: Array[DogStatsRule] = []
	dog.captured.connect(func(stats: DogStatsRule) -> void:
		captured_count[0] += 1
		captured_stats.append(stats)
	)

	check(dog.capture(), "The first capture must transition the dog")
	check(not dog.capture(), "A captured dog must reject repeated capture attempts")
	check(captured_count[0] == 1, "Capture must emit exactly one signal")
	check(captured_stats[0] == dog.stats, "Capture must emit the dog's typed stats")
	dog.free()


func test_capture_disables_state_collision_and_navigation() -> void:
	var dog: DogAgentRule = _make_dog()
	if dog == null:
		return
	add_child(dog)
	var navigation_agent := dog.get_node_or_null("NavigationAgent3D") as NavigationAgent3D

	dog.capture()

	check(dog.state == dog.State.CAPTURED, "Capture must enter the named CAPTURED state")
	check(dog.collision_layer == 0 and dog.collision_mask == 0, "Capture must disable dog collision")
	check(navigation_agent != null, "The dog scene must provide a NavigationAgent3D")
	if navigation_agent != null:
		check(not navigation_agent.avoidance_enabled, "Capture must disable navigation avoidance")
		check(navigation_agent.process_mode == Node.PROCESS_MODE_DISABLED, "Capture must disable navigation processing")
	dog.free()


func test_capture_outside_tree_defers_cleanup() -> void:
	var dog: DogAgentRule = _make_dog()
	if dog == null:
		return
	check(not dog.is_inside_tree(), "Test setup requires an off-tree dog")

	var transitioned: bool = dog.capture()
	await get_tree().process_frame

	check(transitioned, "An off-tree dog must still accept its first capture")
	check(not is_instance_valid(dog), "An off-tree captured dog must be cleaned up on the next frame")
	if is_instance_valid(dog):
		dog.free()


func test_begin_flee_targets_away_with_bounded_lateral_variation() -> void:
	var dog: DogAgentRule = _make_dog()
	if dog == null:
		return
	add_child(dog)
	dog.position = Vector3(10.0, 0.0, 0.0)
	var threat := Vector3.ZERO

	dog.begin_flee(threat)

	var target: Vector3 = dog.get_node("NavigationAgent3D").target_position
	var away := Vector3(1.0, 0.0, 0.0)
	var displacement: Vector3 = target - dog.position
	var forward_distance: float = displacement.dot(away)
	var lateral: Vector3 = displacement - away * forward_distance
	check(dog.state == dog.State.FLEEING, "Fleeing must enter the named FLEEING state")
	check(forward_distance > 0.0, "The flee target must be away from the threat")
	check(lateral.length() <= dog.lateral_variation + 0.001, "Flee target lateral variation must stay bounded")
	dog.free()


func test_weighted_selection_uses_exactly_one_rng_roll() -> void:
	var director: SpawnDirectorRule = _make_director()
	if director == null:
		return
	var roll_count := [0]
	director.set_test_roll_source(func() -> float:
		roll_count[0] += 1
		return 0.80
	)

	var stats: DogStatsRule = director.pick_dog_stats()

	check(roll_count[0] == 1, "Weighted dog selection must consume exactly one RNG roll")
	check(stats != null and stats.get("id") == &"golden_retriever", "The roll must use catalog weights and boundary rules")
	director.free()


func test_director_rejects_visible_near_blocked_or_out_of_bounds_markers() -> void:
	var director: SpawnDirectorRule = _make_director()
	if director == null:
		return
	add_child(director)
	var player := Node3D.new()
	add_child(player)
	player.position = Vector3.ZERO
	director.player = player
	var visible_marker: SpawnPointRule = _make_marker(Vector3(30.0, 0.0, 0.0))
	var near_marker: SpawnPointRule = _make_marker(Vector3(10.0, 0.0, 0.0))
	var blocked_marker: SpawnPointRule = _make_marker(Vector3(40.0, 0.0, 0.0))
	var outside_marker: SpawnPointRule = _make_marker(Vector3(120.0, 0.0, 0.0))
	var valid_marker: SpawnPointRule = _make_marker(Vector3(50.0, 0.0, 0.0))
	var markers := _markers(visible_marker, near_marker, blocked_marker, outside_marker, valid_marker)
	for marker: SpawnPointRule in markers:
		add_child(marker)
	director.set_test_markers(markers)
	director.set_test_marker_validation(visible_marker, true, false, true)
	director.set_test_marker_validation(near_marker, false, false, true)
	director.set_test_marker_validation(blocked_marker, false, true, true)
	director.set_test_marker_validation(outside_marker, false, false, false)
	director.set_test_marker_validation(valid_marker, false, false, true)

	check(director.choose_spawn_marker() == valid_marker, "Only hidden, distant, clear, in-bounds markers may spawn dogs")

	for marker: SpawnPointRule in markers:
		marker.free()
	player.free()
	director.free()


func test_marker_validation_fails_closed_without_production_dependencies() -> void:
	var director: SpawnDirectorRule = _make_director()
	if director == null:
		return
	var marker: SpawnPointRule = _make_marker(Vector3(30.0, 0.0, 0.0))
	director.set_test_markers(_markers(marker))

	check(
		director.choose_spawn_marker() == null,
		"Marker validation must fail closed without player, camera, and physics-world adapters",
	)

	marker.free()
	director.free()


func test_marker_validation_fails_closed_without_player() -> void:
	var director: SpawnDirectorRule = _make_director()
	if director == null:
		return
	var marker: SpawnPointRule = _make_marker(Vector3(30.0, 0.0, 0.0))
	director.set_test_markers(_markers(marker))
	director.set_test_marker_validation(marker, false, false, true)

	check(director.choose_spawn_marker() == null, "A missing player adapter must reject every marker")

	marker.free()
	director.free()


func test_marker_validation_fails_closed_without_camera() -> void:
	var director: SpawnDirectorRule = _make_director()
	if director == null:
		return
	var player := Node3D.new()
	var marker: SpawnPointRule = _make_marker(Vector3(30.0, 0.0, 0.0))
	add_child(player)
	add_child(marker)
	director.player = player
	add_child(director)
	director.set_test_markers(_markers(marker))
	await get_tree().physics_frame

	check(director.choose_spawn_marker() == null, "A missing camera adapter must reject every marker")

	director.queue_free()
	marker.queue_free()
	player.queue_free()
	await get_tree().process_frame


func test_marker_validation_fails_closed_without_physics_tree() -> void:
	var director: SpawnDirectorRule = _make_director()
	if director == null:
		return
	var player := Node3D.new()
	var camera := Camera3D.new()
	var marker: SpawnPointRule = _make_marker(Vector3(0.0, 0.0, 30.0))
	add_child(player)
	add_child(camera)
	add_child(marker)
	director.player = player
	director.camera = camera
	director.set_test_markers(_markers(marker))
	await get_tree().process_frame

	check(director.choose_spawn_marker() == null, "An off-tree director without a physics world must reject every marker")

	director.free()
	marker.queue_free()
	camera.queue_free()
	player.queue_free()
	await get_tree().process_frame


func test_real_camera_frustum_rejects_visible_marker_and_permits_behind_candidate() -> void:
	var director: SpawnDirectorRule = _make_director()
	if director == null:
		return
	var player := Node3D.new()
	var camera := Camera3D.new()
	var visible_marker: SpawnPointRule = _make_marker(Vector3(0.0, 0.0, -30.0))
	var behind_marker: SpawnPointRule = _make_marker(Vector3(0.0, 0.0, 30.0))
	add_child(player)
	add_child(camera)
	add_child(visible_marker)
	add_child(behind_marker)
	director.player = player
	director.camera = camera
	add_child(director)
	director.set_test_markers(_markers(visible_marker, behind_marker))
	await get_tree().physics_frame

	check(
		director.choose_spawn_marker() == behind_marker,
		"The real camera adapter must reject an in-view marker and permit a behind-camera candidate",
	)

	director.queue_free()
	behind_marker.queue_free()
	visible_marker.queue_free()
	camera.queue_free()
	player.queue_free()
	await get_tree().process_frame


func test_real_shape_query_rejects_occupied_marker_and_accepts_clear_marker() -> void:
	var director: SpawnDirectorRule = _make_director()
	if director == null:
		return
	var player := Node3D.new()
	var camera := Camera3D.new()
	var blocked_marker: SpawnPointRule = _make_marker(Vector3(0.0, 0.0, 30.0))
	var clear_marker: SpawnPointRule = _make_marker(Vector3(0.0, 0.0, 50.0))
	var obstacle := StaticBody3D.new()
	var collision_shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.5
	collision_shape.shape = sphere
	obstacle.add_child(collision_shape)
	obstacle.position = blocked_marker.position
	add_child(player)
	add_child(camera)
	add_child(blocked_marker)
	add_child(clear_marker)
	add_child(obstacle)
	director.player = player
	director.camera = camera
	add_child(director)
	director.set_test_markers(_markers(blocked_marker, clear_marker))
	await get_tree().physics_frame

	check(
		director.choose_spawn_marker() == clear_marker,
		"The real shape query must reject an occupied marker and accept a clear candidate",
	)

	director.queue_free()
	obstacle.queue_free()
	clear_marker.queue_free()
	blocked_marker.queue_free()
	camera.queue_free()
	player.queue_free()
	await get_tree().process_frame


func test_director_caps_active_dogs_at_six() -> void:
	var director: SpawnDirectorRule = _make_director()
	if director == null:
		return
	add_child(director)
	var player := Node3D.new()
	add_child(player)
	director.player = player
	var marker: SpawnPointRule = _make_marker(Vector3(30.0, 0.0, 0.0))
	add_child(marker)
	director.set_test_markers(_markers(marker))
	director.set_test_marker_validation(marker, false, false, true)

	var spawned: Array[DogAgentRule] = []
	for index in range(6):
		spawned.append(director.request_dog_spawn())
	var capped_attempt: DogAgentRule = director.request_dog_spawn()

	check(spawned.all(func(dog: DogAgentRule) -> bool: return dog != null), "The director must fill all six active dog slots")
	check(capped_attempt == null, "A seventh active dog must be rejected")
	check(director.active_dog_count() == 6, "The active dog population must never exceed six")
	for dog: DogAgentRule in spawned:
		if is_instance_valid(dog):
			dog.free()
	marker.free()
	player.free()
	director.free()


func test_required_spawn_configuration_cannot_be_weakened() -> void:
	var director: SpawnDirectorRule = _make_director()
	if director == null:
		return

	director.max_active_dogs = 99
	director.retry_delay = 0.01
	director.minimum_player_distance = 5.0

	check(director.max_active_dogs == 6, "The active dog population must remain exactly six")
	check(is_equal_approx(director.retry_delay, 2.0), "The retry delay must remain exactly two seconds")
	check(
		is_equal_approx(director.minimum_player_distance, 20.0),
		"Configured player distance must clamp to at least 20 meters",
	)
	director.minimum_player_distance = 25.0
	check(
		is_equal_approx(director.minimum_player_distance, 25.0),
		"A safer player distance above 20 meters must remain configurable",
	)
	director.free()


func test_director_initially_fills_six_dog_population() -> void:
	var setup := _make_spawnable_director()
	if setup.is_empty():
		return
	var director := setup.director as SpawnDirectorRule

	add_child(director)

	check(director.active_dog_count() == 6, "Tree entry must trigger ready-time fill of six active dogs")
	check(director.spawn_attempt_count == 6, "Initial fill must create exactly six dogs without an extra request")
	_free_spawnable_director(setup)


func test_director_replenishes_after_capture_or_tree_exit() -> void:
	var setup := _make_spawnable_director()
	if setup.is_empty():
		return
	var director := setup.director as SpawnDirectorRule
	add_child(director)
	var active_dogs: Array[Node] = director.get_children().filter(
		func(child: Node) -> bool: return child.has_method("capture")
	)
	var captured_dog := active_dogs[0] as DogAgentRule
	var attempts_before_capture: int = director.spawn_attempt_count

	captured_dog.capture()
	captured_dog.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	check(
		director.active_dog_count() == 6,
		"Capture followed by tree exit must replenish the active population to six",
	)
	check(
		director.spawn_attempt_count == attempts_before_capture + 1,
		"Captured and tree-exiting notifications must coalesce into one replacement spawn",
	)
	_free_spawnable_director(setup)


func test_off_tree_failure_starts_one_deterministic_retry_after_tree_entry() -> void:
	var director: SpawnDirectorRule = _make_director()
	if director == null:
		return
	if not director.has_method("set_test_retry_scheduler"):
		check(false, "SpawnDirector must expose a deterministic retry scheduler seam")
		director.free()
		return
	director.set_test_markers(_markers())
	var scheduled_delays: Array[float] = []
	var scheduled_callbacks: Array[Callable] = []
	director.set_test_retry_scheduler(func(delay: float, callback: Callable) -> void:
		scheduled_delays.append(delay)
		scheduled_callbacks.append(callback)
	)

	var result: DogAgentRule = director.request_dog_spawn()

	check(result == null, "A request without a valid marker must fail cleanly")
	check(scheduled_callbacks.is_empty(), "An off-tree retry must remain pending until tree entry")
	add_child(director)
	await get_tree().process_frame
	check(scheduled_callbacks.size() == 1, "Tree entry must start exactly one pending retry")
	check(
		scheduled_delays.size() == 1 and is_equal_approx(scheduled_delays[0], 2.0),
		"The deterministic retry scheduler must receive exactly two seconds",
	)
	director.request_dog_spawn()
	director.request_dog_spawn()
	check(scheduled_callbacks.size() == 1, "Repeated failures must not stack retry schedules")

	var player := Node3D.new()
	var marker: SpawnPointRule = _make_marker(Vector3(30.0, 0.0, 0.0))
	add_child(player)
	add_child(marker)
	director.player = player
	director.set_test_markers(_markers(marker))
	director.set_test_marker_validation(marker, false, false, true)
	var attempts_before_retry: int = director.spawn_attempt_count
	scheduled_callbacks[0].call()
	await get_tree().process_frame

	check(director.active_dog_count() == 6, "The fired retry must refill the six-dog population")
	check(
		director.spawn_attempt_count == attempts_before_retry + 6,
		"One fired retry must perform one successful population fill",
	)
	check(scheduled_callbacks.size() == 1, "A successful retry must not schedule another timer")
	director.free()
	marker.free()
	player.free()


func test_production_retry_uses_exact_two_second_scene_tree_timer() -> void:
	var director: SpawnDirectorRule = _make_director()
	if director == null:
		return
	director.set_test_markers(_markers())
	add_child(director)
	var retry_timer: SceneTreeTimer = director.get_retry_timer()

	check(retry_timer is SceneTreeTimer, "Production retries must use a one-shot SceneTreeTimer")
	if retry_timer is SceneTreeTimer:
		check(
			retry_timer.time_left > 1.9 and retry_timer.time_left <= 2.0,
			"The production SceneTreeTimer must start with exactly two seconds",
		)
	director.free()


func _make_dog() -> DogAgentRule:
	if not ResourceLoader.exists(DOG_SCENE_PATH):
		check(false, "DogAgent scene must exist and be loadable")
		return null
	var scene := load(DOG_SCENE_PATH) as PackedScene
	check(scene != null, "DogAgent scene must parse as a PackedScene")
	return scene.instantiate() as DogAgentRule if scene != null else null


func _make_director() -> SpawnDirectorRule:
	if not ResourceLoader.exists(SPAWN_DIRECTOR_PATH):
		check(false, "SpawnDirector script must exist and be loadable")
		return null
	var script := load(SPAWN_DIRECTOR_PATH) as Script
	check(script != null, "SpawnDirector script must parse")
	return script.new() as SpawnDirectorRule if script != null else null


func _make_marker(position: Vector3) -> SpawnPointRule:
	if not ResourceLoader.exists(SPAWN_POINT_PATH):
		check(false, "SpawnPoint script must exist and be loadable")
		return null
	var script := load(SPAWN_POINT_PATH) as Script
	var marker := script.new() as SpawnPointRule
	marker.position = position
	return marker


func _markers(
	first: SpawnPointRule = null,
	second: SpawnPointRule = null,
	third: SpawnPointRule = null,
	fourth: SpawnPointRule = null,
	fifth: SpawnPointRule = null,
) -> Array[SpawnPointRule]:
	var markers: Array[SpawnPointRule] = []
	var candidates: Array[SpawnPointRule] = [first, second, third, fourth, fifth]
	for marker: SpawnPointRule in candidates:
		if marker != null:
			markers.append(marker)
	return markers


func _make_spawnable_director() -> Dictionary:
	var director: SpawnDirectorRule = _make_director()
	if director == null:
		return {}
	var player := Node3D.new()
	add_child(player)
	director.player = player
	var marker: SpawnPointRule = _make_marker(Vector3(30.0, 0.0, 0.0))
	add_child(marker)
	director.set_test_markers(_markers(marker))
	director.set_test_marker_validation(marker, false, false, true)
	return {"director": director, "player": player, "marker": marker}


func _free_spawnable_director(setup: Dictionary) -> void:
	var director: Node = setup.director
	var marker: Node = setup.marker
	var player: Node = setup.player
	director.free()
	marker.free()
	player.free()
