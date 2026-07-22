extends "res://tests/test_case.gd"


const GuardAgentRule = preload("res://src/guards/guard_agent.gd")
const GuardAgentScene = preload("res://src/guards/guard_agent.tscn")
const GuardDirectorRule = preload("res://src/guards/guard_director.gd")
const GuardDirectorScene = preload("res://src/guards/guard_director.tscn")
const GuardStatsRule = preload("res://src/guards/guard_stats.gd")
const NetLauncherRule = preload("res://src/capture/net_launcher.gd")
const PlayerVehicleRule = preload("res://src/vehicle/player_vehicle.gd")
const PlayerVehicleScene = preload("res://src/vehicle/player_vehicle.tscn")


func test_net_throw_detects_guards_at_or_inside_exact_event_radius() -> void:
	var launcher := NetLauncherRule.new()
	var director := GuardDirectorRule.new()
	var player := _make_player(Vector3.ZERO)
	var inside := _make_guard(Vector3(44.999, 0.0, 0.0))
	var boundary := _make_guard(Vector3(45.0, 0.0, 0.0))
	var outside := _make_guard(Vector3(45.001, 0.0, 0.0))
	add_child(launcher)
	add_child(director)
	director.player = player
	director.set_test_guards(_guard_array([inside, boundary, outside]))
	director.bind_launcher(launcher)

	launcher.net_thrown.emit(Vector3.ZERO, 45.0)

	check(inside.state == GuardAgentRule.State.PURSUING, "A guard inside the 45m throw event must detect it")
	check(boundary.state == GuardAgentRule.State.PURSUING, "The 45m event boundary must be inclusive")
	check(outside.state == GuardAgentRule.State.IDLE, "A guard beyond the event radius must remain idle")
	launcher.free()
	director.free()
	inside.free()
	boundary.free()
	outside.free()
	player.free()


func test_hit_and_miss_share_the_same_throw_detection_event() -> void:
	var launcher := NetLauncherRule.new()
	var director := GuardDirectorRule.new()
	var player := _make_player(Vector3.ZERO)
	var first_guard := _make_guard(Vector3(10.0, 0.0, 0.0))
	var second_guard := _make_guard(Vector3(-10.0, 0.0, 0.0))
	add_child(launcher)
	add_child(director)
	director.player = player
	director.set_test_guards(_guard_array([first_guard, second_guard]))
	director.bind_launcher(launcher)

	# Resolution is deliberately absent: guards consume the launch event before a later hit or miss.
	launcher.net_thrown.emit(Vector3.ZERO, 45.0)

	check(first_guard.state == GuardAgentRule.State.PURSUING, "A throw that later hits must already have alerted guards")
	check(second_guard.state == GuardAgentRule.State.PURSUING, "A throw that later misses must produce the identical alert")
	launcher.free()
	director.free()
	first_guard.free()
	second_guard.free()
	player.free()


func test_guard_exposes_named_guarded_states_and_typed_target_lifecycle() -> void:
	var guard := _make_guard(Vector3.ZERO)
	var player := _make_player(Vector3(8.0, 0.0, 0.0))
	var started := [0]
	var ended := [0]
	guard.pursuit_started.connect(func(_guard: GuardAgentRule) -> void: started[0] += 1)
	guard.pursuit_ended.connect(func(_guard: GuardAgentRule) -> void: ended[0] += 1)

	guard.begin_pursuit(player)
	guard.begin_pursuit(player)
	var target_while_active: PlayerVehicleRule = guard.target
	player.queue_free()
	guard.simulate_pursuit(0.1)

	check(GuardAgentRule.State.has("IDLE"), "Guard states must name IDLE")
	check(GuardAgentRule.State.has("PURSUING"), "Guard states must name PURSUING")
	check(GuardAgentRule.State.has("EXHAUSTED"), "Guard states must name EXHAUSTED")
	check(GuardAgentRule.State.has("RETIRED"), "Guard states must name RETIRED")
	check(target_while_active == player, "Pursuit must retain the typed PlayerVehicle target")
	check(guard.target == null and guard.state == GuardAgentRule.State.IDLE, "An invalid target must be released and pursuit abandoned")
	check(started[0] == 1 and ended[0] == 1, "Guarded transitions must emit start and end once")
	guard.free()
	await get_tree().process_frame


