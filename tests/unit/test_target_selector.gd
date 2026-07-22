extends "res://tests/test_case.gd"


const DogAgentRule = preload("res://src/dogs/dog_agent.gd")
const DogScene = preload("res://src/dogs/dog_agent.tscn")
const TargetSelectorRule = preload("res://src/capture/target_selector.gd")


func test_cone_includes_thirty_degrees_and_rejects_beyond_it() -> void:
	var selector := TargetSelectorRule.new()
	var boundary_dog := _make_dog(_direction_at_degrees(30.0) * 10.0)
	var outside_dog := _make_dog(_direction_at_degrees(30.1) * 10.0)

	var selected: DogAgentRule = selector.select_from_candidates(
		Transform3D.IDENTITY,
		_dogs(boundary_dog, outside_dog),
		func(_dog: DogAgentRule) -> bool: return true,
	)

	check(selected == boundary_dog, "The targeting cone must use an inclusive 30-degree half-angle")
	boundary_dog.free()
	outside_dog.free()


func test_range_includes_twenty_four_metres_and_rejects_beyond_it() -> void:
	var selector := TargetSelectorRule.new()
	var boundary_dog := _make_dog(Vector3.FORWARD * 24.0)
	var outside_dog := _make_dog(Vector3.FORWARD * 24.01)

	var selected: DogAgentRule = selector.select_from_candidates(
		Transform3D.IDENTITY,
		_dogs(boundary_dog, outside_dog),
		func(_dog: DogAgentRule) -> bool: return true,
	)

	check(selected == boundary_dog, "The targeting range must include exactly 24 metres and exclude greater distances")
	boundary_dog.free()
	outside_dog.free()


func test_prefers_angular_alignment_before_distance() -> void:
	var selector := TargetSelectorRule.new()
	var near_side_dog := _make_dog(_direction_at_degrees(10.0) * 5.0)
	var far_front_dog := _make_dog(Vector3.FORWARD * 20.0)

	var selected: DogAgentRule = selector.select_from_candidates(
		Transform3D.IDENTITY,
		_dogs(near_side_dog, far_front_dog),
		func(_dog: DogAgentRule) -> bool: return true,
	)

	check(selected == far_front_dog, "Angular error must rank before distance")
	near_side_dog.free()
	far_front_dog.free()


func test_uses_distance_to_break_equal_angle_ties() -> void:
	var selector := TargetSelectorRule.new()
	var far_dog := _make_dog(_direction_at_degrees(10.0) * 20.0)
	var near_dog := _make_dog(_direction_at_degrees(10.0) * 5.0)

	var selected: DogAgentRule = selector.select_from_candidates(
		Transform3D.IDENTITY,
		_dogs(far_dog, near_dog),
		func(_dog: DogAgentRule) -> bool: return true,
	)

	check(selected == near_dog, "Distance must break ties between equal angular errors")
	far_dog.free()
	near_dog.free()


func test_rejects_candidates_without_line_of_sight() -> void:
	var selector := TargetSelectorRule.new()
	var blocked_front_dog := _make_dog(Vector3.FORWARD * 5.0)
	var clear_side_dog := _make_dog(_direction_at_degrees(20.0) * 10.0)

	var selected: DogAgentRule = selector.select_from_candidates(
		Transform3D.IDENTITY,
		_dogs(blocked_front_dog, clear_side_dog),
		func(dog: DogAgentRule) -> bool: return dog == clear_side_dog,
	)

	check(selected == clear_side_dog, "A blocked dog must be excluded before ranking")
	blocked_front_dog.free()
	clear_side_dog.free()


func test_lock_emits_only_on_identity_change_and_clears_on_capture() -> void:
	var selector := TargetSelectorRule.new()
	var dog: DogAgentRule = DogScene.instantiate() as DogAgentRule
	dog.position = Vector3.FORWARD * 5.0
	add_child(dog)
	dog.capture_effect_duration = 10.0
	var changed_targets: Array[DogAgentRule] = []
	selector.target_changed.connect(func(target: DogAgentRule) -> void: changed_targets.append(target))

	selector.select_from_candidates(Transform3D.IDENTITY, _one_dog(dog), func(_dog: DogAgentRule) -> bool: return true)
	selector.select_from_candidates(Transform3D.IDENTITY, _one_dog(dog), func(_dog: DogAgentRule) -> bool: return true)
	dog.capture()

	check(changed_targets.size() == 2, "The lock must emit once for acquisition and once for capture clearing")
	if changed_targets.size() == 2:
		check(changed_targets[0] == dog and changed_targets[1] == null, "Capture must clear the acquired identity")
	check(selector.current_target() == null, "A captured dog must not remain locked")
	dog.free()


func test_lock_clears_safely_when_target_exits_or_is_freed() -> void:
	var selector := TargetSelectorRule.new()
	var dog := _make_dog(Vector3.FORWARD * 5.0)
	add_child(dog)
	var changed_count := [0]
	selector.target_changed.connect(func(_target: DogAgentRule) -> void: changed_count[0] += 1)
	selector.select_from_candidates(Transform3D.IDENTITY, _one_dog(dog), func(_candidate: DogAgentRule) -> bool: return true)

	dog.free()

	check(selector.current_target() == null, "A freed target must resolve through its weak lock without an invalid access")
	check(changed_count[0] == 2, "Tree exit must clear the target identity exactly once")


func test_lock_clears_when_target_leaves_selection_constraints() -> void:
	var selector := TargetSelectorRule.new()
	var dog := _make_dog(Vector3.FORWARD * 5.0)
	var changed_targets: Array[DogAgentRule] = []
	selector.target_changed.connect(func(target: DogAgentRule) -> void: changed_targets.append(target))
	selector.select_from_candidates(Transform3D.IDENTITY, _one_dog(dog), func(_candidate: DogAgentRule) -> bool: return true)
	dog.position = Vector3.FORWARD * 25.0

	var selected: DogAgentRule = selector.select_from_candidates(
		Transform3D.IDENTITY,
		_one_dog(dog),
		func(_candidate: DogAgentRule) -> bool: return true,
	)

	check(selected == null and selector.current_target() == null, "A target outside the range must clear the lock")
	check(changed_targets.size() == 2 and changed_targets[1] == null, "Leaving constraints must emit one clear transition")
	dog.free()


func _make_dog(at_position: Vector3) -> DogAgentRule:
	var dog := DogAgentRule.new()
	dog.position = at_position
	return dog


func _dogs(first: DogAgentRule, second: DogAgentRule) -> Array[DogAgentRule]:
	return [first, second]


func _one_dog(dog: DogAgentRule) -> Array[DogAgentRule]:
	return [dog]


func _direction_at_degrees(degrees: float) -> Vector3:
	return Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(degrees))
