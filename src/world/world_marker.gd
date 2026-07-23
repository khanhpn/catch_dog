class_name WorldMarker
extends Marker3D


enum Kind {
	FUEL,
	GUARD_ZONE,
	RECOVERY,
}


@export var stable_id: StringName
@export var kind: Kind = Kind.FUEL


func _enter_tree() -> void:
	match kind:
		Kind.FUEL:
			add_to_group(&"fuel_spawn_points")
		Kind.GUARD_ZONE:
			add_to_group(&"guard_zone_points")
		Kind.RECOVERY:
			add_to_group(&"guard_recovery_points")
