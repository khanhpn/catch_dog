extends "res://tests/test_case.gd"


const PlayerVehicleScene = preload("res://src/vehicle/player_vehicle.tscn")
const FuelPickupScene = preload("res://src/vehicle/fuel_pickup.tscn")


func test_acceleration_consumes_more_than_coasting() -> void:
	var accelerated_vehicle: Variant = PlayerVehicleScene.instantiate()
	add_child(accelerated_vehicle)
	var initial: float = accelerated_vehicle.fuel_percent()
	accelerated_vehicle.simulate_controls(1.0, 0.0, 1.0)
	var accelerated: float = initial - accelerated_vehicle.fuel_percent()

	var coasting_vehicle: Variant = PlayerVehicleScene.instantiate()
	add_child(coasting_vehicle)
	coasting_vehicle.simulate_controls(0.0, 0.0, 1.0)
	var coasted: float = 1.0 - coasting_vehicle.fuel_percent()

	check(accelerated > coasted, "Accelerating must consume more fuel than coasting")
	accelerated_vehicle.free()
	coasting_vehicle.free()


func test_refill_clamps_at_full_capacity() -> void:
	var vehicle: Variant = PlayerVehicleScene.instantiate()
	add_child(vehicle)
	vehicle.simulate_controls(1.0, 0.0, 10.0)
	vehicle.refill_fuel(1000.0)
	check(is_equal_approx(vehicle.fuel_percent(), 1.0), "Vehicle refill must clamp at full capacity")
	vehicle.free()


func test_low_fuel_reduces_vehicle_top_speed() -> void:
	var full_vehicle: Variant = PlayerVehicleScene.instantiate()
	add_child(full_vehicle)
	full_vehicle.simulate_controls(1.0, 0.0, 1.0)
	var full_fuel_speed: float = full_vehicle.forward_speed

	var low_vehicle: Variant = PlayerVehicleScene.instantiate()
	add_child(low_vehicle)
	low_vehicle.simulate_controls(1.0, 0.0, 99.0)
	low_vehicle.forward_speed = 0.0
	low_vehicle.simulate_controls(1.0, 0.0, 1.0)

	check(low_vehicle.fuel_percent() <= 0.01, "Test setup must leave the second vehicle nearly empty")
	check(low_vehicle.forward_speed < full_fuel_speed, "Low fuel must reduce the speed reachable through vehicle controls")
	full_vehicle.free()
	low_vehicle.free()


func test_empty_fuel_disables_propulsion() -> void:
	var vehicle: Variant = PlayerVehicleScene.instantiate()
	add_child(vehicle)
	vehicle.simulate_controls(1.0, 0.0, 100.0)
	vehicle.forward_speed = 0.0

	vehicle.simulate_controls(1.0, 0.0, 1.0)

	check(is_zero_approx(vehicle.fuel_percent()), "Test setup must empty the vehicle fuel")
	check(is_zero_approx(vehicle.forward_speed), "An empty vehicle must not produce propulsion")
	vehicle.free()


func test_brake_decelerates_without_reversing() -> void:
	var vehicle: Variant = PlayerVehicleScene.instantiate()
	add_child(vehicle)
	vehicle.simulate_controls(1.0, 0.0, 0.25)
	var moving_speed: float = vehicle.forward_speed

	vehicle.simulate_controls(-1.0, 0.0, 1.0)

	check(vehicle.forward_speed < moving_speed, "Brake input must reduce forward speed")
	check(vehicle.forward_speed >= 0.0, "Brake input must never reverse the vehicle")
	vehicle.free()


func test_braking_uses_less_fuel_than_accelerating() -> void:
	var accelerating_vehicle: Variant = PlayerVehicleScene.instantiate()
	add_child(accelerating_vehicle)
	accelerating_vehicle.simulate_controls(1.0, 0.0, 0.25)
	var accelerated_consumption: float = 1.0 - accelerating_vehicle.fuel_percent()

	var braking_vehicle: Variant = PlayerVehicleScene.instantiate()
	add_child(braking_vehicle)
	braking_vehicle.simulate_controls(1.0, 0.0, 0.25)
	braking_vehicle.refill_fuel(100.0)
	braking_vehicle.simulate_controls(-1.0, 0.0, 0.25)
	var braking_consumption: float = 1.0 - braking_vehicle.fuel_percent()

	check(braking_consumption < accelerated_consumption, "Braking must use the idle fuel rate, not the acceleration rate")
	accelerating_vehicle.free()
	braking_vehicle.free()


