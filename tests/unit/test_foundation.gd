extends "res://tests/test_case.gd"


func test_required_actions_exist() -> void:
	for action: StringName in [&"steer_left", &"steer_right", &"accelerate", &"brake", &"throw_net", &"pause"]:
		check(InputMap.has_action(action), "Missing input action: %s" % action)
