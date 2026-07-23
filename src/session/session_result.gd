class_name SessionResult
extends RefCounted


const VALID_REASONS: Array[StringName] = [
	&"score_goal",
	&"time_expired",
	&"caught",
	&"out_of_fuel",
]
const SCORE_GOAL := 100
const TIME_EXPIRY_TOLERANCE := 0.001


var won: bool:
	get: return _won
var reason: StringName:
	get: return _reason
var score: int:
	get: return _score
var remaining_time: float:
	get: return _remaining_time
var captures: int:
	get: return _captures
var _won: bool
var _reason: StringName
var _score: int
var _remaining_time: float
var _captures: int


func _init(
	did_win: bool,
	terminal_reason: StringName,
	final_score: int,
	seconds_left: float,
	capture_total: int,
) -> void:
	_won = did_win
	_reason = terminal_reason
	_score = final_score
	_remaining_time = seconds_left
	_captures = capture_total


func is_valid() -> bool:
	var fields_are_valid := (
		reason in VALID_REASONS
		and score >= 0
		and score <= SCORE_GOAL
		and remaining_time >= 0.0
		and captures >= 0
	)
	if not fields_are_valid:
		return false
	match reason:
		&"score_goal":
			return won and score == SCORE_GOAL
		&"time_expired":
			return not won and remaining_time <= TIME_EXPIRY_TOLERANCE
		&"caught", &"out_of_fuel":
			return not won
	return false


func to_payload() -> Dictionary:
	return {
		"won": won,
		"reason": reason,
		"score": score,
		"remaining_time": remaining_time,
		"captures": captures,
	}
