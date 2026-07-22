extends Node
class_name TestCase


var failure_messages: PackedStringArray = []


func check(condition: bool, message: String) -> void:
	if not condition:
		failure_messages.append(message)
