class_name Neighborhood
extends Node3D


const WorldMarkerRule = preload("res://src/world/world_marker.gd")


@export var road_color := Color("343b46")
@export var alley_color := Color("46505d")
@export var grass_color := Color("456348")
@export var building_colors: Array[Color] = [Color("d8b484"), Color("9bb8c8"), Color("c99aa0")]


func _enter_tree() -> void:
	_build_graybox_geometry()
	# Activate the World3D map before the child region enters and performs its normal sync.
	NavigationServer3D.map_set_active(get_world_3d().get_navigation_map(), true)


func _ready() -> void:
	# Re-assign through the node API once the child is registered on the active World3D map.
	var region := $NavigationRegion3D as NavigationRegion3D
	var authored_mesh := region.navigation_mesh
	region.navigation_mesh = null
	region.navigation_mesh = authored_mesh


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
	_add_static_box($DeadEnds, "NorthBarrier", Vector3(-10.0, 0.8, -32.0), Vector3(8.0, 1.6, 0.6), Color("f0b24b"))
	_add_static_box($DeadEnds, "SouthBarrier", Vector3(10.0, 0.8, 33.0), Vector3(8.0, 1.6, 0.6), Color("f0b24b"))
	_build_street_dressing()


func _build_street_dressing() -> void:
	for z in [-48.5, -35.5, 35.5, 48.5]:
		_add_box_visual($VisualDressing, "Sidewalk_%s" % z, Vector3(0.0, 0.12, z), Vector3(104.0, 0.22, 1.4), Color("c2b8a4"))
	for x in [-48.5, -33.5, 33.5, 48.5]:
		_add_box_visual($VisualDressing, "Curb_%s" % x, Vector3(x, 0.16, 0.0), Vector3(1.0, 0.28, 74.0), Color("d6cbb5"))
	for position in [
		Vector3(-52, 0, -48), Vector3(-18, 0, -49), Vector3(20, 0, -49),
		Vector3(52, 0, -18), Vector3(52, 0, 20), Vector3(18, 0, 50),
		Vector3(-20, 0, 50), Vector3(-52, 0, 18),
	]:
		_add_tree($VisualDressing, position)
	for position in [
		Vector3(-50, 0, -30), Vector3(-50, 0, 30),
		Vector3(50, 0, -30), Vector3(50, 0, 30),
	]:
		_add_street_lamp($VisualDressing, position)
	for data in [
		[Vector3(-33, 1.3, -18), Color("e55b48")],
		[Vector3(33, 1.3, 19), Color("2a8fc0")],
		[Vector3(-15, 1.3, 33), Color("e0a72f")],
	]:
		_add_shop_sign($VisualDressing, data[0], data[1])


func _add_tree(parent: Node, at: Vector3) -> void:
	var root := Node3D.new()
	root.position = at
	root.name = "StreetTree"
	parent.add_child(root)
	var trunk := MeshInstance3D.new()
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.18
	trunk_mesh.bottom_radius = 0.28
	trunk_mesh.height = 3.2
	trunk_mesh.radial_segments = 8
	trunk_mesh.material = _material(Color("6b4930"))
	trunk.mesh = trunk_mesh
	trunk.position.y = 1.6
	root.add_child(trunk)
	for offset in [Vector3(0, 3.4, 0), Vector3(0.65, 3.1, 0.15), Vector3(-0.55, 3.0, -0.2)]:
		var crown := MeshInstance3D.new()
		var crown_mesh := SphereMesh.new()
		crown_mesh.radius = 1.15
		crown_mesh.height = 1.8
		crown_mesh.radial_segments = 10
		crown_mesh.rings = 6
		crown_mesh.material = _material(Color("3d7442"))
		crown.mesh = crown_mesh
		crown.position = offset
		root.add_child(crown)


func _add_street_lamp(parent: Node, at: Vector3) -> void:
	var root := Node3D.new()
	root.position = at
	root.name = "StreetLamp"
	parent.add_child(root)
	_add_box_visual(root, "Pole", Vector3(0, 2.8, 0), Vector3(0.14, 5.6, 0.14), Color("3b4650"))
	_add_box_visual(root, "Arm", Vector3(0.45, 5.3, 0), Vector3(1.0, 0.12, 0.12), Color("3b4650"))
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0.85, 5.05, 0)
	lamp.light_color = Color("ffd68a")
	lamp.light_energy = 0.45
	lamp.omni_range = 7.0
	lamp.shadow_enabled = false
	root.add_child(lamp)


func _add_shop_sign(parent: Node, at: Vector3, color: Color) -> void:
	var sign := MeshInstance3D.new()
	sign.position = at
	sign.name = "NeighborhoodSign"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(3.6, 1.0, 0.18)
	var material := _material(color)
	material.emission_enabled = true
	material.emission = color * 0.35
	mesh.material = material
	sign.mesh = mesh
	parent.add_child(sign)


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
	shape_node.name = "CollisionShape3D"
	var shape := BoxShape3D.new()
	shape.size = size
	shape_node.shape = shape
	body.add_child(shape_node)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "MeshInstance3D"
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
