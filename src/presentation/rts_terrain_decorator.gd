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
	for set_piece_data in terrain.get("industrial_set_pieces", []):
		create_industrial_set_piece(parent, set_piece_data)
	for obstacle_data in terrain.get("obstacles", []):
		var obstacle: Dictionary = obstacle_data
		create_obstacle(
			parent,
			_vector3(obstacle.get("position", {})),
			_vector3(obstacle.get("size", {}), Vector3(2.0, 1.0, 2.0)),
			str(obstacle.get("kind", "mesa"))
		)


static func create_industrial_set_piece(parent: Node3D, set_piece_data: Dictionary) -> Node3D:
	var set_piece_id := str(set_piece_data.get("id", "relay_corridor_set_piece"))
	var root := Node3D.new()
	root.name = "AuthoredSetPiece_%s" % set_piece_id
	root.position = _vector3(set_piece_data.get("position", {}))
	root.set_meta("fog_sensitive_scenery", bool(set_piece_data.get("fog_sensitive", true)))
	root.set_meta("terrain_set_piece", set_piece_id)
	parent.add_child(root)
	var base_scale := maxf(0.25, float(set_piece_data.get("scale", 1.0)))
	_attach_piece(root, str(set_piece_data.get("platform_asset", "industrial_platform")), Vector3.ZERO, Vector3.ONE * base_scale, float(set_piece_data.get("yaw", 0.0)))
	var tower_offset := _vector3(set_piece_data.get("tower_offset", {"x": 0.0, "y": 0.7, "z": -1.9}))
	_attach_piece(root, str(set_piece_data.get("tower_asset", "industrial_tower")), tower_offset, Vector3.ONE * base_scale * 0.72, float(set_piece_data.get("yaw", 0.0)) + 90.0)
	var support_offset := _vector3(set_piece_data.get("support_offset", {"x": -2.0, "y": 0.52, "z": 0.0}))
	_attach_piece(root, str(set_piece_data.get("support_asset", "industrial_support")), support_offset, Vector3.ONE * base_scale * 0.68, float(set_piece_data.get("yaw", 0.0)))
	var train_offset := _vector3(set_piece_data.get("train_offset", {"x": 1.9, "y": 0.55, "z": 0.0}))
	_attach_piece(root, str(set_piece_data.get("train_asset", "industrial_train")), train_offset, Vector3.ONE * base_scale * 0.58, float(set_piece_data.get("yaw", 0.0)) + 90.0)
	return root


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
	var base_name := "TerrainObstacle_%s" % kind
	root.name = base_name
	if parent.find_child(base_name, false, false) != null:
		root.name = "%s_%02d" % [base_name, parent.get_child_count()]
	root.position = Vector3(position.x, 0.0, position.z)
	root.set_meta("fog_sensitive_scenery", true)
	parent.add_child(root)
	if kind.contains("tower"):
		_build_tower_outcrop(root, size)
	elif kind.contains("block"):
		_build_station_outpost(root, size, kind.contains("south"))
	elif kind == "debris":
		_build_debris(root, size)
	elif kind.contains("mountain_wall"):
		_build_mountain_wall(root, size, kind.contains("lower"))
	else:
		_build_rock_barrier(root, size, kind.contains("lower"))
	_add_collision(root, size)
	return root


static func create_route_corridors(parent: Node3D, routes: Array) -> void:
	var route_connections: Dictionary = {}
	for route_value in routes:
		_register_route_connections(route_connections, route_value)
	parent.set_meta("route_connection_map", route_connections)
	parent.set_meta("route_tile_occupancy", {})
	for route_value in routes:
		_create_route_corridor(parent, route_value, route_connections)


static func create_route_corridor(parent: Node3D, route_data: Dictionary) -> Node3D:
	# Keep the single-route entry point for callers outside the campaign world
	# builder. Campaign maps use create_route_corridors so shared junctions are
	# resolved from every route before any tile is instantiated.
	var route_connections: Dictionary = parent.get_meta("route_connection_map", {})
	if route_connections.is_empty():
		_register_route_connections(route_connections, route_data)
		parent.set_meta("route_connection_map", route_connections)
	return _create_route_corridor(parent, route_data, route_connections)


