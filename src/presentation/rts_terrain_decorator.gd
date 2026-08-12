class_name RtsTerrainDecorator
extends RefCounted

const AssetLibraryScript = preload("res://src/presentation/rts_asset_library.gd")

## Presentation-only terrain composition. Small Kenney modules are repeated at
## near-uniform scale to form a few readable landforms; they are never stretched
## to match simulation obstacle rectangles.


static func decorate(parent: Node3D, terrain: Dictionary, bounds: Vector2) -> void:
	var border: Dictionary = terrain.get("terrain_border", {})
	if bool(border.get("enabled", true)):
		_build_sparse_boundary(parent, bounds, border)
	for platform_data in terrain.get("walkable_terrain", []):
		create_walkable_mesa(parent, platform_data)
	for zone_data in terrain.get("vegetation_zones", []):
		_create_vegetation_zone(parent, zone_data)
	for obstacle_data in terrain.get("obstacles", []):
		var obstacle: Dictionary = obstacle_data
		create_obstacle(
			parent,
			_vector3(obstacle.get("position", {})),
			_vector3(obstacle.get("size", {}), Vector3(2.0, 1.0, 2.0)),
			str(obstacle.get("kind", "mesa"))
		)


static func create_feature(parent: Node3D, feature_data: Dictionary) -> Node3D:
	var asset_key := str(feature_data.get("asset", "scenery_rock_a"))
	var root := Node3D.new()
	root.name = "Scenery_%s" % asset_key
	root.position = _vector3(feature_data.get("position", {}))
	if bool(feature_data.get("fog_sensitive", true)):
		root.set_meta("fog_sensitive_scenery", true)
	root.set_meta("terrain_asset", asset_key)
	parent.add_child(root)
	_attach_piece(
		root,
		asset_key,
		Vector3.ZERO,
		_vector3(feature_data.get("scale", {}), Vector3.ONE),
		float(feature_data.get("yaw", 0.0))
	)
	if bool(feature_data.get("blocks_movement", false)):
		_add_collision(root, _vector3(feature_data.get("collision_size", {}), Vector3(3.0, 2.0, 3.0)))
	return root


static func create_scenery(parent: Node3D, asset_key: String, position: Vector3, display_scale: Vector3, yaw_degrees: float, blocks_movement := false, collision_size := Vector3.ZERO) -> Node3D:
	return create_feature(parent, {
		"asset": asset_key,
		"position": position,
		"scale": display_scale,
		"yaw": yaw_degrees,
		"fog_sensitive": true,
		"blocks_movement": blocks_movement,
		"collision_size": collision_size,
	})


