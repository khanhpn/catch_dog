extends "res://tests/test_case.gd"


const GameSessionRule = preload("res://src/session/game_session.gd")
const SessionRulesRule = preload("res://src/session/session_rules.gd")


func test_score_100_finishes_once() -> void:
	var session := GameSessionRule.new()
	var finishes: Array[StringName] = []
	var scores: Array[int] = []
	session.session_finished.connect(func(_won: bool, reason: StringName) -> void: finishes.append(reason))
	session.score_changed.connect(func(score: int) -> void: scores.append(score))
	session.add_capture(50)
	session.add_capture(50)
	session.add_capture(50)
	check(session.score == 100, "Score must clamp at the 100-point goal")
	check(session.state == GameSessionRule.State.WON, "Reaching the goal must win the session")
	check(finishes.size() == 1, "Winning must emit one terminal event")
	check(scores == [50, 100], "Captures must emit their clamped score payloads")


func test_tick_expires_the_600_second_session_once() -> void:
	var session := GameSessionRule.new()
	var finishes: Array[StringName] = []
	var times: Array[float] = []
	session.session_finished.connect(
		func(_won: bool, emitted_reason: StringName) -> void:
			finishes.append(emitted_reason)
	)
	session.time_changed.connect(func(seconds: float) -> void: times.append(seconds))
	session.tick(600.0)
	session.tick(1.0)
	check(session.state == GameSessionRule.State.LOST, "Expired time must lose the session")
	check(finishes == [&"time_expired"], "Time expiry must report its named reason")
	check(finishes.size() == 1, "Loss transitions must be idempotent")
	check(times == [0.0], "Ticks must emit the clamped remaining-time payload")


func test_finish_loss_reports_each_reason() -> void:
	var time_session := GameSessionRule.new()
	var time_reasons: Array[StringName] = []
	time_session.session_finished.connect(func(_won: bool, reason: StringName) -> void: time_reasons.append(reason))
	time_session.finish_loss(GameSessionRule.LossReason.TIME_EXPIRED)
	check(time_reasons == [&"time_expired"], "Time expiry must have a stable reason")

	var caught_session := GameSessionRule.new()
	var caught_reasons: Array[StringName] = []
	caught_session.session_finished.connect(func(_won: bool, reason: StringName) -> void: caught_reasons.append(reason))
	caught_session.finish_loss(GameSessionRule.LossReason.CAUGHT)
	check(caught_reasons == [&"caught"], "Guard contact must have a stable reason")

	var fuel_session := GameSessionRule.new()
	var fuel_reasons: Array[StringName] = []
	fuel_session.session_finished.connect(func(_won: bool, reason: StringName) -> void: fuel_reasons.append(reason))
	fuel_session.finish_loss(GameSessionRule.LossReason.OUT_OF_FUEL)
	check(fuel_reasons == [&"out_of_fuel"], "Zero fuel must have a stable reason")


func test_loss_terminal_state_ignores_mixed_reasons() -> void:
	var session := GameSessionRule.new()
	var reasons: Array[StringName] = []
	session.session_finished.connect(func(_won: bool, reason: StringName) -> void: reasons.append(reason))
	session.finish_loss(GameSessionRule.LossReason.CAUGHT)
	session.finish_loss(GameSessionRule.LossReason.OUT_OF_FUEL)
	session.finish_loss(GameSessionRule.LossReason.TIME_EXPIRED)
	check(session.state == GameSessionRule.State.LOST, "The first loss must make the session terminal")
	check(reasons == [&"caught"], "Terminal loss must preserve only its first reason")


func test_session_uses_typed_rules_resource() -> void:
	var session := GameSessionRule.new()
	var rules: Resource = session.get("rules") as Resource
	check(rules != null, "Sessions must expose their rules resource")
	if rules != null:
		check(rules.get_script() == SessionRulesRule, "Session rules must use the typed rules script")
		check(is_equal_approx(float(rules.get("duration_seconds")), 600.0), "Rules must set 600 seconds")
		check(int(rules.get("score_goal")) == 100, "Rules must set the 100-point goal")
