class_name PauseMenu
extends CanvasLayer


signal pause_requested
signal resume_requested
signal restart_requested
signal main_menu_requested


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause"):
		if visible:
			resume_requested.emit()
		else:
			pause_requested.emit()
		get_viewport().set_input_as_handled()


func show_menu() -> void:
	visible = true
	$Overlay/Card/Actions/Resume.grab_focus()


func hide_menu() -> void:
	visible = false


func _on_resume_pressed() -> void:
	resume_requested.emit()


func _on_restart_pressed() -> void:
	restart_requested.emit()


func _on_main_menu_pressed() -> void:
	main_menu_requested.emit()
