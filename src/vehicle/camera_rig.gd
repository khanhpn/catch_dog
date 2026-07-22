class_name VehicleCameraRig
extends Node3D


@export var base_distance := 6.0
@export var speed_pullback := 2.0
@export var follow_height := 2.4
@export var focus_height := 1.0
@export var position_smoothing := 8.0
@export var collision_margin := 0.35
@export var turn_roll_scale := 0.3


var _target: Node3D


@onready var _camera := $Camera3D as Camera3D
@onready var _collision_probe := $CameraCollisionProbe as ShapeCast3D


func _ready() -> void:
	_target = get_parent_node_3d()
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
	var resolved_position := _collision_resolved_position(focus, _desired_camera_position())
	# Snap inward on obstruction, then smooth only the outward recovery to prevent wall clipping.
	if focus.distance_to(resolved_position) < focus.distance_to(_camera.global_position):
		_camera.global_position = resolved_position
	else:
		_camera.global_position = _camera.global_position.lerp(resolved_position, smoothing_weight)
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
	var max_speed := 18.0
	var vehicle_stats: Variant = _target.get("stats")
	if vehicle_stats != null:
		max_speed = maxf(float(vehicle_stats.get("max_speed_mps")), 0.01)
	var ratio: float = clampf(absf(float(_target.get("forward_speed"))) / max_speed, 0.0, 1.0)
	var distance := base_distance + speed_pullback * ratio
	return _focus_position() + _target.global_basis.z * distance + Vector3.UP * follow_height


func _collision_resolved_position(focus: Vector3, desired: Vector3) -> Vector3:
	_collision_probe.global_position = focus
	_collision_probe.target_position = desired - focus
	_collision_probe.force_shapecast_update()
	if not _collision_probe.is_colliding():
		return desired
	var travel_direction := focus.direction_to(desired)
	var hit_distance := focus.distance_to(_collision_probe.get_collision_point(0))
	return focus + travel_direction * maxf(hit_distance - collision_margin, 0.0)
