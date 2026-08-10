class_name RtsMinimap
extends Control

var snapshot: Dictionary = {}
var map_bounds := Rect2(-60.0, -40.0, 120.0, 80.0)


func set_snapshot(next_snapshot: Dictionary) -> void:
	snapshot = next_snapshot
	queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var outer := Rect2(Vector2.ZERO, size)
	draw_rect(outer, Color(0.025, 0.055, 0.09, 0.95), true)
	draw_rect(outer, Color(0.22, 0.72, 0.82, 0.65), false, 2.0)
	var map_rect := Rect2(10.0, 22.0, size.x - 20.0, size.y - 32.0)
	draw_rect(map_rect, Color(0.06, 0.13, 0.16, 1.0), true)
	draw_line(Vector2(map_rect.position.x, map_rect.get_center().y), Vector2(map_rect.end.x, map_rect.get_center().y), Color(0.15, 0.3, 0.32, 0.5), 1.0)
	draw_line(Vector2(map_rect.get_center().x, map_rect.position.y), Vector2(map_rect.get_center().x, map_rect.end.y), Color(0.15, 0.3, 0.32, 0.5), 1.0)
	draw_string(ThemeDB.fallback_font, Vector2(10.0, 16.0), "TACTICAL MAP", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.61, 0.87, 0.91, 1.0))

	if snapshot.is_empty():
		return
	for resource_id in snapshot.get("resource_nodes", {}):
		var resource: Dictionary = snapshot["resource_nodes"][resource_id]
		draw_circle(_map_point(resource["position"], map_rect), 4.0, Color(0.98, 0.77, 0.28, 1.0))
	for point_id in snapshot.get("control_points", {}):
		var point: Dictionary = snapshot["control_points"][point_id]
		var point_color := Color(0.7, 0.75, 0.78, 1.0)
		if point["owner"] == "player":
			point_color = Color(0.18, 0.82, 0.93, 1.0)
		elif point["owner"] == "enemy":
			point_color = Color(0.95, 0.28, 0.37, 1.0)
		var point_position := _map_point(point["position"], map_rect)
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
	for building_id in snapshot.get("buildings", {}):
		var building: Dictionary = snapshot["buildings"][building_id]
		var building_color := Color(0.18, 0.82, 0.93, 1.0) if building["team"] == "player" else Color(0.95, 0.28, 0.37, 1.0)
		draw_rect(Rect2(_map_point(building["position"], map_rect) - Vector2(3.0, 3.0), Vector2(6.0, 6.0)), building_color, true)
	for unit_id in snapshot.get("units", {}):
		var unit: Dictionary = snapshot["units"][unit_id]
		var unit_color := Color(0.55, 0.95, 1.0, 1.0) if unit["team"] == "player" else Color(1.0, 0.45, 0.5, 1.0)
		draw_circle(_map_point(unit["position"], map_rect), 2.0, unit_color)


func _map_point(world_position: Vector3, map_rect: Rect2) -> Vector2:
	var x_ratio := inverse_lerp(map_bounds.position.x, map_bounds.end.x, world_position.x)
	var z_ratio := inverse_lerp(map_bounds.position.y, map_bounds.end.y, world_position.z)
	return Vector2(map_rect.position.x + x_ratio * map_rect.size.x, map_rect.position.y + z_ratio * map_rect.size.y)
