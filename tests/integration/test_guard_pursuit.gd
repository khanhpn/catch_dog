extends "res://tests/test_case.gd"


const GuardAgentRule = preload("res://src/guards/guard_agent.gd")
const GuardAgentScene = preload("res://src/guards/guard_agent.tscn")
const GuardDirectorRule = preload("res://src/guards/guard_director.gd")
const GuardDirectorScene = preload("res://src/guards/guard_director.tscn")
const GuardStatsRule = preload("res://src/guards/guard_stats.gd")
const DogAgentRule = preload("res://src/dogs/dog_agent.gd")
const DogScene = preload("res://src/dogs/dog_agent.tscn")
const NetLauncherRule = preload("res://src/capture/net_launcher.gd")
const NetProjectileRule = preload("res://src/capture/net_projectile.gd")
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


func test_real_launcher_hit_and_miss_emit_the_same_hard_45m_detection() -> void:
	for resolves_as_hit in [true, false]:
		var launcher := NetLauncherRule.new()
		var director := GuardDirectorRule.new()
		var player := _make_player(Vector3.ZERO)
		var dog: DogAgentRule = DogScene.instantiate() as DogAgentRule
		var boundary := _make_guard(Vector3(45.0, 0.0, 0.0))
		var outside := _make_guard(Vector3(45.001, 0.0, 0.0))
		dog.position = Vector3(0.0, 0.0, -8.0)
		dog.capture_effect_duration = 10.0
		add_child(launcher)
		add_child(director)
		add_child(dog)
		director.player = player
		director.set_test_guards(_guard_array([boundary, outside]))
		director.bind_launcher(launcher)
		var projectiles: Array[NetProjectileRule] = []
		var emitted_radii: Array[float] = []
		launcher.set_projectile_factory_for_test(func() -> NetProjectileRule:
			var projectile := NetProjectileRule.new()
			projectiles.append(projectile)
			return projectile
		)
		launcher.net_thrown.connect(func(_origin: Vector3, radius: float) -> void: emitted_radii.append(radius))
		launcher.update_target_from_candidates(
			launcher.global_transform,
			_one_dog(dog),
			func(_candidate: DogAgentRule) -> bool: return true,
		)

		var accepted: bool = launcher.try_throw()
		if not projectiles.is_empty():
			if resolves_as_hit:
				projectiles[0].simulate_hit(dog)
			else:
				projectiles[0].simulate_miss()

		check(accepted, "The production launcher must accept the locked throw")
		check(emitted_radii == [45.0], "Every production throw must emit exactly the hard 45m guard radius")
		check(boundary.state == GuardAgentRule.State.PURSUING, "A real throw must alert a guard at exactly 45m before hit or miss resolution")
		check(outside.state == GuardAgentRule.State.IDLE, "A real throw must not alert a guard beyond 45m")
		launcher.free()
		director.free()
		boundary.free()
		outside.free()
		if is_instance_valid(dog):
			dog.free()
		player.free()
	var property_names := PackedStringArray()
	var launcher := NetLauncherRule.new()
	for property in launcher.get_property_list():
		property_names.append(String(property.name))
	check(not property_names.has("detection_radius"), "The 45m production detection contract must not be export-configurable")
	launcher.free()


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
	var player := _make_player(Vector3(0.0, 0.0, -0.8))
	var caught := [0]
	guard.player_caught.connect(func() -> void: caught[0] += 1)
	guard.begin_pursuit(player)
	var capture_area := guard.get_node("CaptureArea") as Area3D

	await get_tree().physics_frame
	await get_tree().physics_frame

	check(player.collision_layer == 1 and capture_area.collision_mask == 1, "Player and capture area must use explicit compatible physics layers")
	check(capture_area.monitoring, "Pursuit must keep the real capture area monitoring")
	check(not (capture_area.get_node("CollisionShape3D") as CollisionShape3D).disabled, "Pursuit must enable the real capture shape")
	check(capture_area.get_overlapping_bodies().has(player), "The real capture area must observe the overlapping PlayerVehicle body")
	check(caught[0] == 1, "A real CaptureArea body overlap must emit player_caught once")
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


