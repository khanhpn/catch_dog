class_name PlayerVehicle
extends CharacterBody3D


signal fuel_changed(percent: float)
signal stopped_without_fuel


const FuelModelRule = preload("res://src/vehicle/fuel_model.gd")
const PlayerVehicleStatsRule = preload("res://src/vehicle/player_vehicle_stats.gd")


@export var stats: PlayerVehicleStatsRule
var forward_speed: float = 0.0
var fuel: FuelModelRule
var _stopped_signal_emitted := false


var _visual_pivot: Node3D


func _ready() -> void:
	_ensure_initialized()


func _ensure_initialized() -> void:
	if fuel != null:
		return
	if stats == null:
		stats = PlayerVehicleStatsRule.new()
	fuel = FuelModelRule.new(
		stats.fuel_capacity,
		stats.idle_fuel_rate,
		stats.throttle_fuel_rate,
	)
	_visual_pivot = get_node_or_null("VisualPivot") as Node3D


func _physics_process(delta: float) -> void:
	var throttle := Input.get_action_strength("accelerate")
	var brake := Input.get_action_strength("brake")
	if brake > 0.0:
		throttle = -brake
	var steer := Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")
	simulate_controls(throttle, steer, delta)
	if not is_on_floor():
		velocity.y -= float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)) * delta
	else:
		velocity.y = 0.0
	move_and_slide()
	_check_stopped_without_fuel()


func simulate_controls(throttle: float, steer: float, delta: float) -> void:
	_ensure_initialized()
	var safe_delta := maxf(delta, 0.0)
	var safe_throttle := clampf(throttle, -1.0, 1.0)
	var safe_steer := clampf(steer, -1.0, 1.0)
	var acceleration_input := maxf(safe_throttle, 0.0)
	var previous_percent := fuel_percent()
	fuel.consume(safe_delta, acceleration_input)
	var speed_limit := stats.max_speed_mps * fuel.top_speed_scale()
	var target_speed := acceleration_input * speed_limit if fuel.amount > 0.0 else 0.0
	forward_speed = move_toward(
		forward_speed,
		target_speed,
		stats.acceleration_mps2 * safe_delta,
	)
	forward_speed = maxf(forward_speed, 0.0)
	rotation.y -= safe_steer * stats.steer_radians_per_second * safe_delta * speed_ratio()
	var movement_basis := global_basis if is_inside_tree() else basis
	var forward := -movement_basis.z
	velocity.x = forward.x * forward_speed
	velocity.z = forward.z * forward_speed
	# Lean is visual feedback only; the CharacterBody3D stays upright so its collision remains stable.
	if _visual_pivot != null:
		_visual_pivot.rotation.z = -safe_steer * stats.visual_lean_radians * speed_ratio()
	var current_percent := fuel_percent()
	if not is_equal_approx(previous_percent, current_percent):
		fuel_changed.emit(current_percent)


func fuel_percent() -> float:
	_ensure_initialized()
	if fuel == null or is_zero_approx(fuel.capacity):
		return 0.0
	return fuel.amount / fuel.capacity


func refill_fuel(amount: float) -> void:
	_ensure_initialized()
	var previous_percent := fuel_percent()
	var raw_refill := maxf(amount, 0.0) * 0.01 * fuel.capacity
	fuel.refill(raw_refill)
	var current_percent := fuel_percent()
	if not is_equal_approx(previous_percent, current_percent):
		fuel_changed.emit(current_percent)
	if fuel.amount > 0.0:
		_stopped_signal_emitted = false


func is_stopped_without_fuel() -> bool:
	_ensure_initialized()
	return (
		fuel != null
		and is_zero_approx(fuel.amount)
		and Vector2(velocity.x, velocity.z).length() < 0.2
	)


func speed_ratio() -> float:
	if stats == null or is_zero_approx(stats.max_speed_mps):
		return 0.0
	return clampf(absf(forward_speed) / stats.max_speed_mps, 0.0, 1.0)


func _check_stopped_without_fuel() -> void:
	if is_stopped_without_fuel() and not _stopped_signal_emitted:
		_stopped_signal_emitted = true
		stopped_without_fuel.emit()
