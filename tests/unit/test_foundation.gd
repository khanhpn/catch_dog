extends "res://tests/test_case.gd"


const REQUIRED_PHYSICAL_KEYS: Dictionary[StringName, int] = {
	&"steer_left": 4194319,
	&"steer_right": 4194321,
	&"accelerate": 4194320,
	&"brake": 4194322,
	&"throw_net": 32,
	&"pause": 4194305,
}


func test_required_actions_exist() -> void:
	for action: StringName in [&"steer_left", &"steer_right", &"accelerate", &"brake", &"throw_net", &"pause"]:
		check(InputMap.has_action(action), "Missing input action: %s" % action)


func test_required_actions_use_expected_physical_keys() -> void:
	for action: StringName in REQUIRED_PHYSICAL_KEYS:
		var expected_key := REQUIRED_PHYSICAL_KEYS[action]
		check(_has_physical_key(action, expected_key), "Action %s is missing physical keycode %s" % [action, expected_key])


func test_rendering_device_open_gl_fallback_is_explicitly_enabled() -> void:
	var project_config := ConfigFile.new()
	check(project_config.load("res://project.godot") == OK, "Could not load project.godot")
	check(
		project_config.has_section_key("rendering", "rendering_device/fallback_to_opengl3")
		and project_config.get_value("rendering", "rendering_device/fallback_to_opengl3") == true,
		"RenderingDevice fallback to OpenGL 3 must be explicitly enabled",
	)


func _has_physical_key(action: StringName, expected_key: int) -> bool:
	for event: InputEvent in InputMap.action_get_events(action):
		var key_event := event as InputEventKey
		if key_event != null and key_event.physical_keycode == expected_key:
			return true
	return false
