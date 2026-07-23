extends "res://tests/test_case.gd"


const GameplayScenePath := "res://src/session/gameplay.tscn"
const NeighborhoodScenePath := "res://src/world/neighborhood.tscn"
const DogCatalogRule = preload("res://src/dogs/dog_catalog.gd")
const DogAgentRule = preload("res://src/dogs/dog_agent.gd")
const GuardDirectorRule = preload("res://src/guards/guard_director.gd")
const GuardAgentRule = preload("res://src/guards/guard_agent.gd")
const HudRule = preload("res://src/ui/hud.gd")
const LauncherRule = preload("res://src/capture/net_launcher.gd")
const PlayerVehicleRule = preload("res://src/vehicle/player_vehicle.gd")
const SessionResultRule = preload("res://src/session/session_result.gd")
const SpawnDirectorRule = preload("res://src/dogs/spawn_director.gd")


func test_authored_neighborhood_has_complete_stable_gameplay_layout() -> void:
	var packed := load(NeighborhoodScenePath) as PackedScene
	check(packed != null, "The authored neighborhood scene must load")
	if packed == null:
		return
	var neighborhood := packed.instantiate() as Node3D
	add_child(neighborhood)
	await get_tree().process_frame

	check(neighborhood.has_method("layout_summary"), "Neighborhood must expose a typed authored-layout summary")
	if neighborhood.has_method("layout_summary"):
		var summary := neighborhood.call("layout_summary") as Dictionary
		check(int(summary.get("dog_markers", 0)) >= 12, "Neighborhood must author at least 12 dog markers")
		check(int(summary.get("fuel_markers", 0)) == 6, "Neighborhood must author exactly 6 fuel markers")
		check(int(summary.get("guard_zones", 0)) == 3, "Neighborhood must author exactly 3 guard zones")
		check(int(summary.get("recovery_markers", 0)) >= 3, "Neighborhood must author world-space recovery markers")
		check(bool(summary.get("stable_ids_unique", false)), "Every gameplay marker must have a non-empty unique stable id")
	check(neighborhood.get_node_or_null("NavigationRegion3D") is NavigationRegion3D, "Neighborhood must own a real NavigationRegion3D")
	var region := neighborhood.get_node_or_null("NavigationRegion3D") as NavigationRegion3D
	check(region != null and region.navigation_mesh != null and region.navigation_mesh.get_polygon_count() > 0, "Neighborhood navigation must contain authored polygon data")
	check(neighborhood.get_node_or_null("Roads/MainRoadLoop") != null, "Neighborhood must visibly author a looped main road")
	check(neighborhood.get_node_or_null("Roads/AlleyNorth") != null and neighborhood.get_node_or_null("Roads/AlleySouth") != null, "Neighborhood must contain two connected alleys")
	check(neighborhood.get_node_or_null("DeadEnds") != null and neighborhood.get_node("DeadEnds").get_child_count() >= 2, "Neighborhood must make dead ends readable")
	check(neighborhood.get_node_or_null("StaticCollision") != null and neighborhood.get_node("StaticCollision").get_child_count() > 0, "Neighborhood must own static collision")
	neighborhood.free()


