extends "res://tests/test_case.gd"


const GameSessionRule = preload("res://src/session/game_session.gd")


func test_score_100_finishes_once() -> void:
	var session := GameSessionRule.new()
	var finishes: Array[StringName] = []
	session.session_finished.connect(func(_won: bool, reason: StringName) -> void: finishes.append(reason))
	session.add_capture(50)
	session.add_capture(50)
	session.add_capture(50)
	check(session.score == 100, "Score must clamp at the 100-point goal")
	check(session.state == GameSessionRule.State.WON, "Reaching the goal must win the session")
	check(finishes.size() == 1, "Winning must emit one terminal event")


func test_tick_expires_the_600_second_session_once() -> void:
	var session := GameSessionRule.new()
	var finishes: Array[StringName] = []
	session.session_finished.connect(
		func(_won: bool, emitted_reason: StringName) -> void:
			finishes.append(emitted_reason)
	)
	session.tick(600.0)
	session.tick(1.0)
	check(session.state == GameSessionRule.State.LOST, "Expired time must lose the session")
	check(finishes == [&"time_expired"], "Time expiry must report its named reason")
	check(finishes.size() == 1, "Loss transitions must be idempotent")
