class_name SettingsStore
extends RefCounted


enum Preset { LOW, MEDIUM, HIGH }

const VERSION := 1
const DEFAULT_PATH := "user://settings.json"
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
]

var storage_path: String
var master_volume := 0.8
var music_volume := 0.65
var effects_volume := 0.8
var fullscreen := false
var resolution := Vector2i(1280, 720)
var graphics_preset: Preset = Preset.MEDIUM
var camera_shake := 0.65
var reduced_motion := false


func _init(path: String = DEFAULT_PATH) -> void:
	storage_path = path


func load_settings() -> void:
	if not FileAccess.file_exists(storage_path):
		apply()
		return
	var file := FileAccess.open(storage_path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	if not parsed is Dictionary:
		apply()
		return
	var data := parsed as Dictionary
	master_volume = _valid_ratio(data.get("master_volume"), 0.8)
	music_volume = _valid_ratio(data.get("music_volume"), 0.65)
	effects_volume = _valid_ratio(data.get("effects_volume"), 0.8)
	fullscreen = data.get("fullscreen") if data.get("fullscreen") is bool else false
	resolution = _valid_resolution(data.get("resolution"))
	var preset_value: Variant = data.get("graphics_preset")
	graphics_preset = preset_value as Preset if preset_value is int and int(preset_value) in Preset.values() else Preset.MEDIUM
	camera_shake = _valid_ratio(data.get("camera_shake"), 0.65)
	reduced_motion = data.get("reduced_motion") if data.get("reduced_motion") is bool else false
	apply()


func save_settings() -> bool:
	var file := FileAccess.open(storage_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({
		"version": VERSION,
		"master_volume": master_volume,
		"music_volume": music_volume,
		"effects_volume": effects_volume,
		"fullscreen": fullscreen,
		"resolution": "%dx%d" % [resolution.x, resolution.y],
		"graphics_preset": int(graphics_preset),
		"camera_shake": camera_shake,
		"reduced_motion": reduced_motion,
	}, "\t"))
	return true


func apply() -> void:
	_ensure_audio_buses()
	_set_bus_volume(&"Master", master_volume)
	_set_bus_volume(&"Music", music_volume)
	_set_bus_volume(&"Effects", effects_volume)
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED,
	)
	if not fullscreen:
		DisplayServer.window_set_size(resolution)


func apply_graphics_preset(
	preset: Preset,
	environment: Environment = null,
	sun: DirectionalLight3D = null,
) -> void:
	graphics_preset = preset
	if environment != null:
		environment.glow_enabled = preset != Preset.LOW
		environment.fog_enabled = preset != Preset.LOW
	if sun != null:
		sun.shadow_enabled = true
		sun.directional_shadow_max_distance = 55.0 if preset == Preset.LOW else 90.0


func _valid_ratio(value: Variant, fallback: float) -> float:
	return clampf(float(value), 0.0, 1.0) if value is float or value is int else fallback


func _valid_resolution(value: Variant) -> Vector2i:
	if not value is String:
		return RESOLUTIONS[0]
	var parts := String(value).split("x")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return RESOLUTIONS[0]
	var candidate := Vector2i(parts[0].to_int(), parts[1].to_int())
	return candidate if candidate in RESOLUTIONS else RESOLUTIONS[0]


func _ensure_audio_buses() -> void:
	for bus_name in [&"Music", &"Effects"]:
		if AudioServer.get_bus_index(bus_name) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)


func _set_bus_volume(bus_name: StringName, ratio: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index >= 0:
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(ratio, 0.0001)))
