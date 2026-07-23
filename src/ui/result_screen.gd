class_name ResultScreen
extends CanvasLayer


signal replay_requested


var _payload: Dictionary = {}


func present(payload: Dictionary) -> bool:
	if not validate_payload(payload):
		return false
	_payload = payload.duplicate(true)
	$Overlay/Card/Content/Title.text = "THẮNG!" if bool(payload.won) else "KẾT THÚC"
	$Overlay/Card/Content/Reason.text = _reason_text(payload.reason as StringName)
	$Overlay/Card/Content/Stats.text = "Điểm: %d / 100\nSố chó bắt được: %d\nThời gian còn lại: %s" % [
		int(payload.score),
		int(payload.captures),
		_format_time(float(payload.remaining_time)),
	]
	visible = true
	return true


func clear() -> void:
	_payload.clear()
	visible = false


func validate_payload(payload: Dictionary) -> bool:
	return (
		payload.size() == 5
		and payload.has_all(["won", "reason", "score", "remaining_time", "captures"])
		and payload.won is bool
		and payload.reason is StringName
		and payload.score is int
		and payload.remaining_time is float
		and payload.captures is int
	)


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
