class_name RtsMinimap
extends Control

signal world_position_clicked(world_position: Vector3)

const OBJECTIVE_HIGHLIGHT_RADIUS := 12.0

var snapshot: Dictionary = {}
var map_bounds := Rect2(-60.0, -40.0, 120.0, 80.0)
var selected_ids: Array = []
var selected_resource_id := ""
var objective_target_point_id := ""
var objective_target_point_ids: Array = []
var camera_center := Vector3.ZERO
var camera_half_extents := Vector2(18.0, 12.0)


func set_snapshot(next_snapshot: Dictionary) -> void:
	snapshot = next_snapshot
	queue_redraw()


func set_selection(next_selected_ids: Array, next_selected_resource_id: String, next_objective_target_point_id: Variant) -> void:
	selected_ids = next_selected_ids.duplicate()
	selected_resource_id = next_selected_resource_id
	if next_objective_target_point_id is Array:
		objective_target_point_ids = next_objective_target_point_id.duplicate()
	else:
		objective_target_point_ids = [] if str(next_objective_target_point_id).is_empty() else [str(next_objective_target_point_id)]
	objective_target_point_id = str(objective_target_point_ids[0]) if not objective_target_point_ids.is_empty() else ""
	queue_redraw()


func set_camera_view(center: Vector3, camera_distance: float) -> void:
	camera_center = center
	# This is intentionally an authored tactical approximation rather than a
	# second camera render. It keeps the viewport readable while remaining cheap.
	camera_half_extents = Vector2(max(10.0, camera_distance * 0.95), max(7.0, camera_distance * 0.62))
	queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var map_rect := _map_rect()
		if map_rect.has_point(event.position):
			world_position_clicked.emit(_world_point(event.position, map_rect))
			accept_event()


