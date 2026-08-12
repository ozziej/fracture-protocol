class_name RtsWorldBuilder
extends RefCounted

const AssetLibraryScript = preload("res://src/presentation/rts_asset_library.gd")
const TerrainDecoratorScript = preload("res://src/presentation/rts_terrain_decorator.gd")

## Builds static presentation geometry from authored terrain data. It deliberately
## has no gameplay authority: simulation remains the source of map bounds/state.

static func build_environment(parent: Node3D) -> void:
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#111416")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#d2cec4")
	environment.ambient_light_energy = 0.62
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_environment.environment = environment
	parent.add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -28.0, 0.0)
	sun.light_color = Color("#d5e7ec")
	sun.light_energy = 1.45
	sun.shadow_enabled = true
	parent.add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-22.0, 148.0, 0.0)
	fill.light_color = Color("#8d776b")
	fill.light_energy = 0.24
	parent.add_child(fill)


static func build_camera(parent: Node3D) -> Camera3D:
	var camera := Camera3D.new()
	camera.name = "TacticalCamera"
	camera.current = true
	camera.fov = 48.0
	camera.near = 0.1
	camera.far = 180.0
	parent.add_child(camera)
	return camera


static func build_world_shell(parent: Node3D, simulation) -> void:
	var terrain: Dictionary = simulation.get_level_terrain()
	var bounds: Vector2 = simulation.get_level_bounds()
	var ground_size := vector3_from_data(terrain.get("ground_size", {}), Vector3(bounds.x * 2.0, 0.25, bounds.y * 2.0))
	var ground_position := vector3_from_data(terrain.get("ground_position", {}), Vector3(0.0, -0.18, 0.0))
	create_ground_surface(parent, ground_size, ground_position, Color(str(terrain.get("ground_color", "#342f2c"))))

	var grid_spacing: int = max(1, int(terrain.get("grid_spacing", 4)))
	var grid_color := Color(str(terrain.get("grid_color", "#75685f")))
	grid_color.a = float(terrain.get("grid_alpha", 0.18))
	for x in range(int(-bounds.x), int(bounds.x) + 1, grid_spacing):
		var line := MeshInstance3D.new()
		var line_mesh := BoxMesh.new()
		line_mesh.size = Vector3(0.035, 0.018, ground_size.z)
		line.mesh = line_mesh
		line.position = Vector3(float(x), ground_position.y + ground_size.y * 0.5 + 0.01, 0.0)
		line.material_override = material(grid_color, 1.0, 0.0)
		parent.add_child(line)
	for z in range(int(-bounds.y), int(bounds.y) + 1, grid_spacing):
		var line := MeshInstance3D.new()
		var line_mesh := BoxMesh.new()
		line_mesh.size = Vector3(ground_size.x, 0.018, 0.035)
		line.mesh = line_mesh
		line.position = Vector3(0.0, ground_position.y + ground_size.y * 0.5 + 0.01, float(z))
		line.material_override = material(grid_color, 1.0, 0.0)
		parent.add_child(line)

	for road_data in terrain.get("roads", []):
		var road: Dictionary = road_data
		create_road(
			parent,
			vector3_from_data(road.get("position", {})),
			vector3_from_data(road.get("size", {}), Vector3(4.0, 0.03, 4.0)),
			Color(str(terrain.get("road_color", "#51463e"))),
			str(road.get("kind", "straight"))
		)
		var road_kind := str(road.get("kind", "")).to_lower()
		if road_kind == "crossing" or road_kind == "crossroads":
			_create_road_asset(parent, vector3_from_data(road.get("position", {})), Vector3(4.0, 1.0, 4.0), "terrain_road_cross", 0.0)
		elif not road_kind.contains("corner") and not road_kind.contains("end"):
			_create_road_endcaps(parent, vector3_from_data(road.get("position", {})), vector3_from_data(road.get("size", {}), Vector3(4.0, 0.03, 4.0)))
	for marker_data in terrain.get("lane_markers", []):
		var marker: Dictionary = marker_data
		create_lane_marker(parent, vector3_from_data(marker.get("position", {})))
	for accent_data in terrain.get("accents", []):
		var accent: Dictionary = accent_data
		create_terrain_accent(
			parent,
			vector3_from_data(accent.get("position", {})),
			vector3_from_data(accent.get("size", {}), Vector3(4.0, 0.04, 4.0)),
			Color(str(accent.get("color", "#123d49"))),
			str(accent.get("kind", "terrain_pad"))
		)
	for scenery_data in terrain.get("scenery", []):
		var scenery: Dictionary = scenery_data
		TerrainDecoratorScript.create_scenery(
			parent,
			str(scenery.get("asset", "scenery_rock_a")),
			vector3_from_data(scenery.get("position", {})),
			vector3_from_data(scenery.get("scale", {}), Vector3.ONE),
			float(scenery.get("yaw", 0.0)),
			bool(scenery.get("blocks_movement", false)),
			vector3_from_data(scenery.get("collision_size", {}))
		)
	TerrainDecoratorScript.decorate(parent, terrain, bounds)