static func create_walkable_mesa(parent: Node3D, platform_data: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "WalkableMesa_%s" % str(platform_data.get("id", "platform"))
	root.position = _vector3(platform_data.get("position", {}))
	root.set_meta("fog_sensitive_scenery", true)
	root.set_meta("terrain_walkable", true)
	root.set_meta("terrain_height", float(platform_data.get("height", 0.5)))
	root.set_meta("terrain_size", _vector2(platform_data.get("size", {}), Vector2(6.0, 5.0)))
	parent.add_child(root)
	var visual_scale := _vector3(platform_data.get("scale", {}), Vector3.ONE)
	# Y deliberately remains authored at 1.0; rectangular variants change only
	# their X/Z footprint and never become vertically extruded.
	visual_scale.y = 1.0
	_attach_piece(
		root,
		str(platform_data.get("asset", "terrain_mesa_small_b")),
		Vector3.ZERO,
		visual_scale,
		float(platform_data.get("yaw", 0.0))
	)
	var size_data := _vector3(platform_data.get("collision_size", {}), Vector3(6.0, 0.5, 5.0))
	_add_collision(root, Vector3(size_data.x, float(platform_data.get("height", size_data.y)), size_data.z))
	return root


static func create_accent_pad(parent: Node3D, position: Vector3, size: Vector3, color: Color, kind: String) -> Node3D:
	var root := Node3D.new()
	root.name = "TerrainPad_%s" % kind
	root.position = Vector3(position.x, 0.0, position.z)
	root.set_meta("fog_sensitive_scenery", true)
	parent.add_child(root)
	var asset_key := "terrain_road_straight"
	if kind.contains("signal") or kind.contains("core"):
		asset_key = "terrain_road_cross"
	elif kind.contains("energy"):
		asset_key = "terrain_road_end"
	# Accents identify a location; they must not reproduce the full gameplay
	# footprint as a conspicuous rectangular platform.
	var pad_scale := clampf(minf(size.x, size.z) * 0.82, 2.4, 4.0)
	_attach_piece(root, asset_key, Vector3(0.0, position.y, 0.0), Vector3.ONE * pad_scale, 0.0)
	var ring_mesh := TorusMesh.new()
	ring_mesh.outer_radius = maxf(0.7, minf(size.x, size.z) * 0.28)
	ring_mesh.inner_radius = maxf(0.4, ring_mesh.outer_radius - 0.18)
	ring_mesh.rings = 28
	ring_mesh.ring_segments = 8
	var ring := MeshInstance3D.new()
	ring.name = "RoleMarker"
	ring.mesh = ring_mesh
	ring.position.y = position.y + 0.1
	ring.material_override = _material(Color(color.r, color.g, color.b, 0.74))
	root.add_child(ring)
	return root


static func create_obstacle(parent: Node3D, position: Vector3, size: Vector3, kind := "mesa") -> Node3D:
	var root := Node3D.new()
	root.name = "TerrainObstacle_%s" % kind
	root.position = Vector3(position.x, 0.0, position.z)
	root.set_meta("fog_sensitive_scenery", true)
	parent.add_child(root)
	if kind.contains("tower"):
		_build_tower_outcrop(root, size)
	elif kind.contains("block"):
		_build_station_outpost(root, size, kind.contains("south"))
	elif kind == "debris":
		_build_debris(root, size)
	else:
		_build_rock_barrier(root, size, kind.contains("lower"))
	_add_collision(root, size)
	return root


static func _build_sparse_boundary(parent: Node3D, bounds: Vector2, settings: Dictionary) -> void:
	var inset := maxf(2.0, float(settings.get("inset", 5.0)))
	var cluster_size := maxf(5.0, float(settings.get("cluster_size", 8.0)))
	var height := maxf(2.0, float(settings.get("height", 4.5)))
	var positions := [
		Vector3(-bounds.x + inset, 0.0, -bounds.y + inset),
		Vector3(bounds.x - inset, 0.0, bounds.y - inset),
		Vector3(bounds.x - inset, 0.0, -bounds.y + inset),
		Vector3(-bounds.x + inset, 0.0, bounds.y - inset),
		Vector3(-bounds.x * 0.48, 0.0, -bounds.y + inset),
		Vector3(bounds.x * 0.48, 0.0, bounds.y - inset),
		Vector3(-bounds.x + inset, 0.0, bounds.y * 0.35),
		Vector3(bounds.x - inset, 0.0, -bounds.y * 0.35),
	]
	for index in range(positions.size()):
		var root := Node3D.new()
		root.name = "BoundaryOutcrop_%02d" % index
		root.position = positions[index]
		root.set_meta("fog_sensitive_scenery", true)
		parent.add_child(root)
		_build_boundary_outcrop(root, cluster_size * (1.18 if index < 4 else 0.86), height, index)


static func _build_boundary_outcrop(root: Node3D, cluster_size: float, height: float, seed: int) -> void:
	# Boundary dressing uses the existing rocky outcrops only. Keep the cluster
	# grounded and irregular; there is no elevated platform or ramp geometry.
	var base_scale := clampf(cluster_size * 0.3, 1.5, 2.7)
	var offsets := [
		Vector3(-0.42, 0.0, 0.0),
		Vector3(0.38, 0.0, 0.2),
		Vector3(0.05, 0.0, -0.46),
		Vector3(-0.12, 0.0, 0.42),
	]
	var scale_factors := [1.0, 0.76, 0.88, 0.62]
	for index in range(offsets.size()):
		var rock_key := "terrain_rock_a" if (index + seed) % 2 == 0 else "terrain_rock_b"
		var rock_scale := base_scale * float(scale_factors[index])
		_attach_piece(
			root,
			rock_key,
			offsets[index] * base_scale,
			Vector3.ONE * rock_scale,
			float((seed * 37 + index * 83) % 360)
		)
	_add_collision(root, Vector3(maxf(4.0, cluster_size * 0.72), maxf(1.4, height * 0.35), maxf(4.0, cluster_size * 0.72)))


static func _create_vegetation_zone(parent: Node3D, zone_data: Dictionary) -> void:
	var assets: Array = zone_data.get("assets", [])
	if assets.is_empty():
		return
	var centre := _vector3(zone_data.get("position", {}))
	var radius := _vector2(zone_data.get("radius", {}), Vector2(8.0, 8.0))
	var count := maxi(1, int(zone_data.get("count", 6)))
	var seed := int(zone_data.get("seed", 1))
	var scale_min := maxf(0.2, float(zone_data.get("scale_min", 0.8)))
	var scale_max := maxf(scale_min, float(zone_data.get("scale_max", 1.35)))
	var scale_multiplier := maxf(0.1, float(zone_data.get("scale_multiplier", 2.35)))
	for index in range(count):
		var angle := deg_to_rad(fmod(float(seed * 47 + index * 137), 360.0))
		var radial := sqrt(fmod(float(seed * 29 + index * 71), 101.0) / 100.0)
		var position := centre + Vector3(cos(angle) * radius.x * radial, 0.0, sin(angle) * radius.y * radial)
		var scale_value := lerpf(scale_min, scale_max, fmod(float(seed * 13 + index * 43), 97.0) / 96.0) * scale_multiplier
		var asset_key := str(assets[(seed + index * 3) % assets.size()])
		create_feature(parent, {
			"asset": asset_key,
			"position": position,
			"scale": Vector3.ONE * scale_value,
			"yaw": fmod(float(seed * 31 + index * 83), 360.0),
			"fog_sensitive": true,
		})


static func _build_rock_barrier(root: Node3D, size: Vector3, flipped: bool) -> void:
	var long_axis_x := size.x >= size.z
	var extent := maxf(size.x, size.z)
	var cross_extent := maxf(1.8, minf(size.x, size.z))
	var rock_scale := clampf(cross_extent * 0.92, 1.7, 2.8)
	var count := clampi(int(ceil(extent / (rock_scale * 0.86))), 2, 7)
	for index in range(count):
		var along := (float(index) - float(count - 1) * 0.5) * rock_scale * 0.74
		var side_pattern := [-0.23, 0.16, -0.04, 0.25]
		var side := float(side_pattern[index % side_pattern.size()]) * cross_extent
		var offset := Vector3(along, 0.0, side) if long_axis_x else Vector3(side, 0.0, along)
		var rock_key := "terrain_rock_a" if index % 2 == 0 else "terrain_rock_b"
		var variation := 0.9 + float(index % 3) * 0.1
		var y_offset := 0.08 + float(index % 2) * 0.12
		_attach_piece(root, rock_key, offset + Vector3(0.0, y_offset, 0.0), Vector3.ONE * rock_scale * variation, float((index * 71 + (180 if flipped else 0)) % 360))


static func _build_debris(root: Node3D, size: Vector3) -> void:
	var crater_scale := maxf(2.2, minf(size.x, size.z) * 0.9)
	_attach_piece(root, "terrain_crater", Vector3.ZERO, Vector3.ONE * crater_scale, 0.0)
	_build_loose_rocks(root, size, 0.82)


static func _build_loose_rocks(root: Node3D, size: Vector3, scale_multiplier := 1.0) -> void:
	var long_axis_x := size.x >= size.z
	var extent := maxf(size.x, size.z)
	var cross_extent := maxf(1.5, minf(size.x, size.z))
	var count := clampi(int(ceil(extent / 3.5)), 2, 6)
	for index in range(count):
		var along := (float(index) - float(count - 1) * 0.5) * extent / float(count)
		var side := (0.24 if index % 2 == 0 else -0.24) * cross_extent
		var offset := Vector3(along, 0.0, side) if long_axis_x else Vector3(side, 0.0, along)
		var asset_key := "terrain_rock_a" if index % 2 == 0 else "terrain_rock_b"
		var scale_value := minf(2.6, maxf(1.15, cross_extent * 0.58)) * scale_multiplier
		_attach_piece(root, asset_key, offset, Vector3.ONE * scale_value, float(index * 83 % 360))


static func _build_tower_outcrop(root: Node3D, size: Vector3) -> void:
	# The previous industrial tower export read as an unrelated floating
	# building. Use the same readable rock language as the other outcrops.
	var foundation := clampf(minf(size.x, size.z) * 0.82, 2.0, 3.0)
	_attach_piece(root, "terrain_rock_a", Vector3(-0.32, 0.0, 0.0), Vector3.ONE * foundation, 24.0)
	_attach_piece(root, "terrain_rock_b", Vector3(0.38, 0.08, 0.28), Vector3.ONE * foundation * 0.78, 142.0)
	_build_loose_rocks(root, size, 0.56)


static func _build_station_outpost(root: Node3D, size: Vector3, flipped: bool) -> void:
	var yaw := 180.0 if flipped else 0.0
	_build_rock_barrier(root, size, flipped)
	var segment_scale := clampf(minf(size.x, size.z) * 0.58, 1.5, 2.0)
	var long_axis_x := size.x >= size.z
	var segment_count := clampi(int(floor(maxf(size.x, size.z) / (segment_scale * 4.0))), 2, 3)
	for index in range(segment_count):
		var along := (float(index) - float(segment_count - 1) * 0.5) * segment_scale * 1.8
		var offset := Vector3(along, 0.46, 0.0) if long_axis_x else Vector3(0.0, 0.46, along)
		_attach_piece(root, "industrial_platform", offset, Vector3.ONE * segment_scale, yaw + (90.0 if not long_axis_x else 0.0))
	_attach_piece(root, "industrial_train", Vector3(0.0, 0.78, 0.0), Vector3.ONE * segment_scale * 0.82, yaw + (90.0 if long_axis_x else 0.0))
	var support_offset := Vector3(-segment_scale * 1.25, 0.52, 0.0) if long_axis_x else Vector3(0.0, 0.52, -segment_scale * 1.25)
	_attach_piece(root, "industrial_support", support_offset, Vector3.ONE * segment_scale * 0.76, yaw)


static func _attach_piece(root: Node3D, asset_key: String, offset: Vector3, display_scale: Vector3, yaw_degrees: float) -> void:
	var pivot := Node3D.new()
	pivot.position = offset
	pivot.rotation_degrees.y = yaw_degrees
	pivot.set_meta("terrain_asset", asset_key)
	pivot.set_meta("terrain_scale", display_scale)
	root.add_child(pivot)
	var visual := AssetLibraryScript.attach_asset(pivot, asset_key, "neutral")
	if visual == null:
		pivot.queue_free()
		return
	var bounds := _node_bounds(visual, Transform3D.IDENTITY, AABB())
	visual.scale *= display_scale
	visual.position = Vector3(
		-(bounds.position.x + bounds.size.x * 0.5) * display_scale.x,
		-bounds.position.y * display_scale.y,
		-(bounds.position.z + bounds.size.z * 0.5) * display_scale.z
	)


static func _add_collision(root: Node3D, size: Vector3) -> void:
	if size.x <= 0.0 or size.z <= 0.0:
		return
	var body := StaticBody3D.new()
	body.name = "TerrainCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size.x, maxf(0.1, size.y), size.z)
	shape.shape = box
	shape.position.y = maxf(0.0, size.y * 0.5)
	body.add_child(shape)
	root.add_child(body)


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


static func _vector3(value: Variant, fallback := Vector3.ZERO) -> Vector3:
	if value is Vector3:
		return value
	if value is Dictionary:
		return Vector3(float(value.get("x", fallback.x)), float(value.get("y", fallback.y)), float(value.get("z", fallback.z)))
	return fallback


static func _vector2(value: Variant, fallback := Vector2.ZERO) -> Vector2:
	if value is Vector2:
		return value
	if value is Dictionary:
		return Vector2(float(value.get("x", fallback.x)), float(value.get("y", fallback.y)))
	return fallback


static func _material(color: Color) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	if color.a < 0.99:
		result.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	result.roughness = 0.72
	result.metallic = 0.08
	return result