func test_authored_navigation_routes_around_buildings_and_rejects_outside_targets() -> void:
	var neighborhood := (load(NeighborhoodScenePath) as PackedScene).instantiate() as Node3D
	add_child(neighborhood)
	var region := neighborhood.get_node("NavigationRegion3D") as NavigationRegion3D
	var navigation_map := region.get_navigation_map()
	check(await _wait_for_navigation_sync(navigation_map, region), "NavigationRegion3D must synchronize through its normal node lifecycle")
	check(NavigationServer3D.map_is_active(navigation_map), "SceneTree world navigation map must be active")
	var start := Vector3(-40.0, 0.1, -25.0)
	var target := Vector3(0.0, 0.1, -13.0)
	var routed_path := _query_navigation_path(navigation_map, start, target)
	var north_west_house := neighborhood.get_node("StaticCollision/HouseNW") as StaticBody3D

	var navigation_debug := "path=%s regions=%d iteration=%d" % [
		routed_path,
		NavigationServer3D.map_get_regions(navigation_map).size(),
		NavigationServer3D.map_get_iteration_id(navigation_map),
	]
	check(NavigationServer3D.map_get_regions(navigation_map).has(region.get_rid()), "Navigation map must contain this neighborhood's region RID")
	check(not routed_path.is_empty() and routed_path[-1].distance_to(target) < 0.6, "A road-to-alley route must reach its accessible target (%s)" % navigation_debug)
	check(_path_length(routed_path) > start.distance_to(target) + 0.05, "The route must detour instead of taking a blocked straight line through a house (%s)" % navigation_debug)
	check(not _path_crosses_box(routed_path, north_west_house), "Authored navigation must never cross the HouseNW collision footprint")
	var loop_path := _query_navigation_path(
		navigation_map,
		Vector3(-40.0, 0.1, -42.0),
		Vector3(40.0, 0.1, 42.0),
	)
	check(not loop_path.is_empty() and loop_path[-1].distance_to(Vector3(40.0, 0.1, 42.0)) < 0.6, "The looped road must remain fully connected (path=%s)" % loop_path)
	var outside_path := _query_navigation_path(navigation_map, start, Vector3(80.0, 0.1, 0.0))
	check(outside_path.is_empty() or outside_path[-1].distance_to(Vector3(80.0, 0.1, 0.0)) > 1.0, "Perimeter collision must not have reachable navigation outside the neighborhood")
	neighborhood.free()


func test_every_production_anchor_projects_to_real_navigation_within_route_tolerance() -> void:
	var neighborhood := (load(NeighborhoodScenePath) as PackedScene).instantiate() as Node3D
	add_child(neighborhood)
	var region := neighborhood.get_node("NavigationRegion3D") as NavigationRegion3D
	var navigation_map := region.get_navigation_map()
	check(await _wait_for_navigation_sync(navigation_map, region), "Anchor projection fixture requires synchronized real navigation")
	var anchors: Array[Node3D] = []
	for container_name in [&"DogMarkers", &"FuelMarkers", &"GuardZones", &"RecoveryMarkers"]:
		for child in neighborhood.get_node(NodePath(container_name)).get_children():
			anchors.append(child as Node3D)
	check(anchors.size() == 27, "Fixture must cover all 14 dog, 6 fuel, 3 guard, and 4 recovery anchors")
	for anchor in anchors:
		var closest := NavigationServer3D.map_get_closest_point(navigation_map, anchor.global_position)
		check(
			closest.distance_to(anchor.global_position) <= 0.5,
			"Production anchor %s must project to navigation within GuardAgent route tolerance (distance %.3f)" % [
				anchor.name,
				closest.distance_to(anchor.global_position),
			],
		)
	var player_spawn := Vector3(0.0, 0.1, 34.0)
	var player_closest := NavigationServer3D.map_get_closest_point(navigation_map, player_spawn)
	check(player_closest.distance_to(player_spawn) <= 0.5, "Player spawn must project to real navigation within route tolerance")
	neighborhood.free()


func test_real_guard_route_accepts_initial_player_spawn() -> void:
	var gameplay := _make_gameplay()
	if gameplay == null:
		return
	var region := gameplay.get_node("Neighborhood/NavigationRegion3D") as NavigationRegion3D
	var navigation_map := region.get_navigation_map()
	check(await _wait_for_navigation_sync(navigation_map, region), "Guard route fixture requires synchronized real navigation")
	var player := gameplay.get_node("Runtime/Player") as PlayerVehicleRule
	var director := gameplay.get_node("Runtime/GuardDirector") as GuardDirectorRule
	var guard := director.get_child(0) as GuardAgentRule
	guard.begin_pursuit(player)
	guard.refresh_navigation_target()

	check(guard.state == GuardAgentRule.State.PURSUING, "Production GuardAgent must accept a real route from its authored zone to initial player spawn")
	var guard_path := _query_navigation_path(navigation_map, guard.global_position, player.global_position)
	check(not guard_path.is_empty() and guard_path[-1].distance_to(player.global_position) <= 0.5, "Real guard path must terminate within production route tolerance")
	gameplay.free()


