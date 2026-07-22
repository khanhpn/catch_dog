class_name NetProjectile
extends Area3D


const DogStatsRule = preload("res://src/dogs/dog_stats.gd")
const DogAgentRule = preload("res://src/dogs/dog_agent.gd")


signal capture_confirmed(stats: DogStatsRule)


const MAX_RANGE_METERS := 30.0
const DEFAULT_MAX_LIFETIME_SECONDS := 2.0


@export var speed := 30.0
@export var max_lifetime := DEFAULT_MAX_LIFETIME_SECONDS
var resolved := false
var target_position_snapshot := Vector3.ZERO
var target_velocity_snapshot := Vector3.ZERO
var initial_velocity := Vector3.ZERO
var _distance_travelled := 0.0
var _elapsed := 0.0
var _source_body_ref: WeakRef


func _init() -> void:
	collision_layer = 0
	collision_mask = DogAgentRule.COLLISION_LAYER


func _ready() -> void:
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	simulate_step(delta)


func launch(
	origin: Vector3,
	target_position: Vector3,
	target_velocity: Vector3,
	source_body: CollisionObject3D = null,
) -> void:
	resolved = false
	_distance_travelled = 0.0
	_elapsed = 0.0
	target_position_snapshot = target_position
	target_velocity_snapshot = target_velocity
	_set_source_body(source_body)
	var travel_time := origin.distance_to(target_position) / speed if speed > 0.0 else 0.0
	var predicted_target := target_position + target_velocity * travel_time
	var direction := origin.direction_to(predicted_target)
	if direction.is_zero_approx():
		direction = Vector3.FORWARD
	initial_velocity = direction * maxf(speed, 0.0)
	if is_inside_tree():
		top_level = true
		global_position = origin
	else:
		position = origin
	set_physics_process(true)


func simulate_hit(body: Node) -> void:
	if _is_source_body(body):
		return
	var dog := body as DogAgentRule
	if dog == null or not dog.is_capture_target_valid():
		return
	if not _resolve_once():
		return
	var captured_stats: DogStatsRule = dog.stats
	if dog.capture():
		capture_confirmed.emit(captured_stats)


func simulate_miss() -> void:
	_resolve_once()


func simulate_step(delta: float) -> void:
	if resolved or delta <= 0.0:
		return
	var displacement := initial_velocity * delta
	if is_inside_tree():
		global_position += displacement
	else:
		position += displacement
	_distance_travelled += displacement.length()
	_elapsed += delta
	if _distance_travelled + 0.0001 >= MAX_RANGE_METERS or _elapsed + 0.000001 >= max_lifetime:
		simulate_miss()


func _resolve_once() -> bool:
	if resolved:
		return false
	resolved = true
	set_physics_process(false)
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	collision_layer = 0
	collision_mask = 0
	if is_inside_tree():
		queue_free()
	return true


func _on_body_entered(body: Node3D) -> void:
	simulate_hit(body)


func _set_source_body(source_body: CollisionObject3D) -> void:
	_source_body_ref = null
	if is_instance_valid(source_body):
		_source_body_ref = weakref(source_body)


func _is_source_body(body: Node) -> bool:
	if _source_body_ref == null:
		return false
	return _source_body_ref.get_ref() == body
