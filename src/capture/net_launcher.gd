class_name NetLauncher
extends Node3D


const DogAgentRule = preload("res://src/dogs/dog_agent.gd")
const DogStatsRule = preload("res://src/dogs/dog_stats.gd")
const NetProjectileRule = preload("res://src/capture/net_projectile.gd")
const NetProjectileScene = preload("res://src/capture/net_projectile.tscn")
const TargetSelectorRule = preload("res://src/capture/target_selector.gd")


signal target_changed(target: DogAgentRule)
signal net_thrown(origin: Vector3, detection_radius: float)
signal capture_confirmed(stats: DogStatsRule)


const COOLDOWN_SECONDS := 0.8


@export var detection_radius := 12.0
@export var projectile_scene: PackedScene = NetProjectileScene
@export var projectile_parent: Node
var _selector := TargetSelectorRule.new()
var _cooldown_elapsed := COOLDOWN_SECONDS
var _projectile_factory := Callable()


func _init() -> void:
	_selector.target_changed.connect(_on_target_changed)


func _process(delta: float) -> void:
	advance_cooldown(delta)


func update_target(
	origin: Transform3D,
	dogs: Array[DogAgentRule],
	space: PhysicsDirectSpaceState3D,
) -> DogAgentRule:
	return _selector.select(origin, dogs, space)


func update_target_from_candidates(
	origin: Transform3D,
	dogs: Array[DogAgentRule],
	has_line_of_sight: Callable = Callable(),
) -> DogAgentRule:
	return _selector.select_from_candidates(origin, dogs, has_line_of_sight)


func try_throw() -> bool:
	if _cooldown_elapsed < COOLDOWN_SECONDS:
		return false
	var target: DogAgentRule = _selector.current_target()
	if target == null:
		return false
	var projectile := _create_projectile()
	if projectile == null:
		return false
	var parent := projectile_parent if is_instance_valid(projectile_parent) else self
	parent.add_child(projectile)
	var origin := global_position if is_inside_tree() else position
	var target_position := target.global_position if target.is_inside_tree() else target.position
	projectile.capture_confirmed.connect(_on_projectile_capture_confirmed)
	projectile.launch(origin, target_position, target.velocity)
	_cooldown_elapsed = 0.0
	net_thrown.emit(origin, detection_radius)
	return true


func advance_cooldown(delta: float) -> void:
	_cooldown_elapsed = minf(
		_cooldown_elapsed + maxf(delta, 0.0),
		COOLDOWN_SECONDS,
	)


func set_projectile_factory_for_test(factory: Callable) -> void:
	_projectile_factory = factory


func _create_projectile() -> NetProjectileRule:
	var created: Variant
	if _projectile_factory.is_valid():
		created = _projectile_factory.call()
	elif projectile_scene != null:
		created = projectile_scene.instantiate()
	var projectile := created as NetProjectileRule
	if projectile == null and created is Node:
		(created as Node).free()
	return projectile


func _on_target_changed(target: DogAgentRule) -> void:
	target_changed.emit(target)


func _on_projectile_capture_confirmed(stats: DogStatsRule) -> void:
	capture_confirmed.emit(stats)