func test_neighborhood_navigation_uses_node_owned_sync_without_global_rid_flushes() -> void:
	var source := (load("res://src/world/neighborhood.gd") as Script).source_code
	for forbidden in [
		"region_set_map",
		"region_set_navigation_mesh",
		"region_set_transform",
		"map_force_update",
	]:
		check(not source.contains(forbidden), "Production Neighborhood must not bypass NavigationRegion3D ownership with %s" % forbidden)


func test_dead_end_barriers_have_real_static_collision() -> void:
	var neighborhood := (load(NeighborhoodScenePath) as PackedScene).instantiate() as Node3D
	add_child(neighborhood)
	await get_tree().physics_frame
	for barrier_name in [&"NorthBarrier", &"SouthBarrier"]:
		var barrier := neighborhood.get_node("DeadEnds/%s" % barrier_name)
		check(barrier is StaticBody3D, "%s must be a StaticBody3D, not visual-only geometry" % barrier_name)
		if barrier is StaticBody3D:
			var shape := barrier.get_node_or_null("CollisionShape3D") as CollisionShape3D
			check(shape != null and shape.shape != null and not shape.disabled, "%s must own an enabled collision shape" % barrier_name)
	var north_query := PhysicsRayQueryParameters3D.create(
		Vector3(-10.0, 0.8, -30.0),
		Vector3(-10.0, 0.8, -34.0),
	)
	north_query.collision_mask = 1
	var north_hit := neighborhood.get_world_3d().direct_space_state.intersect_ray(north_query)
	check(north_hit.get("collider") == neighborhood.get_node("DeadEnds/NorthBarrier"), "A real physics ray must be blocked by NorthBarrier")
	var south_query := PhysicsRayQueryParameters3D.create(
		Vector3(10.0, 0.8, 31.0),
		Vector3(10.0, 0.8, 35.0),
	)
	south_query.collision_mask = 1
	var south_hit := neighborhood.get_world_3d().direct_space_state.intersect_ray(south_query)
	check(south_hit.get("collider") == neighborhood.get_node("DeadEnds/SouthBarrier"), "A real physics ray must be blocked by SouthBarrier")
	neighborhood.free()


func test_100_points_wins_and_freezes_gameplay_once() -> void:
	var gameplay := _make_gameplay()
	if gameplay == null:
		return

	gameplay.capture_for_test(50)
	gameplay.capture_for_test(50)
	gameplay.capture_for_test(10)

	check(gameplay.session.state == gameplay.session.State.WON, "Captures reaching 100 points must win")
	check(gameplay.session.score == 100, "Winning score must clamp to 100")
	check(gameplay.result_open_count == 1, "Terminal result must open exactly once")
	check(gameplay.gameplay_frozen, "Terminal state must freeze gameplay ownership")
	var payload := gameplay.last_result_payload as Dictionary
	check(payload.get("won") == true and payload.get("reason") == &"score_goal", "Win payload must preserve the terminal reason")
	check(payload.get("score") == 100 and payload.get("captures") == 2, "Win payload must contain score and accepted capture count")
	check(
		ResourceLoader.exists("res://src/session/session_result.gd")
		and gameplay.get("last_result") != null
		and gameplay.get("last_result").get_script() == load("res://src/session/session_result.gd"),
		"Gameplay must own a typed SessionResult instead of a raw Dictionary",
	)
	gameplay.free()


func test_timer_guard_and_empty_fuel_have_distinct_loss_reasons() -> void:
	var gameplay := _make_gameplay()
	if gameplay == null:
		return

	check(gameplay.session.seconds == 180.0, "Playable session duration must start at 180 seconds")
	check(gameplay.simulate_timeout() == &"time_expired", "Timer expiry must report time_expired")
	gameplay.reset_for_test()
	check(gameplay.simulate_guard_contact() == &"caught", "Guard contact must report caught")
	gameplay.reset_for_test()
	check(gameplay.simulate_out_of_fuel() == &"out_of_fuel", "Stopped empty fuel must report out_of_fuel")
	gameplay.free()


