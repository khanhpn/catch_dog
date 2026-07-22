extends SceneTree


const REQUIRED_ACTIONS: Array[StringName] = [
	&"steer_left",
	&"steer_right",
	&"accelerate",
	&"brake",
	&"throw_net",
	&"pause",
]


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

	if failures == 0:
		print("Project validation passed")
	quit(0 if failures == 0 else 1)