static func _create_route_corridor(parent: Node3D, route_data: Dictionary, route_connections: Dictionary) -> Node3D:
	var route_id := str(route_data.get("id", "route"))
	var waypoints: Array = route_data.get("waypoints", [])
	if waypoints.size() < 2:
		return Node3D.new()
	var root := Node3D.new()
	root.name = "AuthoredRoute_%s" % route_id
	root.set_meta("terrain_route", route_id)
	parent.add_child(root)
	var authored_points: Array = []
	for waypoint_value in waypoints:
		_append_route_point(authored_points, _vector3(waypoint_value))
	var tile_index := 0
	for waypoint_index in range(authored_points.size() - 1):
		var start: Vector3 = authored_points[waypoint_index]
		var finish: Vector3 = authored_points[waypoint_index + 1]
		var direction := _route_cardinal_direction(start, finish)
		if direction == Vector2i.ZERO:
			continue
		var distance := absf(finish.x - start.x) + absf(finish.z - start.z)
		# Distribute a whole number of tiles over the authored segment. Fixed
		# four-unit stepping leaves a visible gap whenever a segment (such as the
		# 30-unit deployment spur) is not exactly divisible by the GLB footprint.
		var tile_count := maxi(1, int(ceil(distance / ROUTE_TILE_SIZE)))
		var tile_spacing := distance / float(tile_count)
		for interior_index in range(1, tile_count):
			var tile_position := start + Vector3(float(direction.x), 0.0, float(direction.y)) * tile_spacing * float(interior_index)
			_attach_route_tile_for_connections(root, tile_position, tile_index, route_connections)
			tile_index += 1

	# Every authored point is resolved against the combined route topology. This
	# means a shared North/South pass branch becomes a real roadSplit tile rather
	# than a corner or straight tile chosen by whichever route rendered first.
	_attach_route_tile_for_connections(root, authored_points[0], tile_index, route_connections)
	tile_index += 1
	for waypoint_index in range(1, authored_points.size() - 1):
		_attach_route_tile_for_connections(root, authored_points[waypoint_index], tile_index, route_connections)
		tile_index += 1
	_attach_route_tile_for_connections(root, authored_points[authored_points.size() - 1], tile_index, route_connections)
	return root


const ROUTE_TILE_SIZE := 4.0


static func _append_route_point(points: Array, point: Vector3) -> void:
	if points.is_empty() or points.back().distance_to(point) > 0.1:
		points.append(point)


static func _route_cardinal_direction(start: Vector3, finish: Vector3) -> Vector2i:
	var delta := finish - start
	if absf(delta.x) >= absf(delta.z) and absf(delta.x) > 0.1:
		return Vector2i(1 if delta.x > 0.0 else -1, 0)
	if absf(delta.z) > 0.1:
		return Vector2i(0, 1 if delta.z > 0.0 else -1)
	return Vector2i.ZERO


static func _route_straight_yaw(direction: Vector2i) -> float:
	# terrain_roadStraight.glb is authored along local Z. Horizontal map roads
	# therefore need the 90 degree turn; vertical roads stay at the source yaw.
	return 90.0 if direction.x != 0 else 0.0


static func _route_end_yaw(direction: Vector2i) -> float:
	# terrain_roadEnd.glb opens toward local -Z. Unlike a straight, its yaw must
	# preserve which end is open; the western route start therefore needs 270°
	# so that the road continues east into the map.
	if direction == Vector2i(0, -1):
		return 0.0
	if direction == Vector2i(-1, 0):
		return 90.0
	if direction == Vector2i(0, 1):
		return 180.0
	return 270.0


static func _route_corner_yaw(incoming: Vector2i, outgoing: Vector2i) -> float:
	var connection_a := -incoming
	var connection_b := outgoing
	if _same_connections(connection_a, connection_b, Vector2i(-1, 0), Vector2i(0, -1)):
		return 0.0
	if _same_connections(connection_a, connection_b, Vector2i(0, 1), Vector2i(-1, 0)):
		return 90.0
	if _same_connections(connection_a, connection_b, Vector2i(1, 0), Vector2i(0, 1)):
		return 180.0
	return 270.0