func test_production_signals_feed_catalog_points_and_distinct_losses() -> void:
	var gameplay := _make_gameplay()
	if gameplay == null:
		return
	var launcher := gameplay.get_node("Runtime/Player/NetLauncher") as LauncherRule
	var catalog := DogCatalogRule.new()
	launcher.capture_confirmed.emit(catalog.entries[2])
	check(gameplay.session.score == 40 and gameplay.capture_count == 1, "Confirmed capture must award the selected catalog entry's points")
	(gameplay.get_node("Runtime/GuardDirector") as GuardDirectorRule).player_caught.emit()
	check(gameplay.last_result_payload.get("reason") == &"caught", "GuardDirector contact signal must finish with caught")

	gameplay.reset_for_test()
	(gameplay.get_node("Runtime/Player") as PlayerVehicleRule).stopped_without_fuel.emit()
	check(gameplay.last_result_payload.get("reason") == &"out_of_fuel", "Player stopped-without-fuel signal must finish with out_of_fuel")
	gameplay.free()


func test_real_launcher_target_signal_starts_and_stops_spawned_dog_fleeing() -> void:
	var gameplay := _make_gameplay()
	if gameplay == null:
		return
	await get_tree().process_frame
	var director := gameplay.get_node("Runtime/DogSpawnDirector") as SpawnDirectorRule
	var dogs: Array[DogAgentRule] = director.active_dogs()
	check(not dogs.is_empty(), "Production SpawnDirector must provide a dog for the lock integration fixture")
	if dogs.is_empty():
		gameplay.free()
		return
	var player := gameplay.get_node("Runtime/Player") as PlayerVehicleRule
	var launcher := gameplay.get_node("Runtime/Player/NetLauncher") as LauncherRule
	var dog := dogs[0]
	dog.global_position = launcher.global_position - launcher.global_basis.z * 8.0

	launcher.update_target_from_candidates(
		launcher.global_transform,
		_one_dog(dog),
		func(_candidate: DogAgentRule) -> bool: return true,
	)
	check(dog.state == DogAgentRule.State.FLEEING, "A real launcher target_changed signal must start the newly locked dog fleeing")
	check(dog.get_node("NavigationAgent3D").target_position.distance_to(player.global_position) > 1.0, "Flee navigation target must be directed away from the player")
	var no_dogs: Array[DogAgentRule] = []
	launcher.update_target_from_candidates(launcher.global_transform, no_dogs, Callable())
	check(dog.state == DogAgentRule.State.IDLE and dog.velocity == Vector3.ZERO, "Clearing or replacing the lock must stop the prior dog's flee lifecycle")
	gameplay.free()


func test_threat_ring_uses_heading_updates_and_separates_overlapping_directions() -> void:
	var gameplay := _make_gameplay()
	if gameplay == null:
		return
	var hud := gameplay.get_node("HUD") as HudRule
	check(hud.has_method("update_threat_ring") and hud.has_method("threat_indicator_positions"), "HUD must expose typed relative threat-ring update and inspection APIs")
	if not hud.has_method("update_threat_ring") or not hud.has_method("threat_indicator_positions"):
		gameplay.free()
		return
	var identical: Array[Vector3] = [Vector3.RIGHT, Vector3.RIGHT]
	hud.update_threat_ring(identical, Basis.IDENTITY)
	var first_positions: PackedVector2Array = hud.threat_indicator_positions()
	check(first_positions.size() == 2 and first_positions[0].distance_to(first_positions[1]) > 4.0, "Threats with matching bearings must occupy distinct ring positions")
	var right_threat: Array[Vector3] = [Vector3.RIGHT]
	hud.update_threat_ring(right_threat, Basis.IDENTITY)
	var identity_position: Vector2 = hud.threat_indicator_positions()[0]
	hud.update_threat_ring(right_threat, Basis(Vector3.UP, PI * 0.5))
	var turned_position: Vector2 = hud.threat_indicator_positions()[0]
	check(identity_position.distance_to(turned_position) > 20.0, "Threat indicator bearing must transform relative to player/camera heading")

	var player := gameplay.get_node("Runtime/Player") as PlayerVehicleRule
	var director := gameplay.get_node("Runtime/GuardDirector") as GuardDirectorRule
	var guard := director.get_child(0) as GuardAgentRule
	guard.begin_pursuit(player)
	gameplay._physics_process(0.0)
	var moving_start: Vector2 = hud.threat_indicator_positions()[0]
	guard.global_position = player.global_position + Vector3(30.0, 0.0, 0.0)
	gameplay._physics_process(0.0)
	var moving_end: Vector2 = hud.threat_indicator_positions()[0]
	check(moving_start.distance_to(moving_end) > 4.0, "Threat ring must refresh while pursuing actors move, not only on lifecycle signals")
	gameplay.free()


