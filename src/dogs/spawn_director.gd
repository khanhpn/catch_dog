class_name SpawnDirector
extends Node3D


const DogAgentRule = preload("res://src/dogs/dog_agent.gd")
const DogAgentScene = preload("res://src/dogs/dog_agent.tscn")
const DogCatalogRule = preload("res://src/dogs/dog_catalog.gd")
const DogStatsRule = preload("res://src/dogs/dog_stats.gd")
const SpawnPointRule = preload("res://src/dogs/spawn_point.gd")
const WeightedPickerRule = preload("res://src/dogs/weighted_picker.gd")


@export var player: Node3D
@export var camera: Camera3D
@export var map_bounds := Rect2(-100.0, -100.0, 200.0, 200.0)
@export var minimum_player_distance := 20.0
@export var spawn_clear_radius := 1.0
@export_flags_3d_physics var spawn_collision_mask := 1
@export var max_active_dogs := 6
@export var retry_delay := 2.0
var spawn_attempt_count := 0
var _catalog := DogCatalogRule.new()
var _active_dogs: Array[DogAgentRule] = []
var _test_markers: Array[SpawnPointRule] = []
var _test_markers_set := false
var _test_marker_validation: Dictionary = {}
var _test_roll_source := Callable()
var _retry_timer: Timer
var _maintenance_scheduled := false
var _is_shutting_down := false


func _enter_tree() -> void:
	_is_shutting_down = false
	call_deferred("_start_pending_retry")


func _ready() -> void:
	_start_pending_retry()
	_maintain_population()


func _exit_tree() -> void:
	_is_shutting_down = true


func set_test_roll_source(source: Callable) -> void:
	_test_roll_source = source


func set_test_markers(markers: Array) -> void:
	_test_markers.clear()
	for marker: Variant in markers:
		var typed_marker := marker as SpawnPointRule
		if typed_marker != null:
			_test_markers.append(typed_marker)
	_test_markers_set = true


func set_test_marker_validation(
	marker: Node3D,
	visible: bool,
	blocked: bool,
	in_bounds: bool,
) -> void:
	_test_marker_validation[marker.get_instance_id()] = {
		"visible": visible,
		"blocked": blocked,
		"in_bounds": in_bounds,
	}


func pick_dog_stats() -> DogStatsRule:
	var weights := PackedFloat32Array()
	for entry: DogStatsRule in _catalog.entries:
		weights.append(entry.weight)
	var roll: float
	if _test_roll_source.is_valid():
		roll = float(_test_roll_source.call())
	else:
		roll = randf()
	var index := WeightedPickerRule.pick_index(weights, roll)
	if index == WeightedPickerRule.INVALID_INDEX:
		return null
	return _catalog.entries[index]


func choose_spawn_marker() -> SpawnPointRule:
	for marker: SpawnPointRule in _spawn_markers():
		if _is_spawn_marker_valid(marker):
			return marker
	return null


func request_dog_spawn() -> DogAgentRule:
	spawn_attempt_count += 1
	if active_dog_count() >= max_active_dogs:
		return null
	var marker := choose_spawn_marker()
	if marker == null:
		_schedule_retry()
		return null
	var selected_stats := pick_dog_stats()
	if selected_stats == null:
		_schedule_retry()
		return null
	var dog := DogAgentScene.instantiate() as DogAgentRule
	dog.stats = selected_stats
	add_child(dog)
	if dog.is_inside_tree() and marker.is_inside_tree():
		dog.global_position = marker.global_position
	else:
		dog.position = marker.position
	_active_dogs.append(dog)
	dog.captured.connect(_on_dog_captured.bind(dog))
	dog.tree_exiting.connect(_on_dog_tree_exiting.bind(dog))
	_cancel_retry()
	return dog


func active_dog_count() -> int:
	_prune_active_dogs()
	return _active_dogs.size()


func get_retry_timer() -> Timer:
	return _retry_timer if is_instance_valid(_retry_timer) else null


func _spawn_markers() -> Array[SpawnPointRule]:
	if _test_markers_set:
		return _test_markers
	var markers: Array[SpawnPointRule] = []
	if not is_inside_tree():
		return markers
	for node: Node in get_tree().get_nodes_in_group(&"dog_spawn_points"):
		var marker := node as SpawnPointRule
		if marker != null:
			markers.append(marker)
	return markers