static func _same_connections(first: Vector2i, second: Vector2i, expected_first: Vector2i, expected_second: Vector2i) -> bool:
	return (first == expected_first and second == expected_second) or (first == expected_second and second == expected_first)


static func _register_route_connections(connection_map: Dictionary, route_data: Dictionary) -> void:
	var authored_points: Array = []
	for waypoint_value in route_data.get("waypoints", []):
		_append_route_point(authored_points, _vector3(waypoint_value))
	for waypoint_index in range(authored_points.size() - 1):
		var start: Vector3 = authored_points[waypoint_index]
		var finish: Vector3 = authored_points[waypoint_index + 1]
		var direction := _route_cardinal_direction(start, finish)
		if direction == Vector2i.ZERO:
			continue
		var distance := absf(finish.x - start.x) + absf(finish.z - start.z)
		var tile_count := maxi(1, int(ceil(distance / ROUTE_TILE_SIZE)))
		var tile_spacing := distance / float(tile_count)
		_register_route_connection(connection_map, start, direction)
		_register_route_connection(connection_map, finish, -direction)
		for interior_index in range(1, tile_count):
			var tile_position := start + Vector3(float(direction.x), 0.0, float(direction.y)) * tile_spacing * float(interior_index)
			_register_route_connection(connection_map, tile_position, direction)
			_register_route_connection(connection_map, tile_position, -direction)


static func _register_route_connection(connection_map: Dictionary, position: Vector3, direction: Vector2i) -> void:
	var tile_key := _route_tile_key(position)
	var connections: Array = connection_map.get(tile_key, [])
	var connection_token := _route_direction_token(direction)
	if not connections.has(connection_token):
		connections.append(connection_token)
	connection_map[tile_key] = connections


static func _route_tile_key(position: Vector3) -> String:
	# Preserve the evenly distributed sub-four-unit positions while still
	# coalescing exact shared route endpoints into one junction tile.
	return "%d:%d" % [int(round(position.x * 100.0)), int(round(position.z * 100.0))]


static func _route_direction_token(direction: Vector2i) -> String:
	return "%d:%d" % [direction.x, direction.y]


static func _route_direction_from_token(token: String) -> Vector2i:
	var values := token.split(":")
	if values.size() != 2:
		return Vector2i.ZERO
	return Vector2i(int(values[0]), int(values[1]))


static func _route_tile_descriptor(position: Vector3, connection_map: Dictionary) -> Dictionary:
	var directions: Array[Vector2i] = []
	for token_value in connection_map.get(_route_tile_key(position), []):
		var direction := _route_direction_from_token(str(token_value))
		if direction != Vector2i.ZERO:
			directions.append(direction)
	if directions.size() >= 4:
		return {"asset": "terrain_road_cross", "yaw": 0.0}
	if directions.size() == 3:
		return {"asset": "terrain_road_split", "yaw": _route_split_yaw(directions)}
	if directions.size() == 2:
		if directions[0] == -directions[1]:
			return {"asset": "terrain_road_straight", "yaw": _route_straight_yaw(directions[0])}
		return {"asset": "terrain_road_corner", "yaw": _route_corner_yaw(-directions[0], directions[1])}
	if directions.size() == 1:
		return {"asset": "terrain_road_end", "yaw": _route_end_yaw(directions[0])}
	return {"asset": "terrain_road_straight", "yaw": 0.0}


static func _route_split_yaw(directions: Array[Vector2i]) -> float:
	# terrain_roadSplit.glb is a west/east/south T at its source yaw.
	if _contains_directions(directions, [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1)]):
		return 0.0
	if _contains_directions(directions, [Vector2i(0, -1), Vector2i(0, 1), Vector2i(1, 0)]):
		return 90.0
	if _contains_directions(directions, [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1)]):
		return 180.0
	return 270.0