func test_result_payload_is_complete_and_terminal_transition_is_idempotent() -> void:
	var gameplay := _make_gameplay()
	if gameplay == null:
		return
	gameplay.capture_for_test(40)
	gameplay.session.tick(12.5)
	gameplay.simulate_guard_contact()
	gameplay.simulate_guard_contact()
	gameplay.capture_for_test(50)

	var payload := gameplay.last_result_payload as Dictionary
	check(gameplay.result_open_count == 1, "Repeated terminal inputs must not reopen the result")
	check(payload.keys().size() == 5, "Result payload must contain exactly five validated fields")
	check(payload.get("won") == false and payload.get("reason") == &"caught", "Loss payload must keep its first terminal reason")
	check(payload.get("score") == 40 and is_equal_approx(float(payload.get("remaining_time")), 167.5), "Loss payload must snapshot score and remaining time")
	check(payload.get("captures") == 1, "Loss payload must snapshot capture count")
	gameplay.free()


func test_session_result_rejects_invalid_terminal_cross_field_pairs() -> void:
	var under_goal_win := SessionResultRule.new(true, &"score_goal", 90, 12.0, 3)
	var nonzero_timeout := SessionResultRule.new(false, &"time_expired", 40, 0.5, 1)
	var won_loss := SessionResultRule.new(true, &"caught", 100, 12.0, 4)
	var valid_win := SessionResultRule.new(true, &"score_goal", 100, 12.0, 4)
	var valid_timeout := SessionResultRule.new(false, &"time_expired", 40, 0.0, 1)
	var valid_caught := SessionResultRule.new(false, &"caught", 40, 12.0, 1)
	var valid_out_of_fuel := SessionResultRule.new(false, &"out_of_fuel", 40, 12.0, 1)

	check(not under_goal_win.is_valid(), "score_goal win must require the typed score goal")
	check(not nonzero_timeout.is_valid(), "time_expired must require approximately zero remaining time")
	check(not won_loss.is_valid(), "Loss reasons must reject won=true even at the score goal")
	check(valid_win.is_valid(), "A goal-scoring win must remain valid")
	check(valid_timeout.is_valid(), "A zero-time timeout must remain valid")
	check(valid_caught.is_valid() and valid_out_of_fuel.is_valid(), "Caught and out-of-fuel losses with remaining time must remain valid")


