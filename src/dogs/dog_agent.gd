class_name DogAgent
extends CharacterBody3D


const DogStatsRule = preload("res://src/dogs/dog_stats.gd")


signal captured(stats: DogStatsRule)


enum State {
	IDLE,
	FLEEING,
	CAPTURED,
}


@export var stats: DogStatsRule = DogStatsRule.new()
@export var base_run_speed := 5.0
@export var flee_distance := 12.0
@export var lateral_variation := 3.0
@export var capture_effect_duration := 0.2
var state: State = State.IDLE
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


func begin_flee(threat_position: Vector3) -> void:
	if state == State.CAPTURED:
		return
	state = State.FLEEING
	var current_position := _world_position()
	var away := current_position - threat_position
	away.y = 0.0
	if away.is_zero_approx():
		away = Vector3.FORWARD
	else:
		away = away.normalized()
	var lateral := Vector3(-away.z, 0.0, away.x)
	var lateral_offset := _rng.randf_range(-lateral_variation, lateral_variation)
	_navigation_agent().target_position = (
		current_position
		+ away * flee_distance
		+ lateral * lateral_offset
	)


func capture() -> bool:
	if state == State.CAPTURED:
		return false
	state = State.CAPTURED
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	var collision_shape := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape != null:
		collision_shape.set_deferred("disabled", true)
	var navigation_agent := _navigation_agent()
	navigation_agent.avoidance_enabled = false
	navigation_agent.process_mode = Node.PROCESS_MODE_DISABLED
	captured.emit(stats)
	_play_capture_feedback()
	return true


func _physics_process(_delta: float) -> void:
	if state != State.FLEEING or not is_inside_tree():
		return
	var navigation_agent := _navigation_agent()
	if navigation_agent.is_navigation_finished():
		velocity = Vector3.ZERO
		return
	var direction := navigation_agent.get_next_path_position() - global_position
	direction.y = 0.0
	if direction.is_zero_approx():
		velocity = Vector3.ZERO
		return
	direction = direction.normalized()
	velocity = direction * base_run_speed * stats.run_speed_multiplier
	look_at(global_position + direction, Vector3.UP)
	move_and_slide()


func _navigation_agent() -> NavigationAgent3D:
	return get_node("NavigationAgent3D") as NavigationAgent3D


func _world_position() -> Vector3:
	return global_position if is_inside_tree() else position


func _play_capture_feedback() -> void:
	if not is_inside_tree():
		return
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ZERO, capture_effect_duration)
	tween.tween_callback(queue_free)
