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
		return [destination]
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
