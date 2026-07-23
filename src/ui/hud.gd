class_name GameplayHud
extends CanvasLayer


@onready var _score_label := $SafeArea/TopBar/Score as Label
@onready var _time_label := $SafeArea/TopBar/Time as Label
@onready var _fuel_bar := $SafeArea/FuelPanel/Fuel as ProgressBar
@onready var _fuel_value := $SafeArea/FuelPanel/Value as Label
@onready var _target_status := $SafeArea/TargetPanel/Status as Label
@onready var _cooldown_bar := $SafeArea/TargetPanel/Cooldown as ProgressBar
@onready var _chase_warning := $SafeArea/ChaseWarning as Label
@onready var _threat_indicators := $SafeArea/ThreatIndicators as Control


func _ready() -> void:
	update_score(0, 100)
	update_time(180.0)
	update_fuel(1.0)
	update_target_state(false, 1.0)
	update_chase(false, [])


func update_score(score: int, goal: int) -> void:
	_score_label.text = "%d / %d" % [maxi(score, 0), maxi(goal, 0)]


func update_time(seconds: float) -> void:
	var whole_seconds := maxi(ceili(maxf(seconds, 0.0)), 0)
	_time_label.text = "%02d:%02d" % [whole_seconds / 60, whole_seconds % 60]


func update_fuel(ratio: float) -> void:
	var percent := clampf(ratio, 0.0, 1.0) * 100.0
	_fuel_bar.value = percent
	_fuel_value.text = "%d%%" % roundi(percent)


func update_target_state(locked: bool, cooldown_ratio: float) -> void:
	_target_status.text = "LOCKED" if locked else "NO TARGET"
	_cooldown_bar.value = clampf(cooldown_ratio, 0.0, 1.0) * 100.0
	if locked and cooldown_ratio >= 1.0:
		_target_status.text = "LOCKED · READY"
	elif locked:
		_target_status.text = "LOCKED · COOLDOWN"


func update_chase(active: bool, directions: Array[Vector3]) -> void:
	_chase_warning.visible = active
	for child in _threat_indicators.get_children():
		child.free()
	for direction in directions:
		var indicator := Label.new()
		indicator.text = "▲"
		indicator.add_theme_font_size_override("font_size", 24)
		indicator.position = Vector2(132.0, 52.0)
		indicator.pivot_offset = Vector2(12.0, 12.0)
		indicator.rotation = atan2(direction.x, -direction.z)
		indicator.modulate = Color("ff665c")
		_threat_indicators.add_child(indicator)
