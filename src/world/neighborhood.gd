class_name Neighborhood
extends Node3D


const WorldMarkerRule = preload("res://src/world/world_marker.gd")


@export var road_color := Color("343b46")
@export var alley_color := Color("46505d")
@export var grass_color := Color("456348")
@export var building_colors: Array[Color] = [Color("d8b484"), Color("9bb8c8"), Color("c99aa0")]


func _ready() -> void:
	_build_graybox_geometry()
	_build_authored_navigation()


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


func _build_authored_navigation() -> void:
	var navigation_mesh := NavigationMesh.new()
	var x_coordinates := PackedFloat32Array([-48.0, -34.0, -13.5, -6.5, 6.5, 13.5, 34.0, 48.0])
	var z_coordinates := PackedFloat32Array([-48.0, -36.0, -31.7, -16.5, -9.5, 10.5, 17.5, 32.7, 36.0, 48.0])
	var vertices := PackedVector3Array()
	var vertex_indices := {}
	for z in z_coordinates:
		for x in x_coordinates:
			vertex_indices[Vector2(x, z)] = vertices.size()
			vertices.append(Vector3(x, 0.05, z))
	navigation_mesh.vertices = vertices
	for z_index in range(z_coordinates.size() - 1):
		for x_index in range(x_coordinates.size() - 1):
			var x0 := x_coordinates[x_index]
			var x1 := x_coordinates[x_index + 1]
			var z0 := z_coordinates[z_index]
			var z1 := z_coordinates[z_index + 1]
			if not _is_walkable_navigation_cell(Vector2((x0 + x1) * 0.5, (z0 + z1) * 0.5)):
				continue
			# Shared grid vertices give NavigationServer exact deterministic adjacency.
			navigation_mesh.add_polygon(PackedInt32Array([
				int(vertex_indices[Vector2(x0, z1)]),
				int(vertex_indices[Vector2(x1, z1)]),
				int(vertex_indices[Vector2(x1, z0)]),
				int(vertex_indices[Vector2(x0, z0)]),
			]))
	var region := $NavigationRegion3D as NavigationRegion3D
	region.navigation_mesh = navigation_mesh
	var region_rid := region.get_rid()
	var navigation_map := get_world_3d().get_navigation_map()
	NavigationServer3D.map_set_active(navigation_map, true)
	NavigationServer3D.region_set_use_async_iterations(region_rid, false)
	NavigationServer3D.region_set_enabled(region_rid, true)
	NavigationServer3D.region_set_map(region_rid, navigation_map)
	NavigationServer3D.region_set_transform(region_rid, region.global_transform)
	NavigationServer3D.region_set_navigation_mesh(region_rid, navigation_mesh)
	NavigationServer3D.map_force_update(navigation_map)


func _is_walkable_navigation_cell(center: Vector2) -> bool:
	var on_outer_loop := (
		(absf(center.x) >= 34.0 and absf(center.x) <= 48.0 and absf(center.y) <= 48.0)
		or (absf(center.y) >= 36.0 and absf(center.y) <= 48.0 and absf(center.x) <= 48.0)
	)
	var on_north_alley := absf(center.x) <= 34.0 and center.y >= -16.5 and center.y <= -9.5
	var on_south_alley := absf(center.x) <= 34.0 and center.y >= 10.5 and center.y <= 17.5
	var in_central_yards := absf(center.x) <= 34.0 and center.y >= -9.5 and center.y <= 10.5
	var on_north_spur := center.x >= -13.5 and center.x <= -6.5 and center.y >= -31.7 and center.y <= -16.5
	var on_south_spur := center.x >= 6.5 and center.x <= 13.5 and center.y >= 17.5 and center.y <= 32.7
	return on_outer_loop or on_north_alley or on_south_alley or in_central_yards or on_north_spur or on_south_spur


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
