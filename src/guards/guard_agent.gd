class_name GuardAgent
extends CharacterBody3D


const FuelModelRule = preload("res://src/vehicle/fuel_model.gd")
const GuardStatsRule = preload("res://src/guards/guard_stats.gd")
const PlayerVehicleRule = preload("res://src/vehicle/player_vehicle.gd")


signal pursuit_started(guard: GuardAgent)
signal pursuit_ended(guard: GuardAgent)
signal player_caught


enum State { IDLE, PURSUING, EXHAUSTED, RETIRED }


@export var stats: GuardStatsRule
@export var recovery_points: Array[Marker3D] = []
var state: State = State.IDLE
var fuel: FuelModelRule
var target: PlayerVehicleRule
var _detection_target: PlayerVehicleRule
var _navigation_refresh_elapsed := 0.0
var _forward_speed := 0.0
var _navigation_target_sink := Callable()
var _contact_emitted := false
var _recovery_reachability := Callable()
var _recovering := false
var _recovery_target := Vector3.ZERO
var _recovery_request_pending := false


func _ready() -> void:
	ensure_initialized()
	if recovery_points.is_empty():
		for child in get_children():
			var marker := child as Marker3D
			if marker != null and marker.name.begins_with("RecoveryPoint"):
				recovery_points.append(marker)
	var capture_area := _capture_area()
	if capture_area != null:
		var callback := Callable(self, "_on_capture_body_entered")
		if not capture_area.body_entered.is_connected(callback):
			capture_area.body_entered.connect(callback)
	_set_capture_enabled(false)


func _physics_process(delta: float) -> void:
	simulate_pursuit(delta)
	if state == State.PURSUING and is_inside_tree():
		move_and_slide()


func ensure_initialized() -> void:
	if stats == null:
		stats = GuardStatsRule.new()
	if fuel == null:
		fuel = FuelModelRule.new(
			stats.fuel_capacity,
			stats.idle_fuel_rate,
			stats.throttle_fuel_rate,
		)


func set_detection_target(player: PlayerVehicleRule) -> void:
	_detection_target = player


func on_detection(detection_position: Vector3, radius: float) -> void:
	if state != State.IDLE or radius < 0.0:
		return
	if _world_position().distance_to(detection_position) > radius:
		return
	begin_pursuit(_detection_target)


func begin_pursuit(player: PlayerVehicleRule) -> void:
	ensure_initialized()
	if state != State.IDLE or not _is_player_valid(player):
		return
	target = player
	_detection_target = player
	state = State.PURSUING
	_navigation_refresh_elapsed = 0.0
	_contact_emitted = false
	_forward_speed = 0.0
	_recovering = false
	_recovery_request_pending = false
	var exiting_callback := Callable(self, "_on_target_tree_exiting")
	if not target.tree_exiting.is_connected(exiting_callback):
		target.tree_exiting.connect(exiting_callback, CONNECT_ONE_SHOT)
	_set_capture_enabled(true)
	# Navigation maps synchronize after the node enters the tree; validate from later 4 Hz refreshes.
	refresh_navigation_target(false)
	pursuit_started.emit(self)


func simulate_pursuit(delta: float) -> void:
	if state != State.PURSUING:
		return
	if not _is_player_valid(target):
		_end_pursuit_to_idle()
		return
	ensure_initialized()
	var safe_delta := maxf(delta, 0.0)
	fuel.consume(safe_delta, 1.0)
	if is_zero_approx(fuel.amount):
		exhaust()
		return
	var refresh_interval := _path_refresh_interval()
	_navigation_refresh_elapsed += safe_delta
	while _navigation_refresh_elapsed + 0.000001 >= refresh_interval:
		_navigation_refresh_elapsed -= refresh_interval
		if not _recovering:
			refresh_navigation_target()
	_update_propulsion(safe_delta)