func _draw() -> void:
	var outer := Rect2(Vector2.ZERO, size)
	draw_rect(outer, Color(0.025, 0.055, 0.09, 0.95), true)
	draw_rect(outer, Color(0.22, 0.72, 0.82, 0.65), false, 2.0)
	var map_rect := _map_rect()
	draw_rect(map_rect, Color(0.06, 0.13, 0.16, 1.0), true)
	draw_line(Vector2(map_rect.position.x, map_rect.get_center().y), Vector2(map_rect.end.x, map_rect.get_center().y), Color(0.15, 0.3, 0.32, 0.5), 1.0)
	draw_line(Vector2(map_rect.get_center().x, map_rect.position.y), Vector2(map_rect.get_center().x, map_rect.end.y), Color(0.15, 0.3, 0.32, 0.5), 1.0)
	draw_string(ThemeDB.fallback_font, Vector2(10.0, 16.0), "TACTICAL MAP", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.61, 0.87, 0.91, 1.0))
	if not objective_target_point_ids.is_empty():
		draw_string(ThemeDB.fallback_font, Vector2(max(96.0, size.x - 96.0), 16.0), "OBJECTIVES", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#ffd36a"))

	if snapshot.is_empty():
		return
	_draw_fog_overlay(map_rect)
	for resource_id in snapshot.get("resource_nodes", {}):
		var resource: Dictionary = snapshot["resource_nodes"][resource_id]
		if str(resource.get("visibility_state", "visible")) == "hidden":
			continue
		var resource_position := _map_point(resource["position"], map_rect)
		var depleted := bool(resource.get("depleted", false))
		var resource_color := Color(0.35, 0.35, 0.3, 1.0) if depleted else Color(0.98, 0.77, 0.28, 1.0)
		draw_circle(resource_position, 4.0, resource_color)
		if str(resource_id) == selected_resource_id:
			draw_arc(resource_position, 7.0, 0.0, TAU, 18, Color("#fff0a4"), 1.8)
	for point_id in snapshot.get("control_points", {}):
		var point: Dictionary = snapshot["control_points"][point_id]
		var is_objective := str(point_id) in objective_target_point_ids
		if str(point.get("visibility_state", "visible")) == "hidden" and not is_objective:
			continue
		var point_color := Color(0.7, 0.75, 0.78, 1.0)
		if point["owner"] == "player":
			point_color = Color(0.18, 0.82, 0.93, 1.0)
		elif point["owner"] == "enemy":
			point_color = Color(0.95, 0.28, 0.37, 1.0)
		var point_position := _map_point(point["position"], map_rect)
		var objective_halo_radius := 0.0
		if is_objective:
			var pulse := 0.5 + sin(float(Time.get_ticks_msec()) * 0.004) * 0.5
			objective_halo_radius = OBJECTIVE_HIGHLIGHT_RADIUS + pulse * 2.0
			draw_circle(point_position, objective_halo_radius, Color(1.0, 0.78, 0.22, 0.12), true)
			draw_arc(point_position, objective_halo_radius, 0.0, TAU, 32, Color("#ffd36a"), 2.8)
		if str(point.get("strategic_role", "")) == "network_hub":
			var diamond := PackedVector2Array([
				point_position + Vector2(0.0, -5.0),
				point_position + Vector2(5.0, 0.0),
				point_position + Vector2(0.0, 5.0),
				point_position + Vector2(-5.0, 0.0),
			])
			draw_colored_polygon(diamond, point_color)
		else:
			draw_circle(point_position, 3.0, point_color)
		if bool(point.get("staging_active", false)):
			draw_arc(point_position, 5.5, 0.0, TAU, 20, point_color.lightened(0.25), 1.4)
		if is_objective:
			draw_arc(point_position, objective_halo_radius + 4.0, 0.0, TAU, 32, Color(1.0, 0.78, 0.22, 0.72), 1.4)
			draw_line(point_position + Vector2(-7.0, 0.0), point_position + Vector2(7.0, 0.0), Color("#fff0a4"), 1.2)
			draw_line(point_position + Vector2(0.0, -7.0), point_position + Vector2(0.0, 7.0), Color("#fff0a4"), 1.2)
	for building_id in snapshot.get("buildings", {}):
		var building: Dictionary = snapshot["buildings"][building_id]
		var building_color := Color(0.18, 0.82, 0.93, 1.0) if building["team"] == "player" else Color(0.95, 0.28, 0.37, 1.0)
		draw_rect(Rect2(_map_point(building["position"], map_rect) - Vector2(3.0, 3.0), Vector2(6.0, 6.0)), building_color, true)
	for unit_id in snapshot.get("units", {}):
		var unit: Dictionary = snapshot["units"][unit_id]
		var unit_color := Color(0.55, 0.95, 1.0, 1.0) if unit["team"] == "player" else Color(1.0, 0.45, 0.5, 1.0)
		_draw_unit_marker(_map_point(unit["position"], map_rect), str(unit.get("kind", "")), unit_color)
		if selected_ids.has(unit_id):
			draw_arc(_map_point(unit["position"], map_rect), 4.5, 0.0, TAU, 14, Color("#d9fbff"), 1.2)

	_draw_camera_view(map_rect)


func _map_point(world_position: Vector3, map_rect: Rect2) -> Vector2:
	var x_ratio := inverse_lerp(map_bounds.position.x, map_bounds.end.x, world_position.x)
	var z_ratio := inverse_lerp(map_bounds.position.y, map_bounds.end.y, world_position.z)
	return Vector2(map_rect.position.x + x_ratio * map_rect.size.x, map_rect.position.y + z_ratio * map_rect.size.y)


func _world_point(screen_position: Vector2, map_rect: Rect2) -> Vector3:
	var x_ratio: float = clamp(inverse_lerp(map_rect.position.x, map_rect.end.x, screen_position.x), 0.0, 1.0)
	var z_ratio: float = clamp(inverse_lerp(map_rect.position.y, map_rect.end.y, screen_position.y), 0.0, 1.0)
	return Vector3(lerp(map_bounds.position.x, map_bounds.end.x, x_ratio), 0.0, lerp(map_bounds.position.y, map_bounds.end.y, z_ratio))


func _map_rect() -> Rect2:
	return Rect2(10.0, 22.0, max(20.0, size.x - 20.0), max(20.0, size.y - 32.0))


func _draw_unit_marker(position: Vector2, unit_kind: String, color: Color) -> void:
	match unit_kind:
		"bulwark":
			var diamond := PackedVector2Array([
				position + Vector2(0.0, -3.5),
				position + Vector2(3.5, 0.0),
				position + Vector2(0.0, 3.5),
				position + Vector2(-3.5, 0.0),
			])
			draw_colored_polygon(diamond, color)
		"warden":
			draw_rect(Rect2(position - Vector2(3.0, 3.0), Vector2(6.0, 6.0)), color, true)
		"collector":
			draw_circle(position, 2.7, color)
			draw_circle(position, 4.0, Color(color.r, color.g, color.b, 0.7), false, 1.0)
		_:
			draw_circle(position, 2.0, color)


func _draw_camera_view(map_rect: Rect2) -> void:
	var center := _map_point(camera_center, map_rect)
	var horizontal_scale: float = map_rect.size.x / max(0.1, map_bounds.size.x)
	var vertical_scale: float = map_rect.size.y / max(0.1, map_bounds.size.y)
	var half_size := Vector2(camera_half_extents.x * horizontal_scale, camera_half_extents.y * vertical_scale)
	var corners := PackedVector2Array([
		center + Vector2(-half_size.x, -half_size.y),
		center + Vector2(half_size.x, -half_size.y),
		center + Vector2(half_size.x, half_size.y),
		center + Vector2(-half_size.x, half_size.y),
		center + Vector2(-half_size.x, -half_size.y),
	])
	draw_polyline(corners, Color(0.82, 0.96, 1.0, 0.85), 1.4, true)


func _draw_fog_overlay(map_rect: Rect2) -> void:
	var visibility: Dictionary = snapshot.get("visibility", {})
	if visibility.is_empty():
		return
	var tile_size: float = max(2.0, float(visibility.get("tile_size", 8.0)))
	var cell_size := Vector2(
		tile_size * map_rect.size.x / max(0.1, map_bounds.size.x),
		tile_size * map_rect.size.y / max(0.1, map_bounds.size.y)
	)
	var half_size := cell_size * 0.5
	var explored: PackedVector3Array = visibility.get("explored_cells", PackedVector3Array())
	for center in explored:
		var explored_rect := Rect2(_map_point(center, map_rect) - half_size, cell_size)
		draw_rect(explored_rect, Color(0.02, 0.055, 0.075, 0.42), true)
	var hidden: PackedVector3Array = visibility.get("hidden_cells", PackedVector3Array())
	for center in hidden:
		var hidden_rect := Rect2(_map_point(center, map_rect) - half_size, cell_size)
		draw_rect(hidden_rect, Color(0.008, 0.018, 0.03, 0.86), true)
