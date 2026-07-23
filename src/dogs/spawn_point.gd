class_name SpawnPoint
extends Marker3D


@export var stable_id: StringName


func _enter_tree() -> void:
	add_to_group(&"dog_spawn_points")