static func _contains_directions(actual: Array[Vector2i], expected: Array[Vector2i]) -> bool:
	for direction in expected:
		if not actual.has(direction):
			return false
	return true


static func _attach_route_tile_for_connections(parent: Node3D, position: Vector3, tile_index: int, connection_map: Dictionary) -> void:
	var descriptor := _route_tile_descriptor(position, connection_map)
	_attach_route_tile(parent, str(descriptor.get("asset", "terrain_road_straight")), position, float(descriptor.get("yaw", 0.0)), tile_index)


static func _attach_route_tile(parent: Node3D, asset_key: String, position: Vector3, yaw_degrees: float, tile_index: int) -> void:
	var route_owner := parent.get_parent()
	var tile_key := _route_tile_key(position)
	var occupied: Dictionary = route_owner.get_meta("route_tile_occupancy", {}) if route_owner else {}
	if occupied.has(tile_key):
		return
	var pivot := Node3D.new()
	pivot.name = "RouteTile_%03d_%s" % [tile_index, asset_key]
	pivot.position = position + Vector3.UP * 0.035
	pivot.set_meta("terrain_asset", asset_key)
	parent.add_child(pivot)
	var visual := AssetLibraryScript.attach_asset(pivot, asset_key, "neutral")
	if visual == null:
		pivot.queue_free()
		return
	occupied[tile_key] = true
	if route_owner:
		route_owner.set_meta("route_tile_occupancy", occupied)
	visual.position = Vector3.ZERO
	visual.rotation_degrees.y = yaw_degrees
	visual.scale = Vector3.ONE * ROUTE_TILE_SIZE
	var bounds := _node_bounds(visual, Transform3D.IDENTITY, AABB())
	if bounds.size != Vector3.ZERO:
		visual.position = Vector3(-bounds.get_center().x, -bounds.position.y, -bounds.get_center().z)


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


static func _build_mountain_wall(root: Node3D, size: Vector3, flipped: bool) -> void:
	# Mountain walls reuse the large established scenery-rock GLBs. The smaller
	# Kenney terrain rocks remain useful for loose dressing, but they do not read
	# as a valley wall at this map scale. The simulation owns the full collision.
	var long_axis_x := size.x >= size.z
	var extent := maxf(size.x, size.z)
	var cross_extent := maxf(2.0, minf(size.x, size.z))
	var count := clampi(int(ceil(extent / 7.2)), 10, 16)
	var rock_scale := clampf(cross_extent / 11.0, 1.0, 1.35)
	var row_offsets := [-0.24, 0.24]
	var row_scales := [1.0, 0.9]
	for index in range(count):
		var base_along := (float(index) / float(maxi(1, count - 1)) - 0.5) * extent * 0.98
		for row in range(row_offsets.size()):
			var along := base_along
			var side := float(row_offsets[row]) * cross_extent
			var jitter := float((index % 3) - 1) * cross_extent * 0.055
			if long_axis_x:
				side += jitter
			else:
				along += jitter
			var offset := Vector3(along, 0.08 + float((index + row) % 2) * 0.22, side) if long_axis_x else Vector3(side, 0.08 + float((index + row) % 2) * 0.22, along)
			var rock_key := "scenery_rock_a" if (index + row) % 2 == 0 else "scenery_rock_b"
			var variation := 0.92 + float((index + row) % 3) * 0.08
			var piece_scale := rock_scale * float(row_scales[row]) * variation
			_attach_piece(
				root,
				rock_key,
				offset,
				Vector3(piece_scale, piece_scale * 1.28, piece_scale),
				float((index * 71 + row * 43 + (180 if flipped else 0)) % 360)
			)


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
	# Kenney GLBs carry an authored root offset. Center the scaled mesh itself
	# around the authored pivot so the visible rock occupies the same footprint
	# as the simulation collision placed on the obstacle root.
	visual.position = Vector3.ZERO
	visual.scale = AssetLibraryScript.scale_for(asset_key) * display_scale
	var bounds := _node_bounds(visual, Transform3D.IDENTITY, AABB())
	if bounds.size != Vector3.ZERO:
		visual.position = -bounds.get_center()


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