func test_navigation_target_refreshes_at_four_hertz() -> void:
	var guard := _make_guard(Vector3.ZERO)
	var player := _make_player(Vector3(20.0, 0.0, 0.0))
	var targets: Array[Vector3] = []
	guard.set_test_navigation_target_sink(func(target_position: Vector3) -> void: targets.append(target_position))
	guard.begin_pursuit(player)
	targets.clear()

	guard.simulate_pursuit(0.249)
	guard.simulate_pursuit(0.001)
	guard.simulate_pursuit(0.50)

	check(targets.size() == 3, "Pursuit navigation must refresh once per 0.25 seconds, including accumulated steps")
	guard.free()
	player.free()


func test_predicted_intercept_is_bounded_from_the_player_position() -> void:
	var guard := _make_guard(Vector3.ZERO)
	var player := _make_player(Vector3(10.0, 0.0, 0.0))
	player.velocity = Vector3(100.0, 0.0, 0.0)
	guard.stats = guard.stats.duplicate() as GuardStatsRule
	guard.stats.max_prediction_seconds = 2.0
	guard.stats.max_prediction_distance = 8.0
	guard.begin_pursuit(player)

	var intercept: Vector3 = guard.predicted_intercept_position()

	check(intercept.distance_to(player.global_position) <= 8.001, "Predicted lead must remain within its configured distance bound")
	check(intercept.x > player.global_position.x, "Predicted intercept must lead a moving player")
	guard.free()
	player.free()


func test_guard_has_smaller_finite_tank_and_higher_acceleration_drain_than_player() -> void:
	var guard := _make_guard(Vector3.ZERO)
	var player := _make_player(Vector3.ZERO)

	check(guard.fuel != null, "Guard scene initialization must create its FuelModel")
	if guard.fuel == null:
		guard.free()
		player.free()
		return
	check(guard.fuel.capacity > 0.0, "Guard fuel capacity must be finite and positive")
	check(guard.fuel.capacity < player.fuel.capacity, "The guard tank must be smaller than the player's")
	check(guard.stats.throttle_fuel_rate > player.stats.throttle_fuel_rate, "Strong guard acceleration must drain faster than player acceleration")
	guard.free()
	player.free()


func test_zero_fuel_disables_propulsion_and_capture_then_ends_once() -> void:
	var guard := _make_guard(Vector3.ZERO)
	var player := _make_player(Vector3(8.0, 0.0, 0.0))
	var ended := [0]
	guard.pursuit_ended.connect(func(_guard: GuardAgentRule) -> void: ended[0] += 1)
	guard.begin_pursuit(player)

	check(guard.fuel != null, "Guard pursuit must initialize its FuelModel")
	if guard.fuel == null:
		guard.free()
		player.free()
		return
	guard.simulate_pursuit(guard.fuel.capacity / guard.stats.throttle_fuel_rate)
	guard.simulate_pursuit(1.0)
	var capture_area := guard.get_node("CaptureArea") as Area3D

	check(guard.state == GuardAgentRule.State.EXHAUSTED, "Empty fuel must transition pursuit to EXHAUSTED")
	check(guard.velocity == Vector3.ZERO, "An exhausted guard must have no propulsion")
	check(not capture_area.monitoring and capture_area.collision_layer == 0 and capture_area.collision_mask == 0, "Exhaustion must disable capture collision")
	check(ended[0] == 1, "Exhaustion must emit pursuit_ended exactly once")
	guard.free()
	player.free()


func test_player_contact_emits_once_only_for_the_valid_active_target() -> void:
	var guard := _make_guard(Vector3.ZERO)
	var player := _make_player(Vector3.ZERO)
	var stranger := CharacterBody3D.new()
	add_child(stranger)
	var caught := [0]
	guard.player_caught.connect(func() -> void: caught[0] += 1)
	guard.begin_pursuit(player)

	guard.simulate_player_contact(stranger)
	guard.simulate_player_contact(player)
	guard.simulate_player_contact(player)
	guard.exhaust()
	guard.simulate_player_contact(player)

	check(caught[0] == 1, "Only one contact with the valid target during PURSUING may emit player_caught")
	guard.free()
	player.free()
	stranger.free()


func test_capture_area_body_entered_uses_the_real_contact_adapter() -> void:
	var guard := _make_guard(Vector3.ZERO)
	var player := _make_player(Vector3.ZERO)
	var caught := [0]
	guard.player_caught.connect(func() -> void: caught[0] += 1)
	guard.begin_pursuit(player)
	var capture_area := guard.get_node("CaptureArea") as Area3D

	capture_area.body_entered.emit(player)
	capture_area.body_entered.emit(player)

	check(caught[0] == 1, "The scene CaptureArea body_entered adapter must preserve one-shot contact semantics")
	guard.free()
	player.free()


