class_name SpawnDirector
extends Node3D


const DogAgentRule = preload("res://src/dogs/dog_agent.gd")
const DogAgentScene = preload("res://src/dogs/dog_agent.tscn")
const DogCatalogRule = preload("res://src/dogs/dog_catalog.gd")
const DogStatsRule = preload("res://src/dogs/dog_stats.gd")
const SpawnPointRule = preload("res://src/dogs/spawn_point.gd")
const WeightedPickerRule = preload("res://src/dogs/weighted_picker.gd")
const ACTIVE_DOG_LIMIT := 6
const MINIMUM_PLAYER_DISTANCE := 20.0
const RETRY_DELAY_SECONDS := 2.0
const WORLD_COLLISION_LAYER := 1
const SPAWN_OCCUPANCY_MASK := WORLD_COLLISION_LAYER | DogAgentRule.DOG_COLLISION_LAYER


@export var player: Node3D
@export var camera: Camera3D
@export var map_bounds := Rect2(-100.0, -100.0, 200.0, 200.0)
@export var minimum_player_distance := MINIMUM_PLAYER_DISTANCE:
	set(value):
		minimum_player_distance = maxf(value, MINIMUM_PLAYER_DISTANCE)
@export var spawn_clear_radius := 1.0
@export_flags_3d_physics var spawn_collision_mask := SPAWN_OCCUPANCY_MASK:
	set(value):
		spawn_collision_mask = value | SPAWN_OCCUPANCY_MASK
var max_active_dogs: int:
	get:
		return ACTIVE_DOG_LIMIT
	set(_value):
		pass
var retry_delay: float:
	get:
		return RETRY_DELAY_SECONDS
	set(_value):
		pass
var spawn_attempt_count := 0
var _catalog := DogCatalogRule.new()
var _active_dogs: Array[DogAgentRule] = []
var _test_markers: Array[SpawnPointRule] = []
var _test_markers_set := false
var _test_marker_validation: Dictionary = {}
var _test_roll_source := Callable()
var _test_retry_scheduler := Callable()
# Retry ownership is explicit so repeated failures cannot create parallel timers.
var _retry_pending := false
var _retry_started := false
var _retry_timer: SceneTreeTimer
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
	_release_retry_timer()
	_retry_started = false


func set_test_roll_source(source: Callable) -> void:
	_test_roll_source = source


func set_test_retry_scheduler(scheduler: Callable) -> void:
	_test_retry_scheduler = scheduler


func set_test_markers(markers: Array[SpawnPointRule]) -> void:
	_test_markers = markers.duplicate()
	_test_markers_set = true


func set_test_marker_validation(
	marker: SpawnPointRule,
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
	if active_dog_count() >= ACTIVE_DOG_LIMIT:
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


func get_retry_timer() -> SceneTreeTimer:
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
	# Required production adapters fail closed; a marker is never assumed safe.
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
	if _is_reserved_by_active_dog(marker_position):
		return true
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


func _is_reserved_by_active_dog(marker_position: Vector3) -> bool:
	_prune_active_dogs()
	for dog: DogAgentRule in _active_dogs:
		if _node_position(dog).distance_to(marker_position) <= spawn_clear_radius:
			return true
	return false


func _test_validation_for(marker: SpawnPointRule) -> Dictionary:
	return _test_marker_validation.get(marker.get_instance_id(), {}) as Dictionary


func _node_position(node: Node3D) -> Vector3:
	return node.global_position if node.is_inside_tree() else node.position


func _schedule_retry() -> void:
	if _retry_pending:
		return
	_retry_pending = true
	_start_pending_retry()


func _start_pending_retry() -> void:
	if not _retry_pending or _retry_started or not is_inside_tree():
		return
	_retry_started = true
	var timeout_callback := Callable(self, "_on_retry_timeout")
	if _test_retry_scheduler.is_valid():
		_test_retry_scheduler.call(RETRY_DELAY_SECONDS, timeout_callback)
		return
	_retry_timer = get_tree().create_timer(RETRY_DELAY_SECONDS)
	_retry_timer.timeout.connect(timeout_callback, CONNECT_ONE_SHOT)


func _cancel_retry() -> void:
	_retry_pending = false
	_retry_started = false
	_release_retry_timer()


func _release_retry_timer() -> void:
	var timeout_callback := Callable(self, "_on_retry_timeout")
	if is_instance_valid(_retry_timer) and _retry_timer.timeout.is_connected(timeout_callback):
		_retry_timer.timeout.disconnect(timeout_callback)
	_retry_timer = null


func _on_retry_timeout() -> void:
	if not _retry_pending:
		return
	_retry_pending = false
	_retry_started = false
	_release_retry_timer()
	_maintain_population()


func _on_dog_captured(_stats: DogStatsRule, dog: DogAgentRule) -> void:
	_active_dogs.erase(dog)
	# Capture feedback later emits tree_exiting; both notifications share one deferred fill.
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
	# Deferring avoids mutating the director's children during capture/tree-exit signals.
	_maintenance_scheduled = true
	call_deferred("_run_scheduled_population_maintenance")


func _run_scheduled_population_maintenance() -> void:
	_maintenance_scheduled = false
	if not _is_shutting_down and not is_queued_for_deletion():
		_maintain_population()


func _maintain_population() -> void:
	while active_dog_count() < ACTIVE_DOG_LIMIT:
		if request_dog_spawn() == null:
			return


func _prune_active_dogs() -> void:
	for index in range(_active_dogs.size() - 1, -1, -1):
		if not is_instance_valid(_active_dogs[index]):
			_active_dogs.remove_at(index)
