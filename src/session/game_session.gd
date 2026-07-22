class_name GameSession
extends RefCounted


const SessionRulesResource = preload("res://src/session/session_rules.tres")


signal score_changed(score: int)
signal time_changed(seconds: float)
signal session_finished(won: bool, reason: StringName)


enum State {
	RUNNING,
	WON,
	LOST,
}

enum LossReason {
	TIME_EXPIRED,
}


var score: int = 0
var state: State = State.RUNNING
var score_goal: int
var seconds: float


func _init() -> void:
	score_goal = int(SessionRulesResource.get_meta(&"score_goal"))
	seconds = float(SessionRulesResource.get_meta(&"duration_seconds"))


func add_capture(points: int) -> void:
	if state != State.RUNNING:
		return
	score = clampi(score + points, 0, score_goal)
	score_changed.emit(score)
	if score == score_goal:
		state = State.WON
		session_finished.emit(true, &"score_goal")


func tick(delta: float) -> void:
	if state != State.RUNNING:
		return
	seconds = maxf(seconds - maxf(delta, 0.0), 0.0)
	time_changed.emit(seconds)
	if is_zero_approx(seconds):
		finish_loss(LossReason.TIME_EXPIRED)


func finish_loss(reason: LossReason) -> void:
	if state != State.RUNNING:
		return
	state = State.LOST
	match reason:
		LossReason.TIME_EXPIRED:
			session_finished.emit(false, &"time_expired")
