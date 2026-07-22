extends "res://tests/test_case.gd"


const DogAgentRule = preload("res://src/dogs/dog_agent.gd")
const DogScene = preload("res://src/dogs/dog_agent.tscn")
const NetLauncherRule = preload("res://src/capture/net_launcher.gd")
const NetProjectileRule = preload("res://src/capture/net_projectile.gd")
const NetProjectileScene = preload("res://src/capture/net_projectile.tscn")
const TargetSelectorRule = preload("res://src/capture/target_selector.gd")


func test_invalid_throw_creates_no_projectile_or_detection_event() -> void:
	var launcher := NetLauncherRule.new()
	add_child(launcher)
	var projectile_count := [0]
	var throw_count := [0]
	launcher.set_projectile_factory_for_test(func() -> NetProjectileRule:
		projectile_count[0] += 1
		return NetProjectileRule.new()
	)
	launcher.net_thrown.connect(func(_origin: Vector3, _radius: float) -> void: throw_count[0] += 1)

	var accepted: bool = launcher.try_throw()

	check(not accepted, "A throw without a valid target must be ignored")
	check(projectile_count[0] == 0, "An invalid throw must not create a projectile")
	check(throw_count[0] == 0, "An invalid throw must not emit a detection event")
	launcher.free()


func test_valid_throw_emits_before_hit_and_confirms_capture_once() -> void:
	var launcher := NetLauncherRule.new()
	var dog: DogAgentRule = DogScene.instantiate() as DogAgentRule
	add_child(launcher)
	add_child(dog)
	dog.position = Vector3.FORWARD * 8.0
	dog.capture_effect_duration = 10.0
	var projectile_box: Array[NetProjectileRule] = []
	var events: PackedStringArray = []
	var dog_capture_count := [0]
	launcher.set_projectile_factory_for_test(func() -> NetProjectileRule:
		var projectile := NetProjectileRule.new()
		projectile_box.append(projectile)
		return projectile
	)
	launcher.net_thrown.connect(func(_origin: Vector3, _radius: float) -> void: events.append("thrown"))
	launcher.capture_confirmed.connect(func(_stats) -> void: events.append("captured"))
	dog.captured.connect(func(_stats) -> void: dog_capture_count[0] += 1)
	launcher.update_target_from_candidates(launcher.global_transform, _one_dog(dog), func(_dog: DogAgentRule) -> bool: return true)

	var accepted: bool = launcher.try_throw()
	if not projectile_box.is_empty():
		projectile_box[0].simulate_hit(dog)
		projectile_box[0].simulate_hit(dog)

	check(accepted, "A valid locked target must permit a throw")
	check(events == PackedStringArray(["thrown", "captured"]), "Detection must emit before the eventual capture and capture must emit once")
	check(dog_capture_count[0] == 1, "One projectile must invoke DogAgent capture successfully exactly once")
	dog.free()
	launcher.free()


func test_valid_throw_emits_before_eventual_miss() -> void:
	var launcher := NetLauncherRule.new()
	var dog := _make_dog(Vector3.FORWARD * 8.0)
	add_child(launcher)
	var projectile_box: Array[NetProjectileRule] = []
	var throw_count := [0]
	var capture_count := [0]
	launcher.set_projectile_factory_for_test(func() -> NetProjectileRule:
		var projectile := NetProjectileRule.new()
		projectile_box.append(projectile)
		return projectile
	)
	launcher.net_thrown.connect(func(_origin: Vector3, _radius: float) -> void: throw_count[0] += 1)
	launcher.capture_confirmed.connect(func(_stats) -> void: capture_count[0] += 1)
	launcher.update_target_from_candidates(launcher.global_transform, _one_dog(dog), func(_candidate: DogAgentRule) -> bool: return true)

	var accepted: bool = launcher.try_throw()
	if not projectile_box.is_empty():
		projectile_box[0].simulate_miss()

	check(accepted and throw_count[0] == 1, "A valid throw must emit detection even when the projectile later misses")
	check(capture_count[0] == 0, "A missed projectile must not confirm a capture")
	dog.free()
	launcher.free()


