extends "res://tests/test_case.gd"


const DOG_SCENE_PATH := "res://src/dogs/dog_agent.tscn"
const SPAWN_DIRECTOR_PATH := "res://src/dogs/spawn_director.gd"
const SPAWN_POINT_PATH := "res://src/dogs/spawn_point.gd"


func test_capture_is_idempotent_and_emits_once() -> void:
	var dog: Variant = _make_dog()
	if dog == null:
		return
	add_child(dog)
	var captured_count := [0]
	var captured_stats := [null]
	dog.captured.connect(func(stats: Resource) -> void:
		captured_count[0] += 1
		captured_stats[0] = stats
	)

	check(dog.capture(), "The first capture must transition the dog")
	check(not dog.capture(), "A captured dog must reject repeated capture attempts")
	check(captured_count[0] == 1, "Capture must emit exactly one signal")
	check(captured_stats[0] == dog.stats, "Capture must emit the dog's typed stats")
	dog.free()


func test_capture_disables_state_collision_and_navigation() -> void:
	var dog: Variant = _make_dog()
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


func test_begin_flee_targets_away_with_bounded_lateral_variation() -> void:
	var dog: Variant = _make_dog()
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
	var director: Variant = _make_director()
	if director == null:
		return
	var roll_count := [0]
	director.set_test_roll_source(func() -> float:
		roll_count[0] += 1
		return 0.80
	)

	var stats: Resource = director.pick_dog_stats()

	check(roll_count[0] == 1, "Weighted dog selection must consume exactly one RNG roll")
	check(stats != null and stats.get("id") == &"golden_retriever", "The roll must use catalog weights and boundary rules")
	director.free()


func test_director_rejects_visible_near_blocked_or_out_of_bounds_markers() -> void:
	var director: Variant = _make_director()
	if director == null:
		return
	add_child(director)
	var player := Node3D.new()
	add_child(player)
	player.position = Vector3.ZERO
	director.player = player
	var visible_marker: Variant = _make_marker(Vector3(30.0, 0.0, 0.0))
	var near_marker: Variant = _make_marker(Vector3(10.0, 0.0, 0.0))
	var blocked_marker: Variant = _make_marker(Vector3(40.0, 0.0, 0.0))
	var outside_marker: Variant = _make_marker(Vector3(120.0, 0.0, 0.0))
	var valid_marker: Variant = _make_marker(Vector3(50.0, 0.0, 0.0))
	for marker: Variant in [visible_marker, near_marker, blocked_marker, outside_marker, valid_marker]:
		add_child(marker)
	director.set_test_markers([visible_marker, near_marker, blocked_marker, outside_marker, valid_marker])
	director.set_test_marker_validation(visible_marker, true, false, true)
	director.set_test_marker_validation(near_marker, false, false, true)
	director.set_test_marker_validation(blocked_marker, false, true, true)
	director.set_test_marker_validation(outside_marker, false, false, false)
	director.set_test_marker_validation(valid_marker, false, false, true)

	check(director.choose_spawn_marker() == valid_marker, "Only hidden, distant, clear, in-bounds markers may spawn dogs")

	for marker: Variant in [visible_marker, near_marker, blocked_marker, outside_marker, valid_marker]:
		marker.free()
	player.free()
	director.free()


func test_marker_validation_fails_closed_without_production_dependencies() -> void:
	var director: Variant = _make_director()
	if director == null:
		return
	var marker: Variant = _make_marker(Vector3(30.0, 0.0, 0.0))
	director.set_test_markers([marker])

	check(
		director.choose_spawn_marker() == null,
		"Marker validation must fail closed without player, camera, and physics-world adapters",
	)

	marker.free()
	director.free()


func test_director_caps_active_dogs_at_six() -> void:
	var director: Variant = _make_director()
	if director == null:
		return
	add_child(director)
	var player := Node3D.new()
	add_child(player)
	director.player = player
	var marker: Variant = _make_marker(Vector3(30.0, 0.0, 0.0))
	add_child(marker)
	director.set_test_markers([marker])
	director.set_test_marker_validation(marker, false, false, true)

	var spawned: Array = []
	for index in range(6):
		spawned.append(director.request_dog_spawn())
	var capped_attempt: Variant = director.request_dog_spawn()

	check(spawned.all(func(dog: Variant) -> bool: return dog != null), "The director must fill all six active dog slots")
	check(capped_attempt == null, "A seventh active dog must be rejected")
	check(director.active_dog_count() == 6, "The active dog population must never exceed six")
	for dog: Variant in spawned:
		if is_instance_valid(dog):
			dog.free()
	marker.free()
	player.free()
	director.free()


