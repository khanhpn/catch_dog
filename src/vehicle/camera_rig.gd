class_name VehicleCameraRig
extends Node3D


const PlayerVehicleRule = preload("res://src/vehicle/player_vehicle.gd")


@export var base_distance := 6.0
@export var speed_pullback := 2.0
@export var follow_height := 2.4
@export var focus_height := 1.0
@export var position_smoothing := 8.0
@export var collision_margin := 0.35
@export var turn_roll_scale := 0.3


var _target: PlayerVehicleRule


@onready var _camera := $Camera3D as Camera3D
@onready var _collision_probe := $CameraCollisionProbe as ShapeCast3D


func _ready() -> void:
	_target = get_parent_node_3d() as PlayerVehicleRule
	if _target == null:
		set_physics_process(false)
		return
	top_level = true
	global_transform = Transform3D(Basis.IDENTITY, _focus_position())
	_collision_probe.add_exception(_target)
	_camera.global_position = _desired_camera_position()
	_camera.look_at(_focus_position(), Vector3.UP)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(_target):
		return
	var focus := _focus_position()
	var smoothing_weight := 1.0 - exp(-position_smoothing * delta)
	global_position = global_position.lerp(focus, smoothing_weight)
	var desired_position := _desired_camera_position()
	var desired_distance := focus.distance_to(desired_position)
	var current_distance := focus.distance_to(_camera.global_position)
	var obstruction_distance := _obstruction_distance(focus, desired_position)
	var resolved_distance := resolve_camera_distance(
		current_distance,
		desired_distance,
		obstruction_distance,
		delta,
	)
	# Snap inward on obstruction, then smooth only the outward recovery to prevent wall clipping.
	_camera.global_position = focus + focus.direction_to(desired_position) * resolved_distance
	_camera.look_at(focus, Vector3.UP)
	var visual_pivot := _target.get_node_or_null("VisualPivot") as Node3D
	if visual_pivot != null:
		_camera.rotate_object_local(Vector3.FORWARD, visual_pivot.rotation.z * turn_roll_scale)


func _focus_position() -> Vector3:
	if not is_instance_valid(_target):
		return global_position
	return _target.global_position + Vector3.UP * focus_height


func _desired_camera_position() -> Vector3:
	if not is_instance_valid(_target):
		return global_position
	var max_speed := maxf(_target.stats.max_speed_mps, 0.01)
	var ratio: float = clampf(absf(_target.forward_speed) / max_speed, 0.0, 1.0)
	var distance := base_distance + speed_pullback * ratio
	return _focus_position() + _target.global_basis.z * distance + Vector3.UP * follow_height


func resolve_camera_distance(
	current_distance: float,
	desired_distance: float,
	obstruction_distance: float,
	delta: float,
) -> float:
	var safe_desired := maxf(desired_distance, 0.0)
	var target_distance := safe_desired
	if obstruction_distance >= 0.0 and obstruction_distance < safe_desired:
		target_distance = maxf(obstruction_distance - collision_margin, 0.0)
	if target_distance < current_distance:
		return target_distance
	var smoothing_weight := 1.0 - exp(-position_smoothing * maxf(delta, 0.0))
	return lerpf(maxf(current_distance, 0.0), target_distance, smoothing_weight)


func _obstruction_distance(focus: Vector3, desired: Vector3) -> float:
	_collision_probe.global_position = focus
	_collision_probe.target_position = desired - focus
	_collision_probe.force_shapecast_update()
	if not _collision_probe.is_colliding():
		return focus.distance_to(desired)
	return focus.distance_to(_collision_probe.get_collision_point(0))
