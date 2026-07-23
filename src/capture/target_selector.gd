class_name TargetSelector
extends RefCounted


const DogAgentRule = preload("res://src/dogs/dog_agent.gd")
const DogStatsRule = preload("res://src/dogs/dog_stats.gd")


signal target_changed(target: DogAgentRule)


const HALF_ANGLE_DEGREES := 30.0
const MAX_RANGE_METERS := 24.0
var _target_ref: WeakRef
var _target_instance_id := 0


func select(
	origin: Transform3D,
	dogs: Array[DogAgentRule],
	space: PhysicsDirectSpaceState3D,
) -> DogAgentRule:
	return select_from_candidates(
		origin,
		dogs,
		func(dog: DogAgentRule) -> bool: return _has_line_of_sight(origin, dog, space),
	)


func select_from_candidates(
	origin: Transform3D,
	dogs: Array[DogAgentRule],
	has_line_of_sight: Callable = Callable(),
) -> DogAgentRule:
	var forward := -origin.basis.z.normalized()
	# Match Vector3's float32 representation without widening the cone via a tolerance.
	var minimum_dot := Vector3(cos(deg_to_rad(HALF_ANGLE_DEGREES)), 0.0, 0.0).x
	var best: DogAgentRule
	var best_dot := -1.0
	var best_distance := INF
	for dog: DogAgentRule in dogs:
		if not _is_active(dog):
			continue
		var offset := _dog_position(dog) - origin.origin
		var distance := offset.length()
		if distance <= 0.0 or distance > MAX_RANGE_METERS:
			continue
		var alignment := forward.dot(offset / distance)
		if alignment < minimum_dot:
			continue
		if has_line_of_sight.is_valid() and not bool(has_line_of_sight.call(dog)):
			continue
		if alignment > best_dot or (alignment == best_dot and distance < best_distance):
			best = dog
			best_dot = alignment
			best_distance = distance
	_set_target(best)
	return best


func current_target() -> DogAgentRule:
	if _target_ref == null:
		return null
	var target := _target_ref.get_ref() as DogAgentRule
	if not _is_active(target):
		_set_target(null)
		return null
	return target


func clear_target() -> void:
	_set_target(null)


func _has_line_of_sight(
	origin: Transform3D,
	dog: DogAgentRule,
	space: PhysicsDirectSpaceState3D,
) -> bool:
	if space == null or not is_instance_valid(dog):
		return false
	var query := PhysicsRayQueryParameters3D.create(origin.origin, _dog_position(dog))
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.hit_from_inside = false
	var hit := space.intersect_ray(query)
	return hit.is_empty() or hit.get("collider") == dog


func _is_active(dog: DogAgentRule) -> bool:
	return (
		is_instance_valid(dog)
		and dog.state != DogAgentRule.State.CAPTURED
		and not dog.is_queued_for_deletion()
	)


func _dog_position(dog: DogAgentRule) -> Vector3:
	return dog.capture_target_position()


func _set_target(target: DogAgentRule) -> void:
	var new_instance_id := target.get_instance_id() if is_instance_valid(target) else 0
	if new_instance_id == _target_instance_id:
		return
	_disconnect_target_signals()
	_target_ref = null
	_target_instance_id = new_instance_id
	if target != null:
		_target_ref = weakref(target)
		target.captured.connect(_on_target_captured)
		target.tree_exiting.connect(_on_target_tree_exiting)
	target_changed.emit(target)


func _disconnect_target_signals() -> void:
	if _target_ref == null:
		return
	var target := _target_ref.get_ref() as DogAgentRule
	if not is_instance_valid(target):
		return
	if target.captured.is_connected(_on_target_captured):
		target.captured.disconnect(_on_target_captured)
	if target.tree_exiting.is_connected(_on_target_tree_exiting):
		target.tree_exiting.disconnect(_on_target_tree_exiting)


func _on_target_captured(_stats: DogStatsRule) -> void:
	_set_target(null)


func _on_target_tree_exiting() -> void:
	_set_target(null)
