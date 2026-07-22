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


func test_stopped_without_fuel_emits_once_at_threshold() -> void:
	var vehicle: Variant = PlayerVehicleScene.instantiate()
	add_child(vehicle)
	var stopped_emissions := [0]
	vehicle.stopped_without_fuel.connect(func() -> void: stopped_emissions[0] += 1)

	vehicle.simulate_controls(1.0, 0.0, 100.0)
	check(stopped_emissions[0] == 0, "An empty moving vehicle must not emit the stopped signal")
	vehicle.simulate_controls(0.0, 0.0, 100.0)
	vehicle.simulate_controls(0.0, 0.0, 1.0)

	check(vehicle.is_stopped_without_fuel(), "Vehicle must report stopped after empty fuel and speed below the threshold")
	check(stopped_emissions[0] == 1, "Stopped-without-fuel must emit once at the threshold")
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