func predicted_intercept_position() -> Vector3:
	if not _is_player_valid(target):
		return _world_position()
	var player_position := target.global_position
	var horizontal_velocity := target.velocity
	horizontal_velocity.y = 0.0
	var travel_time := _world_position().distance_to(player_position) / maxf(stats.max_speed_mps, 0.001)
	travel_time = clampf(travel_time, 0.0, maxf(stats.max_prediction_seconds, 0.0))
	var lead := horizontal_velocity * travel_time
	var maximum_lead := maxf(stats.max_prediction_distance, 0.0)
	if lead.length() > maximum_lead:
		lead = lead.normalized() * maximum_lead
	return player_position + lead


func refresh_navigation_target(validate_route: bool = true) -> void:
	if state != State.PURSUING or not _is_player_valid(target):
		return
	var intercept := predicted_intercept_position()
	if validate_route:
		var route_status: Variant = _route_status(intercept)
		if route_status is bool and not bool(route_status):
			recover_or_abandon_navigation()
			return
	_recovering = false
	_recovery_request_pending = false
	_set_navigation_target(intercept)


func set_test_navigation_target_sink(sink: Callable) -> void:
	_navigation_target_sink = sink


func set_test_recovery_reachability(check_reachability: Callable) -> void:
	_recovery_reachability = check_reachability