func test_fuel_pickup_collects_only_once() -> void:
	var vehicle: Variant = PlayerVehicleScene.instantiate()
	add_child(vehicle)
	vehicle.simulate_controls(1.0, 0.0, 100.0)
	var pickup: Variant = FuelPickupScene.instantiate()
	add_child(pickup)
	var collected_emissions := [0]
	pickup.collected.connect(func() -> void: collected_emissions[0] += 1)

	pickup.collect(vehicle)
	pickup.collect(vehicle)

	check(is_equal_approx(vehicle.fuel_percent(), 0.35), "A fuel pickup must add exactly 35 fuel points once")
	check(collected_emissions[0] == 1, "A fuel pickup must emit collected only once")
	check(pickup.collision_layer == 0 and pickup.collision_mask == 0, "A collected pickup must disable collision immediately")
	pickup.free()
	vehicle.free()


func test_pickup_restores_35_percent_with_nonstandard_capacity() -> void:
	var vehicle: Variant = PlayerVehicleScene.instantiate()
	vehicle.stats = vehicle.stats.duplicate()
	vehicle.stats.fuel_capacity = 200.0
	add_child(vehicle)
	vehicle.simulate_controls(1.0, 0.0, 200.0)
	var pickup: Variant = FuelPickupScene.instantiate()
	add_child(pickup)

	pickup.collect(vehicle)

	check(is_equal_approx(vehicle.fuel_percent(), 0.35), "A 35-point pickup must restore 35 percent at any fuel capacity")
	pickup.free()
	vehicle.free()


func test_stopped_without_fuel_emits_once_after_post_move_evaluation() -> void:
	var vehicle: Variant = PlayerVehicleScene.instantiate()
	add_child(vehicle)
	var stopped_emissions := [0]
	vehicle.stopped_without_fuel.connect(func() -> void: stopped_emissions[0] += 1)

	vehicle.simulate_controls(1.0, 0.0, 100.0)
	check(stopped_emissions[0] == 0, "Control simulation must wait for post-move terminal evaluation")
	vehicle.simulate_controls(0.0, 0.0, 100.0)
	vehicle._check_stopped_without_fuel()
	vehicle.simulate_controls(0.0, 0.0, 1.0)
	vehicle._check_stopped_without_fuel()

	check(vehicle.is_stopped_without_fuel(), "Vehicle must report stopped after empty fuel and speed below the threshold")
	check(stopped_emissions[0] == 1, "Stopped-without-fuel must emit once at the threshold")
	vehicle.free()


func test_terminal_signal_uses_post_move_collision_velocity() -> void:
	var vehicle: Variant = PlayerVehicleScene.instantiate()
	add_child(vehicle)
	vehicle.fuel_percent()
	vehicle.fuel.amount = 0.0
	vehicle.forward_speed = 0.1
	var stopped_emissions := [0]
	vehicle.stopped_without_fuel.connect(func() -> void: stopped_emissions[0] += 1)

	vehicle.simulate_controls(0.0, 0.0, 0.0)
	check(stopped_emissions[0] == 0, "Control simulation must not emit before actual movement resolves")
	vehicle.velocity = Vector3.ZERO
	vehicle._check_stopped_without_fuel()

	check(stopped_emissions[0] == 1, "Collision-induced stopping must emit from actual post-move velocity")
	vehicle.free()


func test_stopped_signal_latch_resets_after_refill() -> void:
	var vehicle: Variant = PlayerVehicleScene.instantiate()
	add_child(vehicle)
	vehicle.fuel_percent()
	var stopped_emissions := [0]
	vehicle.stopped_without_fuel.connect(func() -> void: stopped_emissions[0] += 1)
	vehicle.fuel.amount = 0.0
	vehicle.velocity = Vector3.ZERO
	vehicle._check_stopped_without_fuel()
	vehicle._check_stopped_without_fuel()

	vehicle.refill_fuel(10.0)
	vehicle.simulate_controls(1.0, 0.0, 10.0)
	vehicle.velocity = Vector3.ZERO
	vehicle._check_stopped_without_fuel()

	check(stopped_emissions[0] == 2, "A refill must re-arm one terminal signal for a later depletion")
	vehicle.free()


