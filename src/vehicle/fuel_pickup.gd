class_name FuelPickup
extends Area3D


const PlayerVehicleRule = preload("res://src/vehicle/player_vehicle.gd")


signal collected


@export var refill_amount := 35.0
var _was_collected := false


func collect(body: Node3D) -> void:
	var vehicle := body as PlayerVehicleRule
	if _was_collected or vehicle == null:
		return
	_was_collected = true
	collision_layer = 0
	collision_mask = 0
	vehicle.refill_fuel(refill_amount)
	collected.emit()
	queue_free()