func test_cooldown_reopens_at_exactly_eight_tenths_of_a_second() -> void:
	var launcher := NetLauncherRule.new()
	var dog := _make_dog(Vector3.FORWARD * 8.0)
	add_child(launcher)
	launcher.set_projectile_factory_for_test(func() -> NetProjectileRule: return NetProjectileRule.new())
	launcher.update_target_from_candidates(launcher.global_transform, _one_dog(dog), func(_candidate: DogAgentRule) -> bool: return true)

	var first: bool = launcher.try_throw()
	launcher.advance_cooldown(0.799)
	var early: bool = launcher.try_throw()
	launcher.advance_cooldown(0.001)
	var exact: bool = launcher.try_throw()

	check(first, "The initial valid throw must be ready")
	check(not early, "The launcher must remain cooling down before 0.8 seconds")
	check(exact, "The launcher must reopen at exactly 0.8 seconds")
	dog.free()
	launcher.free()


func test_throw_snapshots_target_position_and_velocity_for_non_homing_aim() -> void:
	var launcher := NetLauncherRule.new()
	var dog := _make_dog(Vector3(0.0, 0.0, -12.0))
	dog.velocity = Vector3(3.0, 0.0, 0.0)
	add_child(launcher)
	var projectile_box: Array[NetProjectileRule] = []
	launcher.set_projectile_factory_for_test(func() -> NetProjectileRule:
		var projectile := NetProjectileRule.new()
		projectile_box.append(projectile)
		return projectile
	)
	launcher.update_target_from_candidates(launcher.global_transform, _one_dog(dog), func(_candidate: DogAgentRule) -> bool: return true)

	launcher.try_throw()
	var original_aim := Vector3.ZERO
	if not projectile_box.is_empty():
		original_aim = projectile_box[0].initial_velocity
	dog.position = Vector3(8.0, 0.0, -12.0)
	dog.velocity = Vector3.LEFT * 10.0

	check(not projectile_box.is_empty(), "A valid throw must create one projectile")
	if not projectile_box.is_empty():
		var projectile := projectile_box[0]
		check(projectile.target_position_snapshot == Vector3(0.0, 0.0, -12.0), "Initial aim must snapshot target position")
		check(projectile.target_velocity_snapshot == Vector3(3.0, 0.0, 0.0), "Initial aim must snapshot target velocity")
		check(projectile.initial_velocity == original_aim, "The projectile must not home after the target changes course")
	dog.free()
	launcher.free()


func test_projectile_rejects_non_dog_and_already_captured_hits() -> void:
	var projectile := NetProjectileRule.new()
	var obstacle := StaticBody3D.new()
	var dog: DogAgentRule = DogScene.instantiate() as DogAgentRule
	add_child(dog)
	dog.capture_effect_duration = 10.0
	dog.capture()
	var confirmed := [0]
	projectile.capture_confirmed.connect(func(_stats) -> void: confirmed[0] += 1)

	projectile.simulate_hit(obstacle)
	projectile.simulate_hit(dog)

	check(projectile.resolved, "The first collision must resolve the projectile")
	check(confirmed[0] == 0, "Invalid hit bodies must never confirm capture")
	obstacle.free()
	dog.free()
	projectile.free()


func test_projectile_resolves_miss_at_thirty_metre_range() -> void:
	var projectile := NetProjectileRule.new()
	projectile.max_lifetime = 10.0
	projectile.speed = 30.0
	projectile.launch(Vector3.ZERO, Vector3.FORWARD * 30.0, Vector3.ZERO)

	projectile.simulate_step(0.999)
	check(not projectile.resolved, "A projectile below 30 travelled metres must remain active")
	projectile.simulate_step(0.001)

	check(projectile.resolved, "A projectile must resolve as a miss at 30 travelled metres")
	projectile.free()


