extends SceneTree


const REQUIRED_ACTIONS: Array[StringName] = [
	&"steer_left",
	&"steer_right",
	&"accelerate",
	&"brake",
	&"throw_net",
	&"pause",
]
const REQUIRED_EXPORTS := {
	"Windows Desktop": {
		"platform": "Windows Desktop",
		"path_suffix": ".exe",
		"architecture": "x86_64",
	},
	"macOS": {
		"platform": "macOS",
		"path_suffix": ".zip",
		"architecture": "universal",
	},
}


func _init() -> void:
	var failures := 0
	var version: Dictionary = Engine.get_version_info()
	if int(version.get("major", -1)) != 4 or int(version.get("minor", -1)) != 6:
		printerr("FAIL: Godot 4.6 is required; found %s.%s." % [version.get("major", "unknown"), version.get("minor", "unknown")])
		failures += 1

	for action: StringName in REQUIRED_ACTIONS:
		if not InputMap.has_action(action):
			printerr("FAIL: Required input action is missing: %s." % action)
			failures += 1

	var main_scene_path := String(ProjectSettings.get_setting("application/run/main_scene", ""))
	if main_scene_path.is_empty():
		printerr("FAIL: Project main scene is not configured.")
		failures += 1
	elif not ResourceLoader.exists(main_scene_path):
		printerr("FAIL: Configured main scene does not exist: %s." % main_scene_path)
		failures += 1
	else:
		var main_scene := load(main_scene_path)
		if main_scene == null or not main_scene is PackedScene:
			printerr("FAIL: Could not parse or load main scene: %s." % main_scene_path)
			failures += 1

	failures += _validate_export_presets()

	if failures == 0:
		print("Project validation passed")
	quit(0 if failures == 0 else 1)


func _validate_export_presets() -> int:
	var path := "res://export_presets.cfg"
	if not FileAccess.file_exists(path):
		printerr("FAIL: export_presets.cfg is missing.")
		return 1
	var config := ConfigFile.new()
	if config.load(path) != OK:
		printerr("FAIL: export_presets.cfg could not be parsed.")
		return 1
	var failures := 0
	var found := {}
	var preset_index := 0
	while config.has_section("preset.%d" % preset_index):
		var section := "preset.%d" % preset_index
		var options := "%s.options" % section
		var preset_name := String(config.get_value(section, "name", ""))
		found[preset_name] = true
		if REQUIRED_EXPORTS.has(preset_name):
			var required: Dictionary = REQUIRED_EXPORTS[preset_name]
			if String(config.get_value(section, "platform", "")) != required.platform:
				printerr("FAIL: %s export platform is invalid." % preset_name)
				failures += 1
			if not String(config.get_value(section, "export_path", "")).ends_with(required.path_suffix):
				printerr("FAIL: %s export path must end with %s." % [preset_name, required.path_suffix])
				failures += 1
			if String(config.get_value(options, "binary_format/architecture", "")) != required.architecture:
				printerr("FAIL: %s export architecture must be %s." % [preset_name, required.architecture])
				failures += 1
		preset_index += 1
	for preset_name in REQUIRED_EXPORTS:
		if not found.has(preset_name):
			printerr("FAIL: Required export preset is missing: %s." % preset_name)
			failures += 1
	var file := FileAccess.open(path, FileAccess.READ)
	var content := file.get_as_text().to_lower() if file != null else ""
	for prohibited in ["password=", "api_key=", "token=", "secret="]:
		if content.contains(prohibited):
			printerr("FAIL: export_presets.cfg contains a credential-like value.")
			failures += 1
			break
	return failures
