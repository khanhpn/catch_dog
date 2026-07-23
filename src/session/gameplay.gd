class_name Gameplay
extends Node3D


signal main_menu_requested


const DogAgentRule = preload("res://src/dogs/dog_agent.gd")
const DogStatsRule = preload("res://src/dogs/dog_stats.gd")
const GameSessionRule = preload("res://src/session/game_session.gd")
const GuardAgentRule = preload("res://src/guards/guard_agent.gd")
const GuardAgentScene = preload("res://src/guards/guard_agent.tscn")
const GuardDirectorRule = preload("res://src/guards/guard_director.gd")
const HudRule = preload("res://src/ui/hud.gd")
const LauncherRule = preload("res://src/capture/net_launcher.gd")
const NeighborhoodRule = preload("res://src/world/neighborhood.gd")
const ResultScreenRule = preload("res://src/ui/result_screen.gd")
const SessionResultRule = preload("res://src/session/session_result.gd")
const SessionRulesRule = preload("res://src/session/session_rules.gd")
const SpawnDirectorRule = preload("res://src/dogs/spawn_director.gd")
const FuelPickupRule = preload("res://src/vehicle/fuel_pickup.gd")
const CameraRigRule = preload("res://src/vehicle/camera_rig.gd")
const PauseMenuRule = preload("res://src/ui/pause_menu.gd")
const AudioDirectorRule = preload("res://src/audio/audio_director.gd")
const FuelPickupScene = preload("res://src/vehicle/fuel_pickup.tscn")
const PlayerVehicleRule = preload("res://src/vehicle/player_vehicle.gd")
const SESSION_DURATION_SECONDS := 180.0


var session: GameSessionRule
var result_open_count := 0
var gameplay_frozen := false
var last_result: SessionResultRule
var last_result_payload: Dictionary:
	get:
		return last_result.to_payload() if last_result != null else {}
var capture_count := 0
var _locked_dog: DogAgentRule


@onready var _runtime := $Runtime as Node3D
@onready var _player := $Runtime/Player as PlayerVehicleRule
@onready var _launcher := $Runtime/Player/NetLauncher as LauncherRule
@onready var _dog_director := $Runtime/DogSpawnDirector as SpawnDirectorRule
@onready var _pickup_director := $Runtime/PickupDirector as Node3D
@onready var _guard_director := $Runtime/GuardDirector as GuardDirectorRule
@onready var _hud := $HUD as HudRule
@onready var _result_screen := $ResultScreen as ResultScreenRule
@onready var _neighborhood := $Neighborhood as NeighborhoodRule
@onready var _pause_menu := $PauseMenu as PauseMenuRule
@onready var _audio_director := $AudioDirector as AudioDirectorRule


func _ready() -> void:
	_wire_owned_modules()
	_spawn_fuel_pickups()
	_spawn_authored_guards()
	_start_new_session()
	_connect_once(_pause_menu.pause_requested, func() -> void: set_paused(true))
	_connect_once(_pause_menu.resume_requested, func() -> void: set_paused(false))
	_connect_once(_pause_menu.restart_requested, _restart_from_pause)
	_connect_once(_pause_menu.main_menu_requested, _return_to_main_menu)


func _exit_tree() -> void:
	if get_tree() != null:
		get_tree().paused = false


func _physics_process(delta: float) -> void:
	if gameplay_frozen or session == null:
		return
	session.tick(delta)
	if session.state != GameSessionRule.State.RUNNING:
		return
	_launcher.update_target(
		_launcher.global_transform,
		_dog_director.active_dogs(),
		get_world_3d().direct_space_state,
	)
	_hud.update_target_state(_launcher.has_target(), _launcher.cooldown_ratio())
	_hud.update_threat_ring(_guard_director.threat_directions(), _player.global_basis)


func capture_for_test(points: int) -> void:
	if session == null or session.state != GameSessionRule.State.RUNNING:
		return
	capture_count += 1
	session.add_capture(points)


func simulate_timeout() -> StringName:
	if session != null:
		session.tick(session.seconds)
	return last_result_payload.get("reason", StringName()) as StringName


func simulate_guard_contact() -> StringName:
	if session != null:
		session.finish_loss(GameSessionRule.LossReason.CAUGHT)
	return last_result_payload.get("reason", StringName()) as StringName


func simulate_out_of_fuel() -> StringName:
	if session != null:
		session.finish_loss(GameSessionRule.LossReason.OUT_OF_FUEL)
	return last_result_payload.get("reason", StringName()) as StringName


func reset_for_test() -> void:
	reset_session()


func reset_session() -> void:
	_disconnect_session()
	_clear_dynamic_population()
	_restore_runtime_state()
	_spawn_fuel_pickups()
	_spawn_authored_guards()
	_start_new_session()


func set_paused(paused: bool) -> void:
	if get_tree().paused == paused:
		return
	get_tree().paused = paused
	if paused:
		_pause_menu.show_menu()
	else:
		_pause_menu.hide_menu()


func apply_motion_settings(camera_shake: float, reduced_motion: bool) -> void:
	(_player.get_node("CameraRig") as CameraRigRule).apply_motion_settings(
		camera_shake,
		reduced_motion,
	)


func _restart_from_pause() -> void:
	set_paused(false)
	reset_session()


func _return_to_main_menu() -> void:
	set_paused(false)
	main_menu_requested.emit()