func test_director_initially_fills_six_dog_population() -> void:
	var setup := _make_spawnable_director()
	if setup.is_empty():
		return
	var director: Variant = setup.director
	if not director.has_method("_ready"):
		check(false, "The director must maintain its initial dog population when ready")
		_free_spawnable_director(setup)
		return

	director._ready()

	check(director.active_dog_count() == 6, "A ready director must initially fill six active dog slots")
	_free_spawnable_director(setup)


func test_director_replenishes_after_capture_or_tree_exit() -> void:
	var setup := _make_spawnable_director()
	if setup.is_empty():
		return
	var director: Variant = setup.director
	if not director.has_method("_ready"):
		check(false, "The director must expose ready-time population maintenance")
		_free_spawnable_director(setup)
		return
	director._ready()
	var active_dogs: Array[Node] = director.get_children().filter(
		func(child: Node) -> bool: return child.has_method("capture")
	)
	var captured_dog: Variant = active_dogs[0]

	captured_dog.capture()

	check(director.active_dog_count() == 6, "Capturing a dog must replenish the active population to six")
	active_dogs = director.get_children().filter(
		func(child: Node) -> bool: return child.has_method("capture") and child != captured_dog
	)
	var exiting_dog: Node = active_dogs[0]
	exiting_dog.tree_exiting.emit()

	check(director.active_dog_count() == 6, "A dog leaving the tree must replenish the active population to six")
	_free_spawnable_director(setup)


func test_failed_spawn_schedules_one_non_recursive_two_second_retry() -> void:
	var director: Variant = _make_director()
	if director == null:
		return
	add_child(director)
	director.set_test_markers([])

	var result: Variant = director.request_dog_spawn()
	var retry_timer := director.get_retry_timer() as Timer

	check(result == null, "A request without a valid marker must fail cleanly")
	check(director.spawn_attempt_count == 1, "A failed request must not recurse synchronously")
	check(retry_timer != null, "A failed request must schedule a retry timer")
	if retry_timer != null:
		check(retry_timer.one_shot, "The retry timer must be one-shot")
		check(is_equal_approx(retry_timer.wait_time, 2.0), "The retry delay must be exactly two seconds")
		director.request_dog_spawn()
		check(director.get_retry_timer() == retry_timer, "Repeated failures must not stack retry timers")
	director.free()


func _make_dog() -> Variant:
	if not ResourceLoader.exists(DOG_SCENE_PATH):
		check(false, "DogAgent scene must exist and be loadable")
		return null
	var scene := load(DOG_SCENE_PATH) as PackedScene
	check(scene != null, "DogAgent scene must parse as a PackedScene")
	return scene.instantiate() if scene != null else null


func _make_director() -> Variant:
	if not ResourceLoader.exists(SPAWN_DIRECTOR_PATH):
		check(false, "SpawnDirector script must exist and be loadable")
		return null
	var script := load(SPAWN_DIRECTOR_PATH) as Script
	check(script != null, "SpawnDirector script must parse")
	return script.new() if script != null else null


func _make_marker(position: Vector3) -> Variant:
	if not ResourceLoader.exists(SPAWN_POINT_PATH):
		check(false, "SpawnPoint script must exist and be loadable")
		return null
	var script := load(SPAWN_POINT_PATH) as Script
	var marker: Variant = script.new()
	marker.position = position
	return marker


func _make_spawnable_director() -> Dictionary:
	var director: Variant = _make_director()
	if director == null:
		return {}
	add_child(director)
	var player := Node3D.new()
	add_child(player)
	director.player = player
	var marker: Variant = _make_marker(Vector3(30.0, 0.0, 0.0))
	add_child(marker)
	director.set_test_markers([marker])
	director.set_test_marker_validation(marker, false, false, true)
	return {"director": director, "player": player, "marker": marker}


func _free_spawnable_director(setup: Dictionary) -> void:
	var director: Node = setup.director
	var marker: Node = setup.marker
	var player: Node = setup.player
	director.free()
	marker.free()
	player.free()
