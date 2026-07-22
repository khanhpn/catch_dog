extends Node
class_name Main


@onready var screen_root: Node = $ScreenRoot


func change_screen(scene: PackedScene) -> void:
	for child: Node in screen_root.get_children():
		child.queue_free()
	screen_root.add_child(scene.instantiate())