func test_normal_pursuit_update_recovers_or_abandons_when_target_route_fails() -> void:
	var recovery_guard := _make_guard(Vector3.ZERO)
	var recovery_player := _make_player(Vector3(20.0, 0.0, 0.0))
	var recovery_point := Marker3D.new()
	recovery_point.position = Vector3(4.0, 0.0, 0.0)
	add_child(recovery_point)
	recovery_guard.recovery_points = [recovery_point]
	var recovery_targets: Array[Vector3] = []
	recovery_guard.set_test_navigation_target_sink(func(target_position: Vector3) -> void: recovery_targets.append(target_position))
	recovery_guard.set_test_recovery_reachability(func(target_position: Vector3) -> bool:
		return target_position.is_equal_approx(recovery_point.global_position)
	)
	recovery_guard.begin_pursuit(recovery_player)
	recovery_targets.clear()
	var recovery_start := recovery_guard.global_position

	recovery_guard.simulate_pursuit(0.25)

	check(recovery_guard.state == GuardAgentRule.State.PURSUING, "An unreachable player route must retain pursuit when a recovery route exists")
	check(recovery_targets == [recovery_point.global_position], "Normal pursuit update must switch an unreachable target to the nearest reachable recovery")
	check(recovery_guard.global_position == recovery_start, "Normal navigation failure handling must not teleport to recovery")
	var abandon_guard := _make_guard(Vector3.ZERO)
	var abandon_player := _make_player(Vector3(20.0, 0.0, 0.0))
	abandon_guard.set_test_recovery_reachability(func(_target_position: Vector3) -> bool: return false)
	abandon_guard.begin_pursuit(abandon_player)
	var abandon_start := abandon_guard.global_position

	abandon_guard.simulate_pursuit(0.25)

	check(abandon_guard.state == GuardAgentRule.State.IDLE and abandon_guard.target == null, "An unreachable player route with no recovery route must abandon pursuit")
	check(abandon_guard.global_position == abandon_start, "Abandoning an unreachable route must never teleport")
	recovery_guard.free()
	recovery_player.free()
	recovery_point.free()
	abandon_guard.free()
	abandon_player.free()


func test_real_navigation_map_recovers_across_disconnected_regions_and_accepts_arrival() -> void:
	var region := _make_disconnected_navigation_region()
	var guard := _make_guard(Vector3.ZERO)
	var player := _make_player(Vector3(50.0, 0.0, 0.0))
	var recovery := Marker3D.new()
	recovery.position = Vector3(5.0, 0.0, 0.0)
	add_child(recovery)
	guard.recovery_points = [recovery]
	await get_tree().physics_frame
	await get_tree().physics_frame
	var navigation := guard.get_node("NavigationAgent3D") as NavigationAgent3D
	var navigation_map := navigation.get_navigation_map()
	NavigationServer3D.map_force_update(navigation_map)
	await get_tree().physics_frame
	var recovery_path := _query_navigation_path(navigation_map, guard.global_position, recovery.global_position)
	var player_path := _query_navigation_path(navigation_map, guard.global_position, player.global_position)
	check(not recovery_path.is_empty(), "The real fixture must provide a same-island recovery path")
	check(not player_path.is_empty() and player_path[-1].distance_to(player.global_position) > 0.5, "The disconnected player query may return a partial path but must not reach the other island")
	guard.begin_pursuit(player)
	var before := guard.global_position

	guard.simulate_pursuit(0.25)

	check(guard.state == GuardAgentRule.State.PURSUING, "A disconnected player island must recover through a reachable same-island point")
	check(navigation.target_position.is_equal_approx(recovery.global_position), "Production query_path reachability must reject a partial target route and select connected recovery")
	check(guard.global_position == before, "Real navigation failure recovery must not teleport")
	var arrived_guard := _make_guard(Vector3(-3.0, 0.0, 0.0))
	var arrived_player := _make_player(Vector3(-3.0, 0.0, 0.0))
	await get_tree().physics_frame
	arrived_guard.begin_pursuit(arrived_player)
	arrived_guard.simulate_pursuit(0.25)
	check(arrived_guard.state == GuardAgentRule.State.PURSUING, "A valid route that has already arrived must not be classified as navigation failure")
	guard.free()
	player.free()
	recovery.free()
	arrived_guard.free()
	arrived_player.free()
	for region_rid: RID in region.get_meta("region_rids") as Array[RID]:
		NavigationServer3D.free_rid(region_rid)
	region.free()


