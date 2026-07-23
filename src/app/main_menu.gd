class_name MainMenu
extends Control


signal play_requested
signal tutorial_requested
signal settings_requested
signal quit_requested


func _ready() -> void:
	$Content/Actions/Play.grab_focus()


func _on_play_pressed() -> void:
	play_requested.emit()


func _on_tutorial_pressed() -> void:
	tutorial_requested.emit()


func _on_settings_pressed() -> void:
	settings_requested.emit()


func _on_quit_pressed() -> void:
	quit_requested.emit()