func recover_or_abandon_navigation() -> void:
	if state != State.PURSUING:
		return
	var nearest_point: Marker3D
	var nearest_distance := INF
	for point in recovery_points:
		if not is_instance_valid(point) or point.is_queued_for_deletion():
			continue
		var point_position := point.global_position if point.is_inside_tree() else point.position
		if not _is_recovery_reachable(point_position):
			continue
		var distance := _world_position().distance_squared_to(point_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_point = point
	if nearest_point == null:
		handle_navigation_failure()
		return
	var recovery_position := nearest_point.global_position if nearest_point.is_inside_tree() else nearest_point.position
	handle_navigation_failure(recovery_position)


func handle_navigation_failure(recovery_point: Variant = null) -> void:
	if state != State.PURSUING:
		return
	if recovery_point is Vector3 and (recovery_point as Vector3).is_finite():
		_recovering = true
		_recovery_target = recovery_point as Vector3
		_recovery_request_pending = true
		_set_navigation_target(recovery_point as Vector3)
		return
	_end_pursuit_to_idle()


func simulate_player_contact(body: Node) -> void:
	if (
		state != State.PURSUING
		or _contact_emitted
		or not _is_player_valid(target)
		or body != target
	):
		return
	_contact_emitted = true
	player_caught.emit()


func exhaust() -> void:
	if state != State.PURSUING:
		return
	ensure_initialized()
	fuel.amount = 0.0
	state = State.EXHAUSTED
	_clear_target()
	_stop_propulsion()
	_set_capture_enabled(false)
	pursuit_ended.emit(self)


func retire() -> void:
	if state == State.RETIRED:
		return
	var was_pursuing := state == State.PURSUING
	state = State.RETIRED
	if was_pursuing:
		_clear_target()
		pursuit_ended.emit(self)
	else:
		_clear_target()
	_detection_target = null
	_recovering = false
	_recovery_request_pending = false
	recovery_points.clear()
	_stop_propulsion()
	_set_capture_enabled(false)
	collision_layer = 0
	collision_mask = 0
	var body_shape := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if body_shape != null:
		body_shape.disabled = true
	var visual := get_node_or_null("Visual") as GeometryInstance3D
	if visual != null:
		visual.visible = false
	var navigation := _navigation_agent()
	if navigation != null:
		navigation.avoidance_enabled = false
		navigation.process_mode = Node.PROCESS_MODE_DISABLED
	set_physics_process(false)


func _update_propulsion(delta: float) -> void:
	var navigation := _navigation_agent()
	if navigation == null:
		_stop_propulsion()
		return
	if _recovery_request_pending:
		_recovery_request_pending = false
		_stop_propulsion()
		return
	if navigation.is_navigation_finished():
		if _recovering and _world_position().distance_to(_recovery_target) <= maxf(
			navigation.target_desired_distance,
			0.5,
		):
			_recovering = false
			refresh_navigation_target(false)
		_stop_propulsion()
		return
	var direction := navigation.get_next_path_position() - _world_position()
	direction.y = 0.0
	if direction.is_zero_approx():
		_stop_propulsion()
		return
	direction = direction.normalized()
	_forward_speed = move_toward(
		_forward_speed,
		stats.max_speed_mps,
		stats.acceleration_mps2 * delta,
	)
	velocity = direction * _forward_speed
	if is_inside_tree():
		look_at(global_position + direction, Vector3.UP)


func _set_navigation_target(target_position: Vector3) -> void:
	if _navigation_target_sink.is_valid():
		_navigation_target_sink.call(target_position)
		return
	var navigation := _navigation_agent()
	if navigation != null:
		navigation.target_position = target_position


func _path_refresh_interval() -> float:
	return 1.0 / maxf(stats.path_refresh_hz, 0.001)


func _end_pursuit_to_idle() -> void:
	if state != State.PURSUING:
		return
	state = State.IDLE
	_recovering = false
	_recovery_request_pending = false
	_clear_target()
	_stop_propulsion()
	_set_capture_enabled(false)
	pursuit_ended.emit(self)


func _clear_target() -> void:
	if is_instance_valid(target):
		var exiting_callback := Callable(self, "_on_target_tree_exiting")
		if target.tree_exiting.is_connected(exiting_callback):
			target.tree_exiting.disconnect(exiting_callback)
	target = null


func _stop_propulsion() -> void:
	_forward_speed = 0.0
	velocity = Vector3.ZERO
	var navigation := _navigation_agent()
	if navigation != null:
		navigation.velocity = Vector3.ZERO


func _set_capture_enabled(enabled: bool) -> void:
	var capture_area := _capture_area()
	if capture_area == null:
		return
	capture_area.monitoring = enabled
	capture_area.monitorable = enabled
	capture_area.collision_layer = 4 if enabled else 0
	capture_area.collision_mask = 1 if enabled else 0
	var shape := capture_area.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape != null:
		shape.disabled = not enabled


func _is_player_valid(player: PlayerVehicleRule) -> bool:
	return (
		is_instance_valid(player)
		and player.is_inside_tree()
		and not player.is_queued_for_deletion()
	)


func _is_recovery_reachable(point_position: Vector3) -> bool:
	var status: Variant = _route_status(point_position)
	return status is bool and bool(status)


func _route_status(target_position: Vector3) -> Variant:
	if _recovery_reachability.is_valid():
		return bool(_recovery_reachability.call(target_position))
	var navigation := _navigation_agent()
	if navigation == null:
		return null
	var route_tolerance := maxf(navigation.path_desired_distance, 0.5)
	if _world_position().distance_to(target_position) <= route_tolerance:
		return true
	var navigation_map := navigation.get_navigation_map()
	if not navigation_map.is_valid():
		return null
	if NavigationServer3D.map_get_iteration_id(navigation_map) == 0:
		return null
	if NavigationServer3D.map_get_regions(navigation_map).is_empty():
		return null
	var parameters := NavigationPathQueryParameters3D.new()
	parameters.map = navigation_map
	parameters.start_position = _world_position()
	parameters.target_position = target_position
	parameters.navigation_layers = navigation.navigation_layers
	var result := NavigationPathQueryResult3D.new()
	NavigationServer3D.query_path(parameters, result)
	var route := result.path
	return (
		not route.is_empty()
		and route[0].distance_to(_world_position()) <= route_tolerance
		and route[route.size() - 1].distance_to(target_position) <= route_tolerance
	)


func _navigation_agent() -> NavigationAgent3D:
	return get_node_or_null("NavigationAgent3D") as NavigationAgent3D


func _capture_area() -> Area3D:
	return get_node_or_null("CaptureArea") as Area3D


func _world_position() -> Vector3:
	return global_position if is_inside_tree() else position


func _on_target_tree_exiting() -> void:
	_end_pursuit_to_idle()


func _on_capture_body_entered(body: Node3D) -> void:
	simulate_player_contact(body)
