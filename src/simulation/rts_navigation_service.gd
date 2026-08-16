class_name RtsNavigationService
extends RefCounted

## Stateless pathfinding seam. The simulation owns map data and state; this
## service owns only the geometry algorithm.

static func build_path(start: Vector3, destination: Vector3, obstacles: Array, path_margin: float, corner_padding: float) -> Array:
	var start_point := Vector2(start.x, start.z)
	var destination_point := Vector2(destination.x, destination.z)
	if segment_clear(start_point, destination_point, obstacles, path_margin):
		return [destination]

	var nodes: Array = [start_point, destination_point]
	for obstacle in obstacles:
		var expanded: Rect2 = obstacle.grow(path_margin)
		nodes.append(expanded.position + Vector2(-corner_padding, -corner_padding))
		nodes.append(Vector2(expanded.end.x + corner_padding, expanded.position.y - corner_padding))
		nodes.append(Vector2(expanded.end.x + corner_padding, expanded.end.y + corner_padding))
		nodes.append(Vector2(expanded.position.x - corner_padding, expanded.end.y + corner_padding))

	var distances: Array = []
	var previous: Array = []
	var visited: Array = []
	for _index in range(nodes.size()):
		distances.append(1.0e20)
		previous.append(-1)
		visited.append(false)
	distances[0] = 0.0

	for _iteration in range(nodes.size()):
		var current := -1
		var current_distance := 1.0e20
		for node_index in range(nodes.size()):
			if not visited[node_index] and distances[node_index] < current_distance:
				current = node_index
				current_distance = distances[node_index]
		if current == -1:
			break
		visited[current] = true
		if current == 1:
			break
		for neighbor in range(nodes.size()):
			if visited[neighbor] or not segment_clear(nodes[current], nodes[neighbor], obstacles, path_margin):
				continue
			var candidate_distance: float = distances[current] + nodes[current].distance_to(nodes[neighbor])
			if candidate_distance < distances[neighbor]:
				distances[neighbor] = candidate_distance
				previous[neighbor] = current

	if previous[1] == -1:
		# An endpoint inside an obstacle, or a genuinely sealed pocket, must not
		# silently become a direct path through the obstacle.
		return []
	var node_path: Array = []
	var cursor := 1
	while cursor != -1:
		node_path.push_front(cursor)
		cursor = previous[cursor]
	var result: Array = []
	for node_index in node_path:
		if node_index == 0:
			continue
		var point: Vector2 = nodes[node_index]
		result.append(Vector3(point.x, 0.0, point.y))
	return result


static func resolve_destination(start: Vector3, destination: Vector3, obstacles: Array, path_margin: float, corner_padding: float) -> Vector3:
	var target := Vector2(destination.x, destination.z)
	if point_clear(target, obstacles, path_margin):
		return destination
	var candidates: Array[Vector2] = []
	for obstacle in obstacles:
		var blocked: Rect2 = obstacle.grow(path_margin)
		if not blocked.has_point(target):
			continue
		var clamped_x := clampf(target.x, blocked.position.x, blocked.end.x)
		var clamped_y := clampf(target.y, blocked.position.y, blocked.end.y)
		candidates.append(Vector2(blocked.position.x - corner_padding, clamped_y))
		candidates.append(Vector2(blocked.end.x + corner_padding, clamped_y))
		candidates.append(Vector2(clamped_x, blocked.position.y - corner_padding))
		candidates.append(Vector2(clamped_x, blocked.end.y + corner_padding))
	var best_point := Vector2(start.x, start.z)
	var best_cost := INF
	for candidate in candidates:
		if not point_clear(candidate, obstacles, path_margin):
			continue
		var candidate_world := Vector3(candidate.x, destination.y, candidate.y)
		var path := build_path(start, candidate_world, obstacles, path_margin, corner_padding)
		if path.is_empty() and Vector2(start.x, start.z).distance_to(candidate) > 0.15:
			continue
		var path_cost := 0.0
		var previous_point := Vector2(start.x, start.z)
		for waypoint_value in path:
			var waypoint: Vector3 = waypoint_value
			var waypoint_point := Vector2(waypoint.x, waypoint.z)
			path_cost += previous_point.distance_to(waypoint_point)
			previous_point = waypoint_point
		# Prefer the closest reachable edge of the clicked solid, while using
		# actual route distance to avoid choosing the far side of a mountain.
		var cost := path_cost + candidate.distance_to(target) * 0.25
		if cost < best_cost:
			best_cost = cost
			best_point = candidate
	return Vector3(best_point.x, destination.y, best_point.y)


static func point_clear(point: Vector2, obstacles: Array, path_margin: float) -> bool:
	for obstacle in obstacles:
		if (obstacle as Rect2).grow(path_margin).has_point(point):
			return false
	return true


static func segment_clear(from_point: Vector2, to_point: Vector2, obstacles: Array, path_margin: float) -> bool:
	for obstacle in obstacles:
		var blocked: Rect2 = obstacle.grow(path_margin)
		if blocked.has_point(from_point) or blocked.has_point(to_point):
			return false
		var corners: Array = [
			blocked.position,
			Vector2(blocked.end.x, blocked.position.y),
			blocked.end,
			Vector2(blocked.position.x, blocked.end.y),
		]
		for edge_index in range(corners.size()):
			var edge_start: Vector2 = corners[edge_index]
			var edge_end: Vector2 = corners[(edge_index + 1) % corners.size()]
			if Geometry2D.segment_intersects_segment(from_point, to_point, edge_start, edge_end) != null:
				return false
	return true
