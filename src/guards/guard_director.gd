class_name GuardDirector
extends Node3D


const GuardAgentRule = preload("res://src/guards/guard_agent.gd")
const NetLauncherRule = preload("res://src/capture/net_launcher.gd")
const PlayerVehicleRule = preload("res://src/vehicle/player_vehicle.gd")


signal pursuit_started(guard: GuardAgentRule)
signal pursuit_ended(guard: GuardAgentRule)
signal player_caught
signal threat_directions_changed(directions: Array[Vector3])


const MAX_NON_RETIRED_GUARDS := 3
const REPLACEMENT_DELAY_SECONDS := 20.0


@export var player: PlayerVehicleRule
@export var launcher: NetLauncherRule
@export var camera: Camera3D
var _guards: Array[GuardAgentRule] = []
var _guard_zones: Dictionary = {}
var _replacement_waiting: Array[GuardAgentRule] = []
var _replacement_eligible: Array[GuardAgentRule] = []
var _replacement_timer_pending := false
var _replacement_timer: SceneTreeTimer
var _bound_launcher: NetLauncherRule
var _replacement_scheduler := Callable()
var _visibility_check := Callable()
var _guard_factory := Callable()


func _ready() -> void:
	if launcher != null:
		bind_launcher(launcher)
	for child in get_children():
		var guard := child as GuardAgentRule
		if guard != null:
			register_guard(guard)


func _process(_delta: float) -> void:
	if not _replacement_eligible.is_empty():
		process_replacements()


func _exit_tree() -> void:
	_release_replacement_timer()


func bind_launcher(net_launcher: NetLauncherRule) -> void:
	var callback := Callable(self, "_on_net_thrown")
	if is_instance_valid(_bound_launcher) and _bound_launcher.net_thrown.is_connected(callback):
		_bound_launcher.net_thrown.disconnect(callback)
	_bound_launcher = net_launcher
	if is_instance_valid(_bound_launcher) and not _bound_launcher.net_thrown.is_connected(callback):
		_bound_launcher.net_thrown.connect(callback)


func set_test_guards(guards: Array[GuardAgentRule]) -> void:
	for guard in _guards.duplicate():
		_disconnect_guard(guard)
	_guards.clear()
	_guard_zones.clear()
	_replacement_waiting.clear()
	_replacement_eligible.clear()
	_replacement_timer_pending = false
	_release_replacement_timer()
	for guard in guards:
		register_guard(guard)


func register_guard(guard: GuardAgentRule) -> bool:
	_prune_guards()
	if not is_instance_valid(guard) or guard.state == GuardAgentRule.State.RETIRED:
		return false
	if _guards.has(guard):
		return true
	if non_retired_guard_count() >= MAX_NON_RETIRED_GUARDS:
		return false
	_guards.append(guard)
	guard.set_detection_target(player)
	var started_callback := Callable(self, "_on_guard_pursuit_started")
	var ended_callback := Callable(self, "_on_guard_pursuit_ended")
	var caught_callback := Callable(self, "_on_guard_player_caught").bind(guard)
	var exiting_callback := Callable(self, "_on_guard_tree_exiting").bind(guard)
	if not guard.pursuit_started.is_connected(started_callback):
		guard.pursuit_started.connect(started_callback)
	if not guard.pursuit_ended.is_connected(ended_callback):
		guard.pursuit_ended.connect(ended_callback)
	if not guard.player_caught.is_connected(caught_callback):
		guard.player_caught.connect(caught_callback)
	if not guard.tree_exiting.is_connected(exiting_callback):
		guard.tree_exiting.connect(exiting_callback, CONNECT_ONE_SHOT)
	return true


func non_retired_guard_count() -> int:
	_prune_guards()
	var count := 0
	for guard in _guards:
		if guard.state != GuardAgentRule.State.RETIRED:
			count += 1
	return count


func threat_directions() -> Array[Vector3]:
	var directions: Array[Vector3] = []
	if not _is_player_valid():
		return directions
	_prune_guards()
	for guard in _guards:
		if guard.state != GuardAgentRule.State.PURSUING or guard.target != player:
			continue
		var direction := guard.global_position - player.global_position
		direction.y = 0.0
		if not direction.is_zero_approx():
			directions.append(direction.normalized())
	return directions


func zone_markers() -> Array[Marker3D]:
	var zones: Array[Marker3D] = []
	for child in get_children():
		var marker := child as Marker3D
		if marker != null:
			zones.append(marker)
	return zones


func assign_guard_zone(guard: GuardAgentRule, zone: Marker3D) -> void:
	if is_instance_valid(guard) and is_instance_valid(zone):
		_guard_zones[guard.get_instance_id()] = zone


func set_test_replacement_scheduler(scheduler: Callable) -> void:
	_replacement_scheduler = scheduler


func set_test_visibility_check(check_visibility: Callable) -> void:
	_visibility_check = check_visibility


func set_test_guard_factory(factory: Callable) -> void:
	_guard_factory = factory