func test_projectile_lifetime_resolves_a_stationary_miss() -> void:
	var projectile := NetProjectileRule.new()
	projectile.speed = 0.0
	projectile.max_lifetime = 0.5
	projectile.launch(Vector3.ZERO, Vector3.FORWARD, Vector3.ZERO)

	projectile.simulate_step(0.499)
	check(not projectile.resolved, "A projectile below its lifetime must remain active")
	projectile.simulate_step(0.001)

	check(projectile.resolved, "Projectile lifetime must clean up a miss even without travelled distance")
	projectile.free()


func test_projectile_motion_is_independent_of_launcher_transform_after_launch() -> void:
	var launcher_parent := Node3D.new()
	var projectile := NetProjectileRule.new()
	launcher_parent.rotation.y = PI * 0.5
	add_child(launcher_parent)
	launcher_parent.add_child(projectile)
	projectile.speed = 10.0
	projectile.max_lifetime = 10.0
	projectile.launch(Vector3(2.0, 0.0, 3.0), Vector3(2.0, 0.0, -7.0), Vector3.ZERO)
	var expected_position := projectile.global_position + projectile.initial_velocity * 0.1

	launcher_parent.position = Vector3(20.0, 0.0, 0.0)
	launcher_parent.rotation.y = PI
	projectile.simulate_step(0.1)

	check(
		projectile.global_position.is_equal_approx(expected_position),
		"A launched projectile must continue in world space when its launcher moves or rotates",
	)
	launcher_parent.free()


func test_production_ray_rejects_a_real_obstruction_and_accepts_clear_los() -> void:
	var selector := TargetSelectorRule.new()
	var dog: DogAgentRule = DogScene.instantiate() as DogAgentRule
	var obstacle := StaticBody3D.new()
	var obstacle_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 2.0, 1.0)
	obstacle_shape.shape = box
	obstacle.add_child(obstacle_shape)
	dog.position = Vector3(0.0, 0.0, -10.0)
	obstacle.position = Vector3(0.0, 0.6, -5.0)
	var origin_body := StaticBody3D.new()
	var origin_shape := CollisionShape3D.new()
	var origin_box := BoxShape3D.new()
	origin_box.size = Vector3(1.0, 2.0, 1.0)
	origin_shape.shape = origin_box
	origin_body.add_child(origin_shape)
	origin_body.position = Vector3(0.0, 0.6, 0.0)
	add_child(dog)
	add_child(obstacle)
	add_child(origin_body)
	await get_tree().physics_frame
	var origin := Transform3D(Basis.IDENTITY, Vector3(0.0, 0.6, 0.0))
	var space: PhysicsDirectSpaceState3D = dog.get_world_3d().direct_space_state

	var blocked: DogAgentRule = selector.select(origin, _one_dog(dog), space)
	obstacle.position = Vector3(5.0, 0.6, -5.0)
	await get_tree().physics_frame
	var clear: DogAgentRule = selector.select(origin, _one_dog(dog), space)

	check(blocked == null, "The production ray adapter must reject a dog behind a real physics obstruction")
	check(clear == dog, "The production ray adapter must ignore an enclosing origin body and accept unobstructed LOS")
	origin_body.queue_free()
	obstacle.queue_free()
	dog.queue_free()
	await get_tree().process_frame


func test_projectile_scene_instantiates_as_area_with_collision_shape() -> void:
	var projectile: NetProjectileRule = NetProjectileScene.instantiate() as NetProjectileRule
	check(projectile != null and projectile is Area3D, "The net projectile scene root must be its typed Area3D")
	if projectile != null:
		check(projectile.get_node_or_null("CollisionShape3D") is CollisionShape3D, "The projectile scene must provide a collision shape")
		projectile.free()


func _make_dog(at_position: Vector3) -> DogAgentRule:
	var dog := DogAgentRule.new()
	dog.position = at_position
	return dog


func _one_dog(dog: DogAgentRule) -> Array[DogAgentRule]:
	return [dog]