func test_navigation_failure_recovers_or_abandons_without_teleporting() -> void:
	var guard := _make_guard(Vector3(3.0, 0.0, 4.0))
	var player := _make_player(Vector3(20.0, 0.0, 0.0))
	var targets: Array[Vector3] = []
	guard.set_test_navigation_target_sink(func(target_position: Vector3) -> void: targets.append(target_position))
	guard.begin_pursuit(player)
	var before := guard.global_position

	guard.handle_navigation_failure(Vector3(6.0, 0.0, 7.0))
	var after_recovery := guard.global_position
	guard.handle_navigation_failure()

	check(after_recovery == before and guard.global_position == before, "Recovery and abandonment must never teleport the guard")
	check(targets.has(Vector3(6.0, 0.0, 7.0)), "A reachable recovery point must become a navigation target")
	check(guard.state == GuardAgentRule.State.IDLE and guard.target == null, "No recovery point must abandon pursuit cleanly")
	guard.free()
	player.free()


func test_navigation_failure_adapter_selects_nearest_reachable_authored_point() -> void:
	var guard := _make_guard(Vector3.ZERO)
	var player := _make_player(Vector3(20.0, 0.0, 0.0))
	var near_point := Marker3D.new()
	var far_point := Marker3D.new()
	near_point.position = Vector3(4.0, 0.0, 0.0)
	far_point.position = Vector3(12.0, 0.0, 0.0)
	add_child(near_point)
	add_child(far_point)
	guard.recovery_points = [far_point, near_point]
	var targets: Array[Vector3] = []
	guard.set_test_navigation_target_sink(func(target_position: Vector3) -> void: targets.append(target_position))
	guard.set_test_recovery_reachability(func(_target_position: Vector3) -> bool: return true)
	guard.begin_pursuit(player)
	targets.clear()
	var before := guard.global_position

	guard.recover_or_abandon_navigation()

	check(targets == [near_point.global_position], "Navigation failure must request the nearest reachable authored recovery point")
	check(guard.global_position == before and guard.state == GuardAgentRule.State.PURSUING, "Recovery must steer normally without teleporting or ending pursuit")
	guard.free()
	player.free()
	near_point.free()
	far_point.free()


func test_real_navigation_agent_receives_bounded_intercept_target() -> void:
	var guard := _make_guard(Vector3.ZERO)
	var player := _make_player(Vector3(10.0, 0.0, 0.0))
	player.velocity = Vector3(2.0, 0.0, 0.0)
	guard.begin_pursuit(player)

	guard.refresh_navigation_target()
	var navigation := guard.get_node("NavigationAgent3D") as NavigationAgent3D

	check(navigation.target_position == guard.predicted_intercept_position(), "The scene NavigationAgent3D adapter must receive the computed intercept")
	guard.free()
	player.free()


func test_director_aggregates_only_active_typed_threat_directions() -> void:
	var director := GuardDirectorRule.new()
	var player := _make_player(Vector3.ZERO)
	var east := _make_guard(Vector3(10.0, 0.0, 0.0))
	var north := _make_guard(Vector3(0.0, 0.0, -10.0))
	var idle := _make_guard(Vector3(-10.0, 0.0, 0.0))
	add_child(director)
	director.player = player
	director.set_test_guards(_guard_array([east, north, idle]))
	east.begin_pursuit(player)
	north.begin_pursuit(player)

	var directions: Array[Vector3] = director.threat_directions()

	check(directions.size() == 2, "Threat aggregation must exclude guards that have not detected the player")
	check(directions.has(Vector3.RIGHT) and directions.has(Vector3.FORWARD), "Threat directions must point from player to each pursuer")
	director.free()
	east.free()
	north.free()
	idle.free()
	player.free()


func test_director_scene_authors_exactly_three_guard_zones() -> void:
	var director: GuardDirectorRule = GuardDirectorScene.instantiate() as GuardDirectorRule
	add_child(director)

	var zones: Array[Marker3D] = director.zone_markers()

	check(zones.size() == 3, "The guard director scene must author exactly three guard-zone markers")
	var ids := {}
	for zone in zones:
		ids[zone.name] = true
	check(ids.size() == 3, "Each authored guard zone must have a stable distinct name")
	director.free()


