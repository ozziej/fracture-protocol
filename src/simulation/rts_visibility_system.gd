class_name RtsVisibilitySystem
extends RefCounted

## Owns current vision and explored-map state for both teams. Presentation asks
## this service for a filtered snapshot; it never infers visibility itself.
var simulation
var cache_tick := -1
var cache: Dictionary = {}
var observer_cache: Dictionary = {}
var explored_cells: Dictionary = {"player": {}, "enemy": {}}


func _init(owner) -> void:
	simulation = owner


func reset() -> void:
	cache_tick = -1
	cache.clear()
	observer_cache.clear()
	explored_cells = {"player": {}, "enemy": {}}


func invalidate() -> void:
	cache_tick = -1
	observer_cache.clear()


func refresh() -> void:
	cache_tick = -1
	_ensure_cache()


func get_state(team: String) -> Dictionary:
	_ensure_cache()
	return cache.get(team, _empty_state()).duplicate(true)


func is_entity_visible_to_team(team: String, entity_id: String) -> bool:
	if simulation.units.has(entity_id):
		var unit: Dictionary = simulation.units[entity_id]
		if str(unit.get("team", "")) == team:
			return true
		return is_position_visible_to_team(team, unit["position"])
	if simulation.buildings.has(entity_id):
		var building: Dictionary = simulation.buildings[entity_id]
		if str(building.get("team", "")) == team:
			return true
		return is_position_visible_to_team(team, building["position"])
	return false


func is_position_visible_to_team(team: String, position: Vector3) -> bool:
	for observer in _observers_for_team(team):
		if position.distance_to(observer["position"]) <= float(observer["radius"]):
			return true
	return false


func is_position_explored_by_team(team: String, position: Vector3) -> bool:
	if is_position_visible_to_team(team, position):
		return true
	_ensure_cache()
	var team_cells: Dictionary = explored_cells.get(team, {})
	return team_cells.has(_cell_key_for_position(position))


