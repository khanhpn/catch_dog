extends SceneTree


const DogCatalogRule = preload("res://src/dogs/dog_catalog.gd")
const GameSessionRule = preload("res://src/session/game_session.gd")
const GameplayScene = preload("res://src/session/gameplay.tscn")
const GuardAgentRule = preload("res://src/guards/guard_agent.gd")
const NetProjectileRule = preload("res://src/capture/net_projectile.gd")
const SessionRulesRule = preload("res://src/session/session_rules.gd")
const WeightedPickerRule = preload("res://src/dogs/weighted_picker.gd")

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

	var catalog := DogCatalogRule.new()
	var weights := PackedFloat32Array()
	for entry in catalog.entries:
		weights.append(entry.weight)
	for attempt in SPAWN_ATTEMPTS:
		var roll := float((attempt * 7919) % SPAWN_ATTEMPTS) / float(SPAWN_ATTEMPTS)
		var picked := WeightedPickerRule.pick_index(weights, roll)
		if picked < 0 or picked >= catalog.entries.size():
			failures.append("Weighted spawn attempt %d returned an invalid index." % attempt)
			break

	for event in NET_EVENTS:
		var projectile := NetProjectileRule.new()
		projectile.launch(Vector3.ZERO, Vector3.FORWARD * 10.0, Vector3.ZERO)
		projectile.simulate_miss()
		projectile.simulate_miss()
		if not projectile.resolved:
			failures.append("Net event %d did not reach one terminal state." % event)
			projectile.free()
			break
		projectile.free()

	for lifecycle in GUARD_LIFECYCLES:
		var guard := GuardAgentRule.new()
		guard.ensure_initialized()
		guard.state = GuardAgentRule.State.PURSUING
		guard.exhaust()
		if guard.state != GuardAgentRule.State.EXHAUSTED or not is_zero_approx(guard.fuel.amount):
			failures.append("Guard lifecycle %d did not exhaust cleanly." % lifecycle)
			guard.free()
			break
		guard.retire()
		guard.free()

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
