class_name TutorialScreen
extends Control


signal back_requested


func _ready() -> void:
	$Card/Content/Back.grab_focus()


func _on_back_pressed() -> void:
	back_requested.emit()