func test_director_scene_assigns_stable_world_recovery_points() -> void:
	var director: GuardDirectorRule = GuardDirectorScene.instantiate() as GuardDirectorRule
	var guard: GuardAgentRule = GuardAgentScene.instantiate() as GuardAgentRule
	add_child(director)
	add_child(guard)
	director.register_guard(guard)
	var original_positions: Array[Vector3] = []
	for point in guard.recovery_points:
		original_positions.append(point.global_position)

	guard.global_position += Vector3(20.0, 0.0, 20.0)

	check(guard.recovery_points.size() >= 2, "The production director scene must assign typed navigation recovery points")
	for index in range(guard.recovery_points.size()):
		check(guard.recovery_points[index].get_parent() != guard, "Recovery points must be world-authored rather than moving with the pursuing guard")
		check(guard.recovery_points[index].global_position == original_positions[index], "Guard movement must not move an authored recovery point")
	director.free()
	guard.free()


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
	var third := _make_guard(Vector3(100.0, 0.0, 100.0))
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
	var in_view := {exhausted_guard.get_instance_id(): true, zones[1].get_instance_id(): false, zones[2].get_instance_id(): false}
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
	check(exhausted_guard.is_queued_for_deletion(), "Replacement handoff must queue the retired guard for cleanup")
	check(exhausted_guard.collision_layer == 0 and exhausted_guard.collision_mask == 0, "Retirement must immediately disable guard body collision")
	check(not (exhausted_guard.get_node("Visual") as MeshInstance3D).visible, "Retirement must immediately hide the retired guard mesh")
	check(not (director.get("_guards") as Array).has(exhausted_guard), "Replacement must remove the retired guard from director bookkeeping")
	check(not (director.get("_guard_zones") as Dictionary).has(exhausted_guard.get_instance_id()), "Replacement must clear the retired guard-to-zone mapping")
	check(director.non_retired_guard_count() == 3, "Replacement must preserve the three-guard cap")
	if not replacements.is_empty():
		check(replacements[0].global_position == zones[2].global_position, "Replacement must skip the occupied zone and use another off-camera authored zone")
	director.free()
	exhausted_guard.free()
	second.free()
	third.free()
	player.free()
	for replacement in replacements:
		if is_instance_valid(replacement):
			replacement.free()


func test_staggered_exhaustions_keep_independent_twenty_second_deadlines() -> void:
	var director: GuardDirectorRule = GuardDirectorScene.instantiate() as GuardDirectorRule
	var player := _make_player(Vector3.ZERO)
	add_child(director)
	director.player = player
	var first := _make_guard(Vector3(10.0, 0.0, 0.0))
	var second := _make_guard(Vector3(-10.0, 0.0, 0.0))
	director.set_test_guards(_guard_array([first, second]))
	var delays: Array[float] = []
	var callbacks: Array[Callable] = []
	director.set_test_replacement_scheduler(func(delay: float, callback: Callable) -> void:
		delays.append(delay)
		callbacks.append(callback)
	)
	director.set_test_visibility_check(func(_node: Node3D) -> bool: return true)
	first.begin_pursuit(player)
	first.exhaust()
	# The second event occurs conceptually at +15s; its scheduler must still receive a full 20s delay.
	second.begin_pursuit(player)
	second.exhaust()

	check(delays == [20.0, 20.0] and callbacks.size() == 2, "Each distinct exhausted guard must own an independent 20-second deadline")
	if not callbacks.is_empty():
		callbacks[0].call()
	var eligible := director.get("_replacement_eligible") as Array
	check(eligible.has(first), "The first guard must become eligible at its own deadline")
	check(not eligible.has(second), "A guard exhausted 15 seconds later must remain ineligible until its own deadline")
	check(delays.size() == 2, "Waiting in view after eligibility must not shorten or stack replacement timers")
	if callbacks.size() > 1:
		callbacks[1].call()
	check((director.get("_replacement_eligible") as Array).has(second), "The second guard must become eligible only at its own deadline")
	director.free()
	first.free()
	second.free()
	player.free()