func _is_spawn_marker_valid(marker: SpawnPointRule) -> bool:
	if player == null:
		return false
	var marker_position := _node_position(marker)
	if marker_position.distance_to(_node_position(player)) < minimum_player_distance:
		return false
	if _is_marker_visible(marker, marker_position):
		return false
	if not _is_marker_in_bounds(marker, marker_position):
		return false
	return not _is_marker_blocked(marker, marker_position)


func _is_marker_visible(marker: SpawnPointRule, marker_position: Vector3) -> bool:
	var override := _test_validation_for(marker)
	if not override.is_empty():
		return bool(override.visible)
	var active_camera := camera
	if active_camera == null and is_inside_tree():
		active_camera = get_viewport().get_camera_3d()
	return active_camera == null or active_camera.is_position_in_frustum(marker_position)


func _is_marker_in_bounds(marker: SpawnPointRule, marker_position: Vector3) -> bool:
	var override := _test_validation_for(marker)
	if not override.is_empty():
		return bool(override.in_bounds)
	return map_bounds.has_point(Vector2(marker_position.x, marker_position.z))


func _is_marker_blocked(marker: SpawnPointRule, marker_position: Vector3) -> bool:
	var override := _test_validation_for(marker)
	if not override.is_empty():
		return bool(override.blocked)
	if not is_inside_tree():
		return true
	var query := PhysicsShapeQueryParameters3D.new()
	var shape := SphereShape3D.new()
	shape.radius = spawn_clear_radius
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, marker_position)
	query.collision_mask = spawn_collision_mask
	query.collide_with_areas = true
	query.collide_with_bodies = true
	return not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func _test_validation_for(marker: SpawnPointRule) -> Dictionary:
	return _test_marker_validation.get(marker.get_instance_id(), {}) as Dictionary


func _node_position(node: Node3D) -> Vector3:
	return node.global_position if node.is_inside_tree() else node.position


func _schedule_retry() -> void:
	if is_instance_valid(_retry_timer):
		return
	_retry_timer = Timer.new()
	_retry_timer.name = "SpawnRetryTimer"
	_retry_timer.one_shot = true
	_retry_timer.wait_time = retry_delay
	_retry_timer.timeout.connect(_on_retry_timeout)
	add_child(_retry_timer)
	_start_pending_retry()


func _start_pending_retry() -> void:
	if (
		is_instance_valid(_retry_timer)
		and _retry_timer.is_inside_tree()
		and _retry_timer.is_stopped()
	):
		_retry_timer.start()


func _cancel_retry() -> void:
	if not is_instance_valid(_retry_timer):
		return
	var timer := _retry_timer
	_retry_timer = null
	timer.queue_free()


func _on_retry_timeout() -> void:
	var timer := _retry_timer
	_retry_timer = null
	if is_instance_valid(timer):
		timer.queue_free()
	_maintain_population()


func _on_dog_captured(_stats: DogStatsRule, dog: DogAgentRule) -> void:
	_active_dogs.erase(dog)
	_schedule_population_maintenance()


func _on_dog_tree_exiting(dog: DogAgentRule) -> void:
	_active_dogs.erase(dog)
	_schedule_population_maintenance()


func _schedule_population_maintenance() -> void:
	if _is_shutting_down or is_queued_for_deletion():
		return
	if not is_inside_tree():
		_maintain_population()
		return
	if _maintenance_scheduled:
		return
	_maintenance_scheduled = true
	call_deferred("_run_scheduled_population_maintenance")


func _run_scheduled_population_maintenance() -> void:
	_maintenance_scheduled = false
	if not _is_shutting_down and not is_queued_for_deletion():
		_maintain_population()


func _maintain_population() -> void:
	while active_dog_count() < max_active_dogs:
		if request_dog_spawn() == null:
			return


func _prune_active_dogs() -> void:
	for index in range(_active_dogs.size() - 1, -1, -1):
		if not is_instance_valid(_active_dogs[index]):
			_active_dogs.remove_at(index)
