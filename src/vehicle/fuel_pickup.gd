class_name FuelPickup
extends Area3D


signal collected


@export var refill_amount := 35.0
var _was_collected := false


func collect(body: Node) -> void:
	if _was_collected or body == null or not body.has_method("refill_fuel"):
		return
	_was_collected = true
	collision_layer = 0
	collision_mask = 0
	body.call("refill_fuel", refill_amount)
	collected.emit()
	queue_free()