func visible_entities(entities: Dictionary, team: String, visible_ids: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for entity_id in entities:
		var entity: Dictionary = entities[entity_id]
		if str(entity.get("team", "")) == team or bool(visible_ids.get(entity_id, false)):
			result[entity_id] = entity
	return result


func add_visibility_state_to_markers(markers: Dictionary, team: String) -> Dictionary:
	var result: Dictionary = {}
	for marker_id in markers:
		var marker: Dictionary = markers[marker_id].duplicate(true)
		marker["visibility_state"] = visibility_state_at_position(team, marker["position"])
		result[marker_id] = marker
	return result


func visibility_state_at_position(team: String, position: Vector3) -> String:
	if is_position_visible_to_team(team, position):
		return "visible"
	if is_position_explored_by_team(team, position):
		return "explored"
	return "hidden"


func _ensure_cache() -> void:
	if cache_tick == int(simulation.current_tick):
		return
	cache.clear()
	for team in ["player", "enemy"]:
		cache[team] = _build_team_state(team)
	cache_tick = int(simulation.current_tick)


func _build_team_state(team: String) -> Dictionary:
	var observers: Array = _observers_for_team(team)
	var visible_units: Dictionary = {}
	var visible_buildings: Dictionary = {}
	for entity_id in simulation.units:
		var unit: Dictionary = simulation.units[entity_id]
		if str(unit.get("team", "")) == team or _position_visible_from_observers(unit["position"], observers):
			visible_units[entity_id] = true
	for entity_id in simulation.buildings:
		var building: Dictionary = simulation.buildings[entity_id]
		if str(building.get("team", "")) == team or _position_visible_from_observers(building["position"], observers):
			visible_buildings[entity_id] = true

	var hidden_cells := PackedVector3Array()
	var explored_cells_for_render := PackedVector3Array()
	var visible_cells := PackedVector3Array()
	var team_explored: Dictionary = explored_cells.get(team, {})
	var tile_size: float = max(2.0, float(simulation.level_rules.get("fog_tile_size", 8.0)))
	var bounds: Vector2 = simulation.get_level_bounds()
	var columns: int = int(ceil(bounds.x * 2.0 / tile_size))
	var rows: int = int(ceil(bounds.y * 2.0 / tile_size))
	var visible_cell_keys: Dictionary = {}
	for observer in observers:
		var observer_position: Vector3 = observer["position"]
		var reveal_radius: float = float(observer["radius"]) + tile_size * 0.75
		var min_x_index: int = clamp(int(floor((observer_position.x - reveal_radius + bounds.x) / tile_size)), 0, columns - 1)
		var max_x_index: int = clamp(int(floor((observer_position.x + reveal_radius + bounds.x) / tile_size)), 0, columns - 1)
		var min_z_index: int = clamp(int(floor((observer_position.z - reveal_radius + bounds.y) / tile_size)), 0, rows - 1)
		var max_z_index: int = clamp(int(floor((observer_position.z + reveal_radius + bounds.y) / tile_size)), 0, rows - 1)
		for x_index in range(min_x_index, max_x_index + 1):
			var center_x: float = -bounds.x + (float(x_index) + 0.5) * tile_size
			for z_index in range(min_z_index, max_z_index + 1):
				var center_z: float = -bounds.y + (float(z_index) + 0.5) * tile_size
				var center := Vector3(center_x, 0.0, center_z)
				if center.distance_to(observer_position) <= reveal_radius:
					visible_cell_keys[_cell_key(x_index, z_index)] = true
	for x_index in range(columns):
		var center_x: float = -bounds.x + (float(x_index) + 0.5) * tile_size
		if center_x > bounds.x:
			continue
		for z_index in range(rows):
			var center_z: float = -bounds.y + (float(z_index) + 0.5) * tile_size
			if center_z > bounds.y:
				continue
			var center := Vector3(center_x, 0.0, center_z)
			var key := _cell_key(x_index, z_index)
			if visible_cell_keys.has(key):
				team_explored[key] = true
				visible_cells.append(center)
			elif team_explored.has(key):
				explored_cells_for_render.append(center)
			else:
				hidden_cells.append(center)
	explored_cells[team] = team_explored
	return {
		"visible_units": visible_units,
		"visible_buildings": visible_buildings,
		"hidden_cells": hidden_cells,
		"explored_cells": explored_cells_for_render,
		"visible_cells": visible_cells,
		"tile_size": tile_size,
	}


func _observers_for_team(team: String) -> Array:
	if observer_cache.has(team):
		return observer_cache[team]
	var observers: Array = []
	for entity_id in simulation.units:
		var unit: Dictionary = simulation.units[entity_id]
		if str(unit.get("team", "")) != team or float(unit.get("health", 0.0)) <= 0.0:
			continue
		var radius: float = float(unit.get("vision_range", 0.0))
		if radius <= 0.0 and simulation.unit_definitions.has(str(unit.get("kind", ""))):
			radius = float(simulation.unit_definitions[str(unit["kind"])].vision_range)
		observers.append({"position": unit["position"], "radius": radius})
	for entity_id in simulation.buildings:
		var building: Dictionary = simulation.buildings[entity_id]
		if str(building.get("team", "")) != team or not bool(building.get("complete", false)) or float(building.get("health", 0.0)) <= 0.0:
			continue
		var building_radius: float = float(building.get("vision_range", 0.0))
		if building_radius <= 0.0 and simulation.building_definitions.has(str(building.get("kind", ""))):
			building_radius = float(simulation.building_definitions[str(building["kind"])].vision_range)
		observers.append({"position": building["position"], "radius": building_radius})
	observer_cache[team] = observers
	return observers


func _position_visible_from_observers(position: Vector3, observers: Array) -> bool:
	for observer in observers:
		if position.distance_to(observer["position"]) <= float(observer["radius"]):
			return true
	return false


func _cell_key_for_position(position: Vector3) -> String:
	var tile_size: float = max(2.0, float(simulation.level_rules.get("fog_tile_size", 8.0)))
	var bounds: Vector2 = simulation.get_level_bounds()
	var x_index: int = int(floor((position.x + bounds.x) / tile_size))
	var z_index: int = int(floor((position.z + bounds.y) / tile_size))
	return _cell_key(x_index, z_index)


func _cell_key(x_index: int, z_index: int) -> String:
	return "%d:%d" % [x_index, z_index]


func _empty_state() -> Dictionary:
	return {
		"visible_units": {},
		"visible_buildings": {},
		"hidden_cells": PackedVector3Array(),
		"explored_cells": PackedVector3Array(),
		"visible_cells": PackedVector3Array(),
		"tile_size": 8.0,
	}