static func create_ground_surface(parent: Node3D, size: Vector3, position: Vector3, fallback_color := Color("#342f2c")) -> Node3D:
	var root := Node3D.new()
	root.name = "TerrainGround"
	root.set_meta("terrain_asset", "terrain_ground")
	root.position = Vector3(position.x, position.y + size.y * 0.5, position.z)
	parent.add_child(root)
	var visual := AssetLibraryScript.attach_asset(root, "terrain_ground", "neutral")
	if visual != null:
		# terrain.glb is an authored one-square plane. Scale only its footprint;
		# unlike the old BoxMesh this cannot create a visible vertical map slab.
		visual.scale = Vector3(maxf(1.0, size.x), 1.0, maxf(1.0, size.z))
		_centre_scaled_asset(visual)
		return root
	var fallback := MeshInstance3D.new()
	var fallback_mesh := PlaneMesh.new()
	fallback_mesh.size = Vector2(maxf(1.0, size.x), maxf(1.0, size.z))
	fallback.mesh = fallback_mesh
	fallback.material_override = material(fallback_color, 0.94, 0.03)
	root.add_child(fallback)
	return root


static func create_road(parent: Node3D, position: Vector3, size: Vector3, color := Color("#51463e"), kind := "straight") -> Node3D:
	var lower_kind := kind.to_lower()
	var asset_key := "terrain_road_straight"
	if lower_kind.contains("corner"):
		asset_key = "terrain_road_corner"
	elif lower_kind.contains("end"):
		asset_key = "terrain_road_end"
	var long_axis_x := size.x >= size.z
	var yaw := 0.0 if long_axis_x else 90.0
	return _create_road_asset(parent, position, Vector3(maxf(1.0, size.x), 1.0, maxf(1.0, size.z)), asset_key, yaw, color)


static func _create_road_asset(parent: Node3D, position: Vector3, footprint: Vector3, asset_key: String, yaw_degrees: float, fallback_color := Color("#51463e")) -> Node3D:
	var root := Node3D.new()
	root.name = "Road_%s_%03d" % [asset_key, parent.get_child_count()]
	root.position = position
	root.set_meta("terrain_road_asset", asset_key)
	parent.add_child(root)
	var visual := AssetLibraryScript.attach_asset(root, asset_key, "neutral")
	if visual != null:
		visual.rotation_degrees.y = yaw_degrees
		visual.scale = Vector3(maxf(1.0, footprint.x), 1.0, maxf(1.0, footprint.z))
		_centre_scaled_asset(visual)
		return root
	var fallback := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(maxf(1.0, footprint.x), maxf(1.0, footprint.z))
	fallback.mesh = mesh
	fallback.material_override = material(fallback_color, 0.98, 0.05)
	root.add_child(fallback)
	return root


static func _create_road_endcaps(parent: Node3D, position: Vector3, size: Vector3) -> void:
	var long_axis_x := size.x >= size.z
	var cap_width := maxf(1.0, minf(size.x, size.z))
	var offset := maxf(0.0, maxf(size.x, size.z) * 0.5 - cap_width * 0.5)
	var yaw := 0.0 if long_axis_x else 90.0
	var first := position + (Vector3(-offset, 0.0, 0.0) if long_axis_x else Vector3(0.0, 0.0, -offset))
	var second := position + (Vector3(offset, 0.0, 0.0) if long_axis_x else Vector3(0.0, 0.0, offset))
	var footprint := Vector3(cap_width, 1.0, cap_width)
	_create_road_asset(parent, first, footprint, "terrain_road_end", yaw)
	_create_road_asset(parent, second, footprint, "terrain_road_end", yaw + 180.0)