func test_repeated_replacement_cycles_keep_nodes_and_bookkeeping_bounded() -> void:
	var director: GuardDirectorRule = GuardDirectorScene.instantiate() as GuardDirectorRule
	var player := _make_player(Vector3.ZERO)
	add_child(director)
	director.player = player
	var zones := director.zone_markers()
	var current := _make_guard(zones[0].global_position)
	var second := _make_guard(Vector3(100.0, 0.0, 100.0))
	var third := _make_guard(Vector3(-100.0, 0.0, 100.0))
	director.set_test_guards(_guard_array([current, second, third]))
	director.assign_guard_zone(current, zones[0])
	director.assign_guard_zone(second, zones[1])
	director.assign_guard_zone(third, zones[2])
	director.set_test_visibility_check(func(_node: Node3D) -> bool: return false)
	var callbacks: Array[Callable] = []
	director.set_test_replacement_scheduler(func(_delay: float, callback: Callable) -> void: callbacks.append(callback))
	var created: Array[GuardAgentRule] = []
	director.set_test_guard_factory(func() -> GuardAgentRule:
		var replacement := GuardAgentScene.instantiate() as GuardAgentRule
		add_child(replacement)
		created.append(replacement)
		return replacement
	)

	for cycle in range(4):
		current.begin_pursuit(player)
		current.exhaust()
		check(callbacks.size() == cycle + 1, "Every cycle must schedule exactly one deadline for its exhausted guard")
		if callbacks.size() > cycle:
			callbacks[cycle].call()
		await get_tree().process_frame
		check(director.non_retired_guard_count() == 3, "Every replacement cycle must preserve three non-retired guards")
		check((director.get("_guards") as Array).size() == 3, "Retired guards must not accumulate in director guard bookkeeping")
		check((director.get("_guard_zones") as Dictionary).size() == 3, "Retired guard-to-zone mappings must not accumulate")
		var retired_nodes := 0
		for child in get_children():
			var guard_child := child as GuardAgentRule
			if guard_child != null and guard_child.state == GuardAgentRule.State.RETIRED:
				retired_nodes += 1
		check(retired_nodes == 0, "Queued retired guard nodes must be freed after replacement handoff")
		if created.size() > cycle:
			current = created[cycle]
	director.free()
	second.free()
	third.free()
	player.free()
	for replacement in created:
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


func _one_dog(dog: DogAgentRule) -> Array[DogAgentRule]:
	return [dog]


func _make_disconnected_navigation_region() -> Node3D:
	var fixture := Node3D.new()
	add_child(fixture)
	var region_rids: Array[RID] = []
	var navigation_map := fixture.get_world_3d().get_navigation_map()
	NavigationServer3D.map_set_active(navigation_map, true)
	for offset_x in [0.0, 50.0]:
		var navigation_mesh := NavigationMesh.new()
		navigation_mesh.vertices = PackedVector3Array([
			Vector3(-10.0, 0.0, 10.0),
			Vector3(10.0, 0.0, 10.0),
			Vector3(10.0, 0.0, -10.0),
			Vector3(-10.0, 0.0, -10.0),
		])
		navigation_mesh.add_polygon(PackedInt32Array([0, 1, 2]))
		navigation_mesh.add_polygon(PackedInt32Array([0, 2, 3]))
		var region_rid := NavigationServer3D.region_create()
		region_rids.append(region_rid)
		NavigationServer3D.region_set_use_async_iterations(region_rid, false)
		NavigationServer3D.region_set_enabled(region_rid, true)
		NavigationServer3D.region_set_map(region_rid, navigation_map)
		NavigationServer3D.region_set_transform(
			region_rid,
			Transform3D(Basis.IDENTITY, Vector3(offset_x, 0.0, 0.0)),
		)
		NavigationServer3D.region_set_navigation_mesh(region_rid, navigation_mesh)
	fixture.set_meta("region_rids", region_rids)
	return fixture


func _query_navigation_path(navigation_map: RID, start: Vector3, target: Vector3) -> PackedVector3Array:
	var parameters := NavigationPathQueryParameters3D.new()
	parameters.map = navigation_map
	parameters.start_position = start
	parameters.target_position = target
	parameters.navigation_layers = 1
	var result := NavigationPathQueryResult3D.new()
	NavigationServer3D.query_path(parameters, result)
	return result.path
