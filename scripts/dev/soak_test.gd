extends SceneTree


const DogAgentScene = preload("res://src/dogs/dog_agent.tscn")
const GameSessionRule = preload("res://src/session/game_session.gd")
const GameplayScene = preload("res://src/session/gameplay.tscn")
const GuardAgentScene = preload("res://src/guards/guard_agent.tscn")
const GuardAgentRule = preload("res://src/guards/guard_agent.gd")
const GuardDirectorRule = preload("res://src/guards/guard_director.gd")
const NetProjectileRule = preload("res://src/capture/net_projectile.gd")
const SessionRulesRule = preload("res://src/session/session_rules.gd")
const SpawnDirectorRule = preload("res://src/dogs/spawn_director.gd")
const SpawnPointRule = preload("res://src/dogs/spawn_point.gd")

const SESSION_RESTARTS := 50
const SPAWN_ATTEMPTS := 2000
const NET_EVENTS := 500
const GUARD_LIFECYCLES := 100


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var failures := PackedStringArray()
	var baseline_nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var baseline_orphans := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var peak_nodes := baseline_nodes

	var gameplay := GameplayScene.instantiate()
	root.add_child(gameplay)
	await process_frame
	for restart in SESSION_RESTARTS:
		gameplay.reset_session()
		if gameplay.session == null or gameplay.gameplay_frozen:
			failures.append("Session restart %d did not restore a running session." % restart)
		peak_nodes = maxi(peak_nodes, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
	await process_frame
	gameplay.free()
	await process_frame

	var spawn_director := SpawnDirectorRule.new()
	var spawn_player := Node3D.new()
	var spawn_camera := Camera3D.new()
	var first_marker := SpawnPointRule.new()
	var second_marker := SpawnPointRule.new()
	spawn_player.position = Vector3.ZERO
	first_marker.position = Vector3(30.0, 0.0, 0.0)
	second_marker.position = Vector3(34.0, 0.0, 0.0)
	spawn_director.player = spawn_player
	spawn_director.camera = spawn_camera
	spawn_director.set_population_active(false)
	spawn_director.set_test_markers([first_marker, second_marker])
	spawn_director.set_test_roll_source(func() -> float: return 0.5)
	spawn_director.add_child(spawn_player)
	spawn_director.add_child(spawn_camera)
	spawn_director.add_child(first_marker)
	spawn_director.add_child(second_marker)
	root.add_child(spawn_director)
	for cycle in SPAWN_ATTEMPTS / 2:
		var first_dog = spawn_director.request_dog_spawn()
		var second_dog = spawn_director.request_dog_spawn()
		if first_dog == null or second_dog == null:
			failures.append("Spawn cycle %d failed to create both validated dogs." % cycle)
			break
		if first_dog.position.distance_to(second_dog.position) <= spawn_director.spawn_clear_radius:
			failures.append("Spawn cycle %d placed two dogs inside the reserved radius." % cycle)
			break
		first_dog.free()
		second_dog.free()
		if spawn_director.active_dog_count() != 0:
			failures.append("Spawn cycle %d retained an invalid dog reference." % cycle)
			break
	spawn_director.free()

	for event in NET_EVENTS:
		var dog = DogAgentScene.instantiate()
		dog.capture_effect_duration = 0.0
		root.add_child(dog)
		var projectile := NetProjectileRule.new()
		root.add_child(projectile)
		var capture_count := [0]
		projectile.capture_confirmed.connect(
			func(_stats) -> void: capture_count[0] += 1,
		)
		projectile.launch(Vector3.ZERO, Vector3.FORWARD * 10.0, Vector3.ZERO)
		projectile.simulate_hit(dog)
		projectile.simulate_hit(dog)
		if not projectile.resolved or capture_count[0] != 1:
			failures.append("Net event %d did not resolve exactly one capture." % event)
			break
		if is_instance_valid(projectile):
			projectile.free()
		if is_instance_valid(dog):
			dog.free()

	for lifecycle in GUARD_LIFECYCLES:
		var guard_director := GuardDirectorRule.new()
		var first_zone := Marker3D.new()
		var second_zone := Marker3D.new()
		first_zone.position = Vector3(-10.0, 0.0, 0.0)
		second_zone.position = Vector3(10.0, 0.0, 0.0)
		guard_director.add_child(first_zone)
		guard_director.add_child(second_zone)
		guard_director.set_world_zones([first_zone, second_zone])
		guard_director.set_test_visibility_check(func(_node) -> bool: return false)
		guard_director.set_test_replacement_scheduler(
			func(_delay: float, callback: Callable) -> void: callback.call(),
		)
		guard_director.set_test_guard_factory(
			func(): return GuardAgentScene.instantiate(),
		)
		root.add_child(guard_director)
		var guard := GuardAgentScene.instantiate() as GuardAgentRule
		guard_director.add_child(guard)
		guard.ensure_initialized()
		guard_director.register_guard(guard)
		guard_director.assign_guard_zone(guard, first_zone)
		guard.state = GuardAgentRule.State.PURSUING
		guard.exhaust()
		guard_director.process_replacements()
		if guard.state != GuardAgentRule.State.RETIRED or guard_director.non_retired_guard_count() != 1:
			failures.append("Guard lifecycle %d did not retire and replace exactly once." % lifecycle)
			break
		guard_director.free()

	for session_index in SESSION_RESTARTS:
		var rules := SessionRulesRule.new()
		rules.score_goal = 100
		rules.duration_seconds = 1.0
		var session := GameSessionRule.new(rules)
		var terminal_count := [0]
		session.session_finished.connect(
			func(_won: bool, _reason: StringName) -> void: terminal_count[0] += 1,
		)
		if session_index % 2 == 0:
			session.add_capture(100)
			session.add_capture(100)
			session.finish_loss(GameSessionRule.LossReason.CAUGHT)
		else:
			session.finish_loss(GameSessionRule.LossReason.CAUGHT)
			session.finish_loss(GameSessionRule.LossReason.OUT_OF_FUEL)
			session.add_capture(100)
		if terminal_count[0] != 1:
			failures.append("Session %d emitted %d terminal events." % [session_index, terminal_count[0]])

	await process_frame
	await process_frame
	var final_nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var final_orphans := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	if final_nodes > baseline_nodes + 1:
		failures.append("Node count grew from %d to %d." % [baseline_nodes, final_nodes])
	if final_orphans > baseline_orphans:
		failures.append("Orphan count grew from %d to %d." % [baseline_orphans, final_orphans])

	print(
		"Soak counts: sessions=%d spawns=%d nets=%d guards=%d peak_nodes=%d"
		% [SESSION_RESTARTS, SPAWN_ATTEMPTS, NET_EVENTS, GUARD_LIFECYCLES, peak_nodes],
	)
	for failure in failures:
		printerr("FAIL: %s" % failure)
	if failures.is_empty():
		print("Soak test passed")
	quit(0 if failures.is_empty() else 1)