func test_immediate_replay_resets_launcher_projectiles_vehicle_and_camera_through_typed_apis() -> void:
	var gameplay := _make_gameplay()
	if gameplay == null:
		return
	await get_tree().process_frame
	var launcher := gameplay.get_node("Runtime/Player/NetLauncher") as LauncherRule
	var director := gameplay.get_node("Runtime/DogSpawnDirector") as SpawnDirectorRule
	var dogs: Array[DogAgentRule] = director.active_dogs()
	check(not dogs.is_empty(), "Replay fixture requires an owned spawned dog")
	if dogs.is_empty():
		gameplay.free()
		return
	var dog := dogs[0]
	dog.global_position = launcher.global_position - launcher.global_basis.z * 8.0
	launcher.update_target_from_candidates(
		launcher.global_transform,
		_one_dog(dog),
		func(_candidate: DogAgentRule) -> bool: return true,
	)
	check(launcher.try_throw(), "Replay fixture must launch a real projectile immediately before reset")
	check(launcher.cooldown_ratio() < 1.0 and gameplay.get_node("Runtime/Projectiles").get_child_count() == 1, "Fixture must begin with cooldown and one live projectile")
	var player := gameplay.get_node("Runtime/Player") as PlayerVehicleRule
	var camera := player.get_node("CameraRig")
	check(player.has_method("reset_runtime_state"), "PlayerVehicle must expose a typed runtime reset API")
	check(launcher.has_method("reset_runtime_state"), "NetLauncher must expose a typed runtime reset API")
	check(camera.has_method("reset_runtime_state") and camera.has_method("follow_anchor_position"), "CameraRig must expose typed reset and inspection APIs")
	if (
		not player.has_method("reset_runtime_state")
		or not launcher.has_method("reset_runtime_state")
		or not camera.has_method("reset_runtime_state")
		or not camera.has_method("follow_anchor_position")
	):
		gameplay.free()
		return

	gameplay.reset_for_test()

	check(is_equal_approx(launcher.cooldown_ratio(), 1.0) and not launcher.has_target(), "Replay must restore launcher readiness and clear its lock")
	check(gameplay.get_node("Runtime/Projectiles").get_child_count() == 0, "Replay must free all live projectiles")
	check(player.global_position.distance_to(Vector3(0.0, 0.1, 34.0)) < 0.01 and player.velocity == Vector3.ZERO, "Replay must restore player pose and motion")
	check(camera.follow_anchor_position().distance_to(player.global_position + Vector3.UP * camera.focus_height) < 0.01, "Replay must snap camera smoothing to the restored player pose")
	var capture_connection_count := launcher.capture_confirmed.get_connections().size()
	var target_connection_count := launcher.target_changed.get_connections().size()
	for cycle in range(3):
		gameplay.capture_for_test(100)
		gameplay.reset_for_test()
	check(launcher.capture_confirmed.get_connections().size() == capture_connection_count, "Repeated replay must not duplicate launcher signal connections")
	check(launcher.target_changed.get_connections().size() == target_connection_count, "Repeated replay must not duplicate target lifecycle connections")
	check(gameplay.get_node("Runtime/Projectiles").get_child_count() == 0, "Repeated replay cycles must not leak projectiles")
	gameplay.free()


func test_replay_restores_owned_runtime_without_duplicates_or_stale_signals() -> void:
	var gameplay := _make_gameplay()
	if gameplay == null:
		return
	var original_session: RefCounted = gameplay.session
	gameplay.capture_for_test(100)
	var runtime_count := gameplay.get_node("Runtime").get_child_count()
	var initial_pickups := gameplay.get_node("Runtime/PickupDirector").get_child_count()
	var initial_guards := gameplay.get_node("Runtime/GuardDirector").get_child_count()

	gameplay.reset_for_test()

	check(gameplay.session != original_session, "Replay must create a fresh GameSession owner")
	check(gameplay.session.score == 0 and is_equal_approx(gameplay.session.seconds, 180.0), "Replay must restore initial score and time")
	check(not gameplay.gameplay_frozen and gameplay.result_open_count == 0, "Replay must unfreeze play and clear result ownership")
	check(gameplay.get_node("Runtime").get_child_count() == runtime_count, "Replay must not leak or duplicate runtime children")
	check(initial_pickups == 6 and gameplay.get_node("Runtime/PickupDirector").get_child_count() == 6, "Replay must restore exactly six owned fuel pickups")
	check(initial_guards == 3 and gameplay.get_node("Runtime/GuardDirector").get_child_count() == 3, "Replay must restore exactly three owned guards")
	original_session.session_finished.emit(false, &"caught")
	check(gameplay.result_open_count == 0, "Signals from a retired session must be disconnected")
	gameplay.free()