func process_replacements() -> void:
	for exhausted_guard in _replacement_eligible.duplicate():
		if not is_instance_valid(exhausted_guard) or exhausted_guard.state != GuardAgentRule.State.EXHAUSTED:
			_replacement_eligible.erase(exhausted_guard)
			continue
		if _is_in_view(exhausted_guard):
			continue
		var zone := _replacement_zone_for(exhausted_guard)
		if zone == null:
			continue
		exhausted_guard.retire()
		var replacement := _create_guard()
		if replacement == null:
			_replacement_eligible.erase(exhausted_guard)
			continue
		if not replacement.is_inside_tree():
			add_child(replacement)
		replacement.global_position = zone.global_position
		if not register_guard(replacement):
			replacement.queue_free()
			_replacement_eligible.erase(exhausted_guard)
			continue
		assign_guard_zone(replacement, zone)
		_replacement_eligible.erase(exhausted_guard)
	_emit_threat_directions()


func _on_net_thrown(origin: Vector3, detection_radius: float) -> void:
	_prune_guards()
	for guard in _guards:
		guard.set_detection_target(player)
		guard.on_detection(origin, detection_radius)


func _on_guard_pursuit_started(guard: GuardAgentRule) -> void:
	pursuit_started.emit(guard)
	_emit_threat_directions()


func _on_guard_pursuit_ended(guard: GuardAgentRule) -> void:
	pursuit_ended.emit(guard)
	if guard.state == GuardAgentRule.State.EXHAUSTED:
		_schedule_replacement(guard)
	_emit_threat_directions()


func _on_guard_player_caught(guard: GuardAgentRule) -> void:
	if guard.state == GuardAgentRule.State.PURSUING and guard.target == player:
		player_caught.emit()


func _on_guard_tree_exiting(guard: GuardAgentRule) -> void:
	_guards.erase(guard)
	_replacement_waiting.erase(guard)
	_replacement_eligible.erase(guard)
	_guard_zones.erase(guard.get_instance_id())
	_emit_threat_directions()


func _schedule_replacement(guard: GuardAgentRule) -> void:
	if _replacement_waiting.has(guard) or _replacement_eligible.has(guard):
		return
	_replacement_waiting.append(guard)
	if _replacement_timer_pending:
		return
	_replacement_timer_pending = true
	var timeout_callback := Callable(self, "_on_replacement_delay_elapsed")
	if _replacement_scheduler.is_valid():
		_replacement_scheduler.call(REPLACEMENT_DELAY_SECONDS, timeout_callback)
		return
	if not is_inside_tree():
		return
	_replacement_timer = get_tree().create_timer(REPLACEMENT_DELAY_SECONDS)
	_replacement_timer.timeout.connect(timeout_callback, CONNECT_ONE_SHOT)


func _on_replacement_delay_elapsed() -> void:
	_replacement_timer_pending = false
	_release_replacement_timer()
	for guard in _replacement_waiting:
		if is_instance_valid(guard) and not _replacement_eligible.has(guard):
			_replacement_eligible.append(guard)
	_replacement_waiting.clear()
	process_replacements()


func _replacement_zone_for(exhausted_guard: GuardAgentRule) -> Marker3D:
	var previous_zone := _guard_zones.get(exhausted_guard.get_instance_id()) as Marker3D
	for zone in zone_markers():
		if zone != previous_zone and not _is_in_view(zone):
			return zone
	return null


func _create_guard() -> GuardAgentRule:
	var created: Variant
	if _guard_factory.is_valid():
		created = _guard_factory.call()
	else:
		created = preload("res://src/guards/guard_agent.tscn").instantiate()
	return created as GuardAgentRule


func _is_in_view(node: Node3D) -> bool:
	if _visibility_check.is_valid():
		return bool(_visibility_check.call(node))
	var active_camera := camera
	if active_camera == null and is_inside_tree():
		active_camera = get_viewport().get_camera_3d()
	return active_camera == null or active_camera.is_position_in_frustum(node.global_position)


func _is_player_valid() -> bool:
	return is_instance_valid(player) and player.is_inside_tree() and not player.is_queued_for_deletion()


func _emit_threat_directions() -> void:
	threat_directions_changed.emit(threat_directions())


func _prune_guards() -> void:
	for guard in _guards.duplicate():
		if not is_instance_valid(guard) or guard.is_queued_for_deletion():
			_guards.erase(guard)


func _disconnect_guard(guard: GuardAgentRule) -> void:
	if not is_instance_valid(guard):
		return
	var started_callback := Callable(self, "_on_guard_pursuit_started")
	var ended_callback := Callable(self, "_on_guard_pursuit_ended")
	var caught_callback := Callable(self, "_on_guard_player_caught").bind(guard)
	var exiting_callback := Callable(self, "_on_guard_tree_exiting").bind(guard)
	if guard.pursuit_started.is_connected(started_callback):
		guard.pursuit_started.disconnect(started_callback)
	if guard.pursuit_ended.is_connected(ended_callback):
		guard.pursuit_ended.disconnect(ended_callback)
	if guard.player_caught.is_connected(caught_callback):
		guard.player_caught.disconnect(caught_callback)
	if guard.tree_exiting.is_connected(exiting_callback):
		guard.tree_exiting.disconnect(exiting_callback)


func _release_replacement_timer() -> void:
	var callback := Callable(self, "_on_replacement_delay_elapsed")
	if is_instance_valid(_replacement_timer) and _replacement_timer.timeout.is_connected(callback):
		_replacement_timer.timeout.disconnect(callback)
	_replacement_timer = null
