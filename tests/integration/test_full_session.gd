extends "res://tests/test_case.gd"


const GameplayScenePath := "res://src/session/gameplay.tscn"
const NeighborhoodScenePath := "res://src/world/neighborhood.tscn"
const DogCatalogRule = preload("res://src/dogs/dog_catalog.gd")
const GuardDirectorRule = preload("res://src/guards/guard_director.gd")
const LauncherRule = preload("res://src/capture/net_launcher.gd")
const PlayerVehicleRule = preload("res://src/vehicle/player_vehicle.gd")


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