func test_hud_presents_all_required_session_and_threat_feedback() -> void:
	var gameplay := _make_gameplay()
	if gameplay == null:
		return
	var hud := gameplay.get_node_or_null("HUD")
	check(hud != null, "Gameplay must own its HUD")
	if hud == null:
		gameplay.free()
		return
	check(hud.has_method("update_score") and hud.has_method("update_time") and hud.has_method("update_fuel"), "HUD must expose typed score, time, and fuel updates")
	hud.update_score(40, 100)
	hud.update_time(65.0)
	hud.update_fuel(0.35)
	hud.update_target_state(true, 0.4)
	var threats: Array[Vector3] = [Vector3.RIGHT, Vector3.BACK]
	hud.update_chase(true, threats)
	check((hud.get_node("SafeArea/TopBar/Score") as Label).text == "40 / 100", "HUD must clearly render score over goal")
	check((hud.get_node("SafeArea/TopBar/Time") as Label).text == "01:05", "HUD must format time as mm:ss")
	check(is_equal_approx((hud.get_node("SafeArea/FuelPanel/Fuel") as ProgressBar).value, 35.0), "HUD must render fuel percentage")
	check((hud.get_node("SafeArea/TargetPanel/Status") as Label).text.contains("LOCK"), "HUD must show target lock state")
	check((hud.get_node("SafeArea/ChaseWarning") as Label).visible, "HUD must show a chase warning")
	check((hud.get_node("SafeArea/ThreatIndicators") as Control).get_child_count() == 2, "HUD must render one directional threat indicator per pursuing guard")
	gameplay.free()


func _make_gameplay() -> Node:
	var packed := load(GameplayScenePath) as PackedScene
	check(packed != null, "Playable gameplay scene must load")
	if packed == null:
		return null
	var gameplay := packed.instantiate()
	add_child(gameplay)
	return gameplay


func _query_navigation_path(navigation_map: RID, start: Vector3, target: Vector3) -> PackedVector3Array:
	var parameters := NavigationPathQueryParameters3D.new()
	parameters.map = navigation_map
	parameters.start_position = start
	parameters.target_position = target
	parameters.navigation_layers = 1
	var result := NavigationPathQueryResult3D.new()
	NavigationServer3D.query_path(parameters, result)
	return result.path


func _wait_for_navigation_sync(navigation_map: RID, region: NavigationRegion3D) -> bool:
	for frame in range(12):
		if (
			NavigationServer3D.map_get_iteration_id(navigation_map) > 0
			and NavigationServer3D.region_get_iteration_id(region.get_rid()) > 0
			and NavigationServer3D.map_get_regions(navigation_map).has(region.get_rid())
			and not _query_navigation_path(
				navigation_map,
				Vector3(-50.0, 0.1, -50.0),
				Vector3(50.0, 0.1, -50.0),
			).is_empty()
		):
			return true
		await get_tree().physics_frame
	return false


func _path_length(path: PackedVector3Array) -> float:
	var length := 0.0
	for index in range(1, path.size()):
		length += path[index - 1].distance_to(path[index])
	return length


func _path_crosses_box(path: PackedVector3Array, body: StaticBody3D) -> bool:
	var shape_node: CollisionShape3D
	for child in body.get_children():
		var candidate := child as CollisionShape3D
		if candidate != null:
			shape_node = candidate
			break
	if shape_node == null:
		return true
	var box := shape_node.shape as BoxShape3D
	var half_size := box.size * 0.5
	for index in range(1, path.size()):
		var from := path[index - 1]
		var to := path[index]
		var steps := maxi(ceili(from.distance_to(to) / 0.25), 1)
		for step in range(steps + 1):
			var point := from.lerp(to, float(step) / float(steps))
			var local := body.to_local(point)
			if absf(local.x) < half_size.x and absf(local.z) < half_size.z:
				return true
	return false


func _one_dog(dog: DogAgentRule) -> Array[DogAgentRule]:
	return [dog]