static func create_lane_marker(parent: Node3D, position: Vector3) -> void:
	var marker := MeshInstance3D.new()
	var marker_mesh := BoxMesh.new()
	marker_mesh.size = Vector3(0.55, 0.025, 0.12)
	marker.mesh = marker_mesh
	marker.position = position
	marker.material_override = emissive_material(Color("#d89f42"), 0.8)
	parent.add_child(marker)


static func create_obstacle(parent: Node3D, position: Vector3, size: Vector3, kind := "mesa") -> void:
	TerrainDecoratorScript.create_obstacle(parent, position, size, kind)


static func create_terrain_accent(parent: Node3D, position: Vector3, size: Vector3, color: Color, kind := "terrain_pad") -> void:
	TerrainDecoratorScript.create_accent_pad(parent, position, size, color, kind)


static func create_scenery(parent: Node3D, asset_key: String, position: Vector3, display_scale: Vector3, yaw_degrees: float, blocks_movement := false, collision_size := Vector3.ZERO) -> Node3D:
	return TerrainDecoratorScript.create_scenery(parent, asset_key, position, display_scale, yaw_degrees, blocks_movement, collision_size)


static func terrain_height_at(terrain: Dictionary, position: Vector3) -> float:
	var height := 0.0
	for platform_data in terrain.get("walkable_terrain", []):
		var platform: Dictionary = platform_data
		var centre := vector3_from_data(platform.get("position", {}))
		var size := vector3_from_data(platform.get("size", {}), Vector3(6.0, 0.5, 5.0))
		if absf(position.x - centre.x) <= size.x * 0.5 and absf(position.z - centre.z) <= size.z * 0.5:
			height = maxf(height, float(platform.get("height", size.y)))
	return height


static func sync_scenery_visibility(parent: Node3D, visibility: Dictionary) -> void:
	var hidden_cells: PackedVector3Array = visibility.get("hidden_cells", PackedVector3Array())
	var tile_size: float = maxf(2.0, float(visibility.get("tile_size", 8.0)))
	for child in parent.get_children():
		if child is Node3D and child.has_meta("fog_sensitive_scenery"):
			child.visible = not _position_in_cells(child.position, hidden_cells, tile_size)


static func _position_in_cells(position: Vector3, cells: PackedVector3Array, tile_size: float) -> bool:
	var half_size := tile_size * 0.5
	for center in cells:
		if absf(position.x - center.x) <= half_size and absf(position.z - center.z) <= half_size:
			return true
	return false


static func _centre_scaled_asset(asset: Node3D) -> void:
	var bounds := _node_bounds(asset, Transform3D.IDENTITY, AABB())
	if bounds.size == Vector3.ZERO:
		return
	# Several Kenney terrain GLBs use a tile-grid origin rather than a tile
	# centre. Centre after applying scale/rotation so authored map coordinates
	# place the visual footprint, not the source file's arbitrary origin.
	asset.position = -bounds.get_center()


static func _node_bounds(node: Node, parent_transform: Transform3D, current: AABB) -> AABB:
	var transform := parent_transform
	if node is Node3D:
		transform = parent_transform * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh:
		var next_bounds := transform * (node as MeshInstance3D).mesh.get_aabb()
		current = next_bounds if current.size == Vector3.ZERO else current.merge(next_bounds)
	for child in node.get_children():
		current = _node_bounds(child, transform, current)
	return current


static func vector3_from_data(value: Variant, fallback: Vector3 = Vector3.ZERO) -> Vector3:
	if value is Vector3:
		return value
	if value is Dictionary:
		var data: Dictionary = value
		return Vector3(float(data.get("x", fallback.x)), float(data.get("y", fallback.y)), float(data.get("z", fallback.z)))
	return fallback


static func material(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	if color.a < 0.99:
		result.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	result.roughness = roughness
	result.metallic = metallic
	return result


static func emissive_material(color: Color, energy: float) -> StandardMaterial3D:
	var result := material(color, 0.3, 0.1)
	result.emission_enabled = true
	result.emission = color
	result.emission_energy_multiplier = energy
	return result
