class_name ResultScreen
extends CanvasLayer


const SessionResultRule = preload("res://src/session/session_result.gd")


signal replay_requested


var _result: SessionResultRule


func present(result: SessionResultRule) -> bool:
	if result == null or not result.is_valid():
		return false
	_result = result
	$Overlay/Card/Content/Title.text = "THẮNG!" if result.won else "KẾT THÚC"
	$Overlay/Card/Content/Reason.text = _reason_text(result.reason)
	$Overlay/Card/Content/Stats.text = "Điểm: %d / 100\nSố chó bắt được: %d\nThời gian còn lại: %s" % [
		result.score,
		result.captures,
		_format_time(result.remaining_time),
	]
	visible = true
	return true


func clear() -> void:
	_result = null
	visible = false


func _on_replay_pressed() -> void:
	replay_requested.emit()


func _reason_text(reason: StringName) -> String:
	match reason:
		&"score_goal": return "Đã đạt mục tiêu 100 điểm"
		&"time_expired": return "Hết thời gian"
		&"caught": return "Bị bảo vệ bắt"
		&"out_of_fuel": return "Hết xăng và dừng xe"
	return "Phiên chơi kết thúc"


func _format_time(seconds: float) -> String:
	var whole_seconds := maxi(floori(maxf(seconds, 0.0)), 0)
	return "%02d:%02d" % [whole_seconds / 60, whole_seconds % 60]