func test_director_caps_non_retired_guards_at_three() -> void:
	var director := GuardDirectorRule.new()
	add_child(director)
	var guards: Array[GuardAgentRule] = []
	for index in range(4):
		guards.append(_make_guard(Vector3(index * 3.0, 0.0, 0.0)))

	var registrations := PackedByteArray()
	for guard in guards:
		registrations.append(1 if director.register_guard(guard) else 0)

	check(registrations == PackedByteArray([1, 1, 1, 0]), "The director must reject a fourth non-retired guard")
	check(director.non_retired_guard_count() == 3, "The non-retired population must never exceed three")
	director.free()
	for guard in guards:
		guard.free()


func test_exhaustion_schedules_one_delayed_off_camera_replacement_without_refill() -> void:
	var director: GuardDirectorRule = GuardDirectorScene.instantiate() as GuardDirectorRule
	var player := _make_player(Vector3.ZERO)
	add_child(director)
	director.player = player
	var zones := director.zone_markers()
	check(zones.size() == 3, "Replacement policy requires the three authored guard zones")
	if zones.size() != 3:
		director.free()
		player.free()
		return
	var exhausted_guard := _make_guard(zones[0].global_position)
	var second := _make_guard(zones[1].global_position)
	var third := _make_guard(zones[2].global_position)
	director.set_test_guards(_guard_array([exhausted_guard, second, third]))
	director.assign_guard_zone(exhausted_guard, zones[0])
	director.assign_guard_zone(second, zones[1])
	director.assign_guard_zone(third, zones[2])
	var scheduled_delays: Array[float] = []
	var timeout_callbacks: Array[Callable] = []
	director.set_test_replacement_scheduler(func(delay: float, callback: Callable) -> void:
		scheduled_delays.append(delay)
		timeout_callbacks.append(callback)
	)
	var in_view := {exhausted_guard.get_instance_id(): true, zones[1].get_instance_id(): true, zones[2].get_instance_id(): false}
	director.set_test_visibility_check(func(node: Node3D) -> bool: return bool(in_view.get(node.get_instance_id(), false)))
	var replacements: Array[GuardAgentRule] = []
	director.set_test_guard_factory(func() -> GuardAgentRule:
		var replacement := GuardAgentScene.instantiate() as GuardAgentRule
		add_child(replacement)
		replacements.append(replacement)
		return replacement
	)
	exhausted_guard.begin_pursuit(player)

	exhausted_guard.exhaust()
	exhausted_guard.exhaust()

	check(scheduled_delays == [20.0], "Repeated exhaustion notification must own only one 20-second timer")
	if not timeout_callbacks.is_empty():
		timeout_callbacks[0].call()
	check(replacements.is_empty(), "An exhausted guard still in view must not be replaced")
	check(is_equal_approx(exhausted_guard.fuel.amount, 0.0), "An exhausted guard must never refill in view")
	in_view[exhausted_guard.get_instance_id()] = false
	director.process_replacements()

	check(replacements.size() == 1, "An eligible exhausted guard must receive one off-camera replacement")
	check(exhausted_guard.state == GuardAgentRule.State.RETIRED, "Replacement must retire the exhausted guard")
	check(director.non_retired_guard_count() == 3, "Replacement must preserve the three-guard cap")
	if not replacements.is_empty():
		check(replacements[0].global_position == zones[2].global_position, "Replacement must use another off-camera authored zone")
	director.free()
	exhausted_guard.free()
	second.free()
	third.free()
	player.free()
	for replacement in replacements:
		if is_instance_valid(replacement):
			replacement.free()


func _make_player(at: Vector3) -> PlayerVehicleRule:
	var player: PlayerVehicleRule = PlayerVehicleScene.instantiate() as PlayerVehicleRule
	add_child(player)
	player.global_position = at
	player.fuel_percent()
	return player


func _make_guard(at: Vector3) -> GuardAgentRule:
	var guard: GuardAgentRule = GuardAgentScene.instantiate() as GuardAgentRule
	add_child(guard)
	guard.global_position = at
	guard.ensure_initialized()
	return guard


func _guard_array(values: Array) -> Array[GuardAgentRule]:
	var guards: Array[GuardAgentRule] = []
	for value in values:
		guards.append(value as GuardAgentRule)
	return guards