func _wire_owned_modules() -> void:
	_dog_director.player = _player
	_dog_director.camera = _player.get_node("CameraRig/Camera3D") as Camera3D
	_launcher.projectile_parent = $Runtime/Projectiles
	_launcher.source_body = _player
	_guard_director.player = _player
	_guard_director.launcher = _launcher
	_guard_director.camera = _player.get_node("CameraRig/Camera3D") as Camera3D
	_guard_director.bind_launcher(_launcher)
	_audio_director.player = _player
	_audio_director.guard_director = _guard_director
	_connect_once(_launcher.capture_confirmed, _on_capture_confirmed)
	_connect_once(_launcher.target_changed, _on_target_changed)
	_connect_once(_player.fuel_changed, _on_player_fuel_changed)
	_connect_once(_player.stopped_without_fuel, _on_player_stopped_without_fuel)
	_connect_once(_guard_director.player_caught, _on_player_caught)
	_connect_once(_guard_director.threat_directions_changed, _on_threat_directions_changed)
	_connect_once(_result_screen.replay_requested, reset_session)


func _start_new_session() -> void:
	var rules := SessionRulesRule.new()
	rules.duration_seconds = SESSION_DURATION_SECONDS
	rules.score_goal = 100
	session = GameSessionRule.new(rules)
	session.score_changed.connect(_on_score_changed)
	session.time_changed.connect(_on_time_changed)
	session.session_finished.connect(_on_session_finished)
	capture_count = 0
	result_open_count = 0
	gameplay_frozen = false
	last_result = null
	_result_screen.clear()
	_set_runtime_enabled(true)
	_hud.update_score(0, session.score_goal)
	_hud.update_time(session.seconds)
	_hud.update_fuel(_player.fuel_percent())
	_hud.update_target_state(false, 1.0)
	_hud.update_chase(false, [])


func _disconnect_session() -> void:
	if session == null:
		return
	if session.score_changed.is_connected(_on_score_changed):
		session.score_changed.disconnect(_on_score_changed)
	if session.time_changed.is_connected(_on_time_changed):
		session.time_changed.disconnect(_on_time_changed)
	if session.session_finished.is_connected(_on_session_finished):
		session.session_finished.disconnect(_on_session_finished)


func _on_capture_confirmed(stats: DogStatsRule) -> void:
	if stats == null:
		return
	capture_for_test(stats.score)


func _on_target_changed(target: DogAgentRule) -> void:
	if is_instance_valid(_locked_dog) and _locked_dog != target:
		_locked_dog.stop_fleeing()
	_locked_dog = target
	if is_instance_valid(_locked_dog):
		_locked_dog.begin_flee(_player.global_position)


func _on_score_changed(score: int) -> void:
	_hud.update_score(score, session.score_goal)


func _on_time_changed(seconds: float) -> void:
	_hud.update_time(seconds)


func _on_player_fuel_changed(percent: float) -> void:
	_hud.update_fuel(percent)


func _on_player_stopped_without_fuel() -> void:
	if session != null:
		session.finish_loss(GameSessionRule.LossReason.OUT_OF_FUEL)


func _on_player_caught() -> void:
	if session != null:
		session.finish_loss(GameSessionRule.LossReason.CAUGHT)


func _on_threat_directions_changed(directions: Array[Vector3]) -> void:
	_hud.update_threat_ring(directions, _player.global_basis)


func _on_session_finished(won: bool, reason: StringName) -> void:
	if result_open_count > 0:
		return
	var result := SessionResultRule.new(
		won,
		reason,
		session.score,
		float(session.seconds),
		capture_count,
	)
	if not result.is_valid():
		push_error("Gameplay produced an invalid result payload")
		return
	last_result = result
	result_open_count = 1
	gameplay_frozen = true
	_set_runtime_enabled(false)
	_result_screen.present(result)


func _set_runtime_enabled(enabled: bool) -> void:
	_dog_director.set_population_active(enabled)
	var mode := Node.PROCESS_MODE_INHERIT if enabled else Node.PROCESS_MODE_DISABLED
	for child in _runtime.get_children():
		child.process_mode = mode


func _restore_runtime_state() -> void:
	_locked_dog = null
	_player.reset_runtime_state(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.1, 34.0)))
	_launcher.reset_runtime_state()
	(_player.get_node("CameraRig") as CameraRigRule).reset_runtime_state()


func _clear_dynamic_population() -> void:
	for container in [_dog_director, _pickup_director, _guard_director, $Runtime/Projectiles]:
		for child in container.get_children():
			if child is DogAgentRule or child is FuelPickupRule or child is GuardAgentRule or container == $Runtime/Projectiles:
				child.free()
	_guard_director.clear_guard_registry()


func _spawn_fuel_pickups() -> void:
	for marker in _neighborhood.fuel_markers():
		var pickup := FuelPickupScene.instantiate() as FuelPickupRule
		_pickup_director.add_child(pickup)
		pickup.global_position = marker.global_position


func _spawn_authored_guards() -> void:
	var recovery_points: Array[Marker3D] = []
	for recovery_marker in _neighborhood.recovery_markers():
		recovery_points.append(recovery_marker)
	var guard_zones: Array[Marker3D] = []
	for authored_zone in _neighborhood.guard_zones():
		guard_zones.append(authored_zone)
	_guard_director.set_world_zones(guard_zones)
	for zone in guard_zones:
		var guard := GuardAgentScene.instantiate() as GuardAgentRule
		guard.recovery_points = recovery_points
		_guard_director.add_child(guard)
		guard.global_position = zone.global_position
		if _guard_director.register_guard(guard):
			_guard_director.assign_guard_zone(guard, zone)


func _connect_once(source: Signal, callback: Callable) -> void:
	if not source.is_connected(callback):
		source.connect(callback)