func test_standstill_cannot_yaw_or_lean() -> void:
	var vehicle: Variant = PlayerVehicleScene.instantiate()
	add_child(vehicle)

	vehicle.simulate_controls(0.0, 1.0, 1.0)
	var visual_pivot := vehicle.get_node("VisualPivot") as Node3D

	check(is_zero_approx(vehicle.rotation.y), "A stationary vehicle must not yaw from steering")
	check(is_zero_approx(visual_pivot.rotation.z), "A stationary vehicle must not visually lean")
	vehicle.free()


func test_camera_follow_transform_smooths_translation_and_converges() -> void:
	var vehicle: Variant = PlayerVehicleScene.instantiate()
	add_child(vehicle)
	var camera_rig: Variant = vehicle.get_node("CameraRig")
	check(camera_rig.has_method("smooth_follow_transform"), "Camera rig must expose deterministic transform smoothing")
	if not camera_rig.has_method("smooth_follow_transform"):
		vehicle.free()
		return
	var current := Transform3D.IDENTITY
	var desired := Transform3D(Basis.IDENTITY, Vector3(10.0, 0.0, 0.0))

	var first: Transform3D = camera_rig.smooth_follow_transform(current, desired, 0.1)
	check(first.origin.x > 0.0 and first.origin.x < desired.origin.x, "One camera update must advance between old and desired positions")

	var converged := first
	for index in range(20):
		converged = camera_rig.smooth_follow_transform(converged, desired, 0.1)
	check(converged.origin.distance_to(desired.origin) < 0.001, "Repeated camera updates must converge to translated target pose")
	vehicle.free()


func test_camera_follow_transform_smooths_yaw_and_converges() -> void:
	var vehicle: Variant = PlayerVehicleScene.instantiate()
	add_child(vehicle)
	var camera_rig: Variant = vehicle.get_node("CameraRig")
	check(camera_rig.has_method("smooth_follow_transform"), "Camera rig must expose deterministic transform smoothing")
	if not camera_rig.has_method("smooth_follow_transform"):
		vehicle.free()
		return
	var current := Transform3D.IDENTITY
	var desired := Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO)

	var first: Transform3D = camera_rig.smooth_follow_transform(current, desired, 0.1)
	check(first.basis.z.x > 0.0 and first.basis.z.z > 0.0, "One camera update must rotate between old and desired yaw")

	var converged := first
	for index in range(20):
		converged = camera_rig.smooth_follow_transform(converged, desired, 0.1)
	check(converged.basis.z.dot(desired.basis.z) > 0.9999, "Repeated camera updates must converge to target yaw")
	vehicle.free()


func test_camera_obstruction_snaps_inward_and_recovers_smoothly() -> void:
	var vehicle: Variant = PlayerVehicleScene.instantiate()
	add_child(vehicle)
	var camera_rig: Variant = vehicle.get_node("CameraRig")
	check(camera_rig.has_method("resolve_camera_distance"), "Camera rig must expose deterministic distance resolution")
	if not camera_rig.has_method("resolve_camera_distance"):
		vehicle.free()
		return

	var inward: float = camera_rig.resolve_camera_distance(8.0, 8.0, 3.0, 0.1)
	var outward: float = camera_rig.resolve_camera_distance(inward, 8.0, 8.0, 0.1)

	check(is_equal_approx(inward, 3.0 - camera_rig.collision_margin), "Camera obstruction must snap inward with collision margin")
	check(outward > inward and outward < 8.0, "Camera must smooth outward recovery after an obstruction clears")
	vehicle.free()


func test_vehicle_scene_separates_visual_lean_and_has_camera_probe() -> void:
	var vehicle: Variant = PlayerVehicleScene.instantiate()
	add_child(vehicle)
	vehicle.simulate_controls(1.0, 1.0, 0.1)
	var visual_pivot := vehicle.get_node_or_null("VisualPivot") as Node3D
	var camera_probe := vehicle.get_node_or_null("CameraRig/CameraCollisionProbe") as ShapeCast3D

	check(visual_pivot != null and not is_zero_approx(visual_pivot.rotation.z), "Steering must lean only the visual pivot")
	check(is_zero_approx(vehicle.rotation.z), "The CharacterBody3D collision orientation must remain upright")
	check(camera_probe != null and camera_probe.enabled, "The camera rig must include an enabled collision probe")
	vehicle.free()
