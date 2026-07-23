class_name Neighborhood
extends Node3D


const WorldMarkerRule = preload("res://src/world/world_marker.gd")


@export var road_color := Color("343b46")
@export var alley_color := Color("46505d")
@export var grass_color := Color("456348")
@export var building_colors: Array[Color] = [Color("d8b484"), Color("9bb8c8"), Color("c99aa0")]


func _ready() -> void:
	_build_graybox_geometry()


func layout_summary() -> Dictionary:
	var ids := PackedStringArray()
	var dog_count := 0
	var fuel_count := 0
	var guard_count := 0
	var recovery_count := 0
	for marker in _all_markers():
		var stable_id := StringName(marker.get("stable_id"))
		if stable_id != StringName():
			ids.append(String(stable_id))
		if marker.is_in_group(&"dog_spawn_points"):
			dog_count += 1
		elif marker.is_in_group(&"fuel_spawn_points"):
			fuel_count += 1
		elif marker.is_in_group(&"guard_zone_points"):
			guard_count += 1
		elif marker.is_in_group(&"guard_recovery_points"):
			recovery_count += 1
	var unique_ids := {}
	for stable_id in ids:
		unique_ids[stable_id] = true
	return {
		"dog_markers": dog_count,
		"fuel_markers": fuel_count,
		"guard_zones": guard_count,
		"recovery_markers": recovery_count,
		"stable_ids_unique": ids.size() == _all_markers().size() and unique_ids.size() == ids.size(),
	}


func guard_zones() -> Array[WorldMarkerRule]:
	return _markers_in_group(&"guard_zone_points")


func recovery_markers() -> Array[WorldMarkerRule]:
	return _markers_in_group(&"guard_recovery_points")


func fuel_markers() -> Array[WorldMarkerRule]:
	return _markers_in_group(&"fuel_spawn_points")


func _all_markers() -> Array[Marker3D]:
	var markers: Array[Marker3D] = []
	for container_name in [&"DogMarkers", &"FuelMarkers", &"GuardZones", &"RecoveryMarkers"]:
		var container := get_node_or_null(NodePath(container_name))
		if container == null:
			continue
		for child in container.get_children():
			var marker := child as Marker3D
			if marker != null:
				markers.append(marker)
	return markers


func _markers_in_group(group: StringName) -> Array[WorldMarkerRule]:
	var markers: Array[WorldMarkerRule] = []
	for marker in _all_markers():
		if marker.is_in_group(group):
			var typed_marker := marker as WorldMarkerRule
			if typed_marker != null:
				markers.append(typed_marker)
	return markers


func _build_graybox_geometry() -> void:
	if get_node("Roads/MainRoadLoop").get_child_count() > 0:
		return
	# Four broad slabs form an unmistakable loop around the central residential block.
	_add_box_visual($Roads/MainRoadLoop, "NorthRoad", Vector3(0.0, 0.03, -42.0), Vector3(92.0, 0.08, 12.0), road_color)
	_add_box_visual($Roads/MainRoadLoop, "SouthRoad", Vector3(0.0, 0.03, 42.0), Vector3(92.0, 0.08, 12.0), road_color)
	_add_box_visual($Roads/MainRoadLoop, "WestRoad", Vector3(-40.0, 0.031, 0.0), Vector3(12.0, 0.08, 72.0), road_color)
	_add_box_visual($Roads/MainRoadLoop, "EastRoad", Vector3(40.0, 0.031, 0.0), Vector3(12.0, 0.08, 72.0), road_color)
	_add_box_visual($Roads/AlleyNorth, "AlleySurface", Vector3(0.0, 0.04, -13.0), Vector3(68.0, 0.09, 7.0), alley_color)
	_add_box_visual($Roads/AlleySouth, "AlleySurface", Vector3(0.0, 0.04, 14.0), Vector3(68.0, 0.09, 7.0), alley_color)
	_add_box_visual($Yards, "CentralYard", Vector3(0.0, 0.0, 0.0), Vector3(68.0, 0.05, 20.0), grass_color)
	_add_box_visual($Yards, "WestYard", Vector3(-24.0, 0.0, 0.0), Vector3(14.0, 0.06, 10.0), Color("527657"))
	_add_box_visual($Yards, "EastYard", Vector3(24.0, 0.0, 0.0), Vector3(14.0, 0.06, 10.0), Color("527657"))
	for data in [
		["HouseNW", Vector3(-24.0, 2.5, -25.0), Vector3(13.0, 5.0, 10.0), 0],
		["HouseNE", Vector3(22.0, 3.0, -26.0), Vector3(15.0, 6.0, 9.0), 1],
		["HouseSW", Vector3(-22.0, 2.25, 26.0), Vector3(16.0, 4.5, 9.0), 2],
		["HouseSE", Vector3(24.0, 2.75, 25.0), Vector3(13.0, 5.5, 10.0), 0],
	]:
		_add_static_box($StaticCollision, data[0], data[1], data[2], building_colors[data[3]])
	_add_static_box($StaticCollision, "Ground", Vector3(0.0, -0.5, 0.0), Vector3(120.0, 1.0, 120.0), grass_color)
	_add_static_box($StaticCollision, "NorthBoundary", Vector3(0.0, 1.0, -59.0), Vector3(120.0, 2.0, 1.0), Color("70808a"))
	_add_static_box($StaticCollision, "SouthBoundary", Vector3(0.0, 1.0, 59.0), Vector3(120.0, 2.0, 1.0), Color("70808a"))
	_add_static_box($StaticCollision, "WestBoundary", Vector3(-59.0, 1.0, 0.0), Vector3(1.0, 2.0, 118.0), Color("70808a"))
	_add_static_box($StaticCollision, "EastBoundary", Vector3(59.0, 1.0, 0.0), Vector3(1.0, 2.0, 118.0), Color("70808a"))
	_add_box_visual($DeadEnds, "NorthSpur", Vector3(-10.0, 0.04, -24.0), Vector3(7.0, 0.09, 16.0), alley_color)
	_add_box_visual($DeadEnds, "SouthSpur", Vector3(10.0, 0.04, 25.0), Vector3(7.0, 0.09, 16.0), alley_color)
	_add_box_visual($DeadEnds, "NorthBarrier", Vector3(-10.0, 0.8, -32.0), Vector3(8.0, 1.6, 0.6), Color("f0b24b"))
	_add_box_visual($DeadEnds, "SouthBarrier", Vector3(10.0, 0.8, 33.0), Vector3(8.0, 1.6, 0.6), Color("f0b24b"))


func _add_box_visual(parent: Node, node_name: String, at: Vector3, size: Vector3, color: Color) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	mesh_instance.position = at
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = _material(color)
	mesh_instance.mesh = mesh
	parent.add_child(mesh_instance)


func _add_static_box(parent: Node, node_name: String, at: Vector3, size: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = at
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	shape_node.shape = shape
	body.add_child(shape_node)
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = _material(color)
	mesh_instance.mesh = mesh
	body.add_child(mesh_instance)
	parent.add_child(body)


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.88
	return material
