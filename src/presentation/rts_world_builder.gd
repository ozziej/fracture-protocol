class_name RtsWorldBuilder
extends RefCounted

const AssetLibraryScript = preload("res://src/presentation/rts_asset_library.gd")

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
	var ground := MeshInstance3D.new()
	var ground_mesh := BoxMesh.new()
	ground_mesh.size = ground_size
	ground.mesh = ground_mesh
	ground.position = ground_position
	ground.material_override = material(Color("#272b2c"), 0.94, 0.03)
	parent.add_child(ground)

	var grid_spacing: int = max(1, int(terrain.get("grid_spacing", 4)))
	for x in range(int(-bounds.x), int(bounds.x) + 1, grid_spacing):
		var line := MeshInstance3D.new()
		var line_mesh := BoxMesh.new()
		line_mesh.size = Vector3(0.035, 0.018, ground_size.z)
		line.mesh = line_mesh
		line.position = Vector3(float(x), ground_position.y + ground_size.y * 0.5 + 0.01, 0.0)
		line.material_override = material(Color(0.34, 0.39, 0.39, 0.34), 1.0, 0.0)
		parent.add_child(line)
	for z in range(int(-bounds.y), int(bounds.y) + 1, grid_spacing):
		var line := MeshInstance3D.new()
		var line_mesh := BoxMesh.new()
		line_mesh.size = Vector3(ground_size.x, 0.018, 0.035)
		line.mesh = line_mesh
		line.position = Vector3(0.0, ground_position.y + ground_size.y * 0.5 + 0.01, float(z))
		line.material_override = material(Color(0.34, 0.39, 0.39, 0.34), 1.0, 0.0)
		parent.add_child(line)

	for road_data in terrain.get("roads", []):
		var road: Dictionary = road_data
		create_road(parent, vector3_from_data(road.get("position", {})), vector3_from_data(road.get("size", {}), Vector3(4.0, 0.03, 4.0)))
	for marker_data in terrain.get("lane_markers", []):
		var marker: Dictionary = marker_data
		create_lane_marker(parent, vector3_from_data(marker.get("position", {})))
	for accent_data in terrain.get("accents", []):
		var accent: Dictionary = accent_data
		create_terrain_accent(parent, vector3_from_data(accent.get("position", {})), vector3_from_data(accent.get("size", {}), Vector3(4.0, 0.04, 4.0)), Color(str(accent.get("color", "#123d49"))))
	for scenery_data in terrain.get("scenery", []):
		var scenery: Dictionary = scenery_data
		create_scenery(
			parent,
			str(scenery.get("asset", "scenery_rock_a")),
			vector3_from_data(scenery.get("position", {})),
			vector3_from_data(scenery.get("scale", {}), Vector3.ONE),
			float(scenery.get("yaw", 0.0))
		)
	for obstacle_data in terrain.get("obstacles", []):
		var obstacle: Dictionary = obstacle_data
		create_obstacle(parent, vector3_from_data(obstacle.get("position", {})), vector3_from_data(obstacle.get("size", {}), Vector3(2.0, 1.0, 2.0)))


static func create_road(parent: Node3D, position: Vector3, size: Vector3) -> void:
	var road := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	road.mesh = mesh
	road.position = position
	road.material_override = material(Color("#3a403f"), 0.98, 0.05)
	parent.add_child(road)


static func create_lane_marker(parent: Node3D, position: Vector3) -> void:
	var marker := MeshInstance3D.new()
	var marker_mesh := BoxMesh.new()
	marker_mesh.size = Vector3(0.55, 0.025, 0.12)
	marker.mesh = marker_mesh
	marker.position = position
	marker.material_override = emissive_material(Color("#d89f42"), 0.8)
	parent.add_child(marker)


static func create_obstacle(parent: Node3D, position: Vector3, size: Vector3) -> void:
	var obstacle := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	obstacle.mesh = mesh
	obstacle.position = position
	obstacle.material_override = material(Color("#4b504e"), 0.82, 0.12)
	parent.add_child(obstacle)
	var highlight := MeshInstance3D.new()
	var highlight_mesh := BoxMesh.new()
	highlight_mesh.size = Vector3(size.x * 0.72, 0.04, size.z * 0.72)
	highlight.mesh = highlight_mesh
	highlight.position = position + Vector3(0.0, size.y * 0.5 + 0.03, 0.0)
	highlight.material_override = material(Color("#747a73"), 0.88, 0.08)
	parent.add_child(highlight)


static func create_terrain_accent(parent: Node3D, position: Vector3, size: Vector3, color: Color) -> void:
	var accent := MeshInstance3D.new()
	var accent_mesh := BoxMesh.new()
	accent_mesh.size = size
	accent.mesh = accent_mesh
	accent.position = position
	accent.material_override = material(color, 0.72, 0.08)
	parent.add_child(accent)


static func create_scenery(parent: Node3D, asset_key: String, position: Vector3, display_scale: Vector3, yaw_degrees: float) -> void:
	var root := Node3D.new()
	root.name = "Scenery_%s" % asset_key
	root.position = position
	root.rotation_degrees.y = yaw_degrees
	root.set_meta("fog_sensitive_scenery", true)
	parent.add_child(root)
	var visual := AssetLibraryScript.attach_asset(root, asset_key, "neutral")
	if visual:
		visual.scale *= display_scale


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
