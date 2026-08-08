class_name RtsSimulation
extends Node

const UnitDefinitionScript = preload("res://src/unit_definition.gd")
const BuildingDefinitionScript = preload("res://src/building_definition.gd")

signal simulation_event(event_type: String, payload: Dictionary)

const TICK_SECONDS := 0.1
const MAX_STEPS_PER_FRAME := 8
const SUPPLY_LINK_RADIUS := 19.0
const SUPPLY_EFFECT_RADIUS := 13.0
const UNSUPPLIED_SPEED_MULTIPLIER := 0.82
const UNSUPPLIED_DAMAGE_MULTIPLIER := 0.7
const NAVIGATION_OBSTACLES := [
	Rect2(-11.0, 14.0, 8.0, 2.0),
	Rect2(8.5, 8.0, 3.0, 8.0),
	Rect2(-20.5, -18.0, 7.0, 2.0),
	Rect2(4.5, -23.5, 3.0, 7.0),
	Rect2(37.5, 8.5, 5.0, 3.0),
	Rect2(-41.5, -9.5, 5.0, 3.0),
]
const NAV_PATH_MARGIN := 1.25
const NAV_CORNER_PADDING := 0.45

var current_tick := 0
var accumulator := 0.0
var player_credits := 850.0
var enemy_credits := 700.0
var match_over := false

var units: Dictionary = {}
var buildings: Dictionary = {}
var control_points: Dictionary = {}
var resource_nodes: Dictionary = {}
var unit_definitions: Dictionary = {}
var building_definitions: Dictionary = {}
var command_queue: Array = []
var event_history: Array = []

var _next_entity_id := 1
var _economy_timer := 0.0
var _ai_timer := 0.0
var _event_sequence := 0


func _ready() -> void:
	_build_definitions()


func start_match() -> void:
	_build_definitions()
	current_tick = 0
	accumulator = 0.0
	player_credits = 850.0
	enemy_credits = 700.0
	match_over = false
	_next_entity_id = 1
	_economy_timer = 0.0
	_ai_timer = 0.0
	_event_sequence = 0
	units.clear()
	buildings.clear()
	control_points.clear()
	resource_nodes.clear()
	command_queue.clear()
	event_history.clear()

	_add_resource_node("north_field", "Northern Energy Field", Vector3(-15.0, 0.0, -1.0), 1.0)
	_add_resource_node("south_field", "Southern Energy Field", Vector3(17.0, 0.0, 3.0), -1.0)

	_add_control_point("central_relay", "Central Relay", Vector3(0.0, 0.0, -1.0))
	_add_control_point("east_crossing", "East Crossing", Vector3(23.0, 0.0, -13.0))
	_add_control_point("west_crossing", "West Crossing", Vector3(-23.0, 0.0, 12.0))

	_add_building("player", "command_hub", Vector3(-30.0, 0.0, 15.0))
	_add_building("player", "refinery", Vector3(-24.0, 0.0, 15.0))
	_add_building("player", "assembly_bay", Vector3(-30.0, 0.0, 9.0))
	_add_unit("player", "ranger", Vector3(-22.0, 0.0, 9.0))
	_add_unit("player", "ranger", Vector3(-20.0, 0.0, 11.0))
	_add_unit("player", "warden", Vector3(-23.0, 0.0, 7.0))

	_add_building("enemy", "command_hub", Vector3(30.0, 0.0, -15.0))
	_add_building("enemy", "refinery", Vector3(24.0, 0.0, -15.0))
	_add_building("enemy", "assembly_bay", Vector3(30.0, 0.0, -9.0))
	_add_unit("enemy", "raider", Vector3(22.0, 0.0, -9.0))
	_add_unit("enemy", "raider", Vector3(20.0, 0.0, -11.0))
	_add_unit("enemy", "bulwark", Vector3(23.0, 0.0, -7.0))

	_emit_event("MatchStarted", {"tick": current_tick, "message": "Skirmish online. Secure the relay network."})


func step(delta: float) -> void:
	if match_over:
		return
	accumulator += delta
	var steps := 0
	while accumulator >= TICK_SECONDS and steps < MAX_STEPS_PER_FRAME:
		accumulator -= TICK_SECONDS
		step_fixed()
		steps += 1


func step_fixed() -> void:
	if match_over:
		return
	current_tick += 1
	_process_commands()
	_update_construction()
	_update_production()
	_update_units()
	_update_control_points()
	_update_supply_states()
	_update_economy()
	_update_ai()
	_check_victory()


func issue_command(command_type: String, issuer: String, payload: Dictionary) -> void:
	command_queue.append({
		"type": command_type,
		"issuer": issuer,
		"payload": payload.duplicate(true),
		"tick": current_tick,
	})


func get_state() -> Dictionary:
	return {
		"tick": current_tick,
		"player_credits": player_credits,
		"enemy_credits": enemy_credits,
		"units": units,
		"buildings": buildings,
		"control_points": control_points,
		"resource_nodes": resource_nodes,
		"match_over": match_over,
	}


func get_player_unit_ids() -> Array:
	var result: Array = []
	for entity_id in units:
		if units[entity_id]["team"] == "player":
			result.append(entity_id)
	return result


func get_territory_summary() -> Dictionary:
	var player_owned := 0
	var enemy_owned := 0
	for point_id in control_points:
		var owner: String = control_points[point_id]["owner"]
		if owner == "player":
			player_owned += 1
		elif owner == "enemy":
			enemy_owned += 1
	return {"player": player_owned, "enemy": enemy_owned, "total": control_points.size()}


func get_supply_summary(team: String) -> Dictionary:
	var connected_units := 0
	var unsupplied_units := 0
	for entity_id in units:
		var unit: Dictionary = units[entity_id]
		if unit["team"] != team:
			continue
		if unit.get("supply_state", "connected") == "connected":
			connected_units += 1
		else:
			unsupplied_units += 1
	return {
		"connected_units": connected_units,
		"unsupplied_units": unsupplied_units,
		"total_units": connected_units + unsupplied_units,
		"connected_sources": _get_connected_supply_sources(team).size(),
	}


func _build_definitions() -> void:
	if not unit_definitions.is_empty() and not building_definitions.is_empty():
		return
	unit_definitions.clear()
	building_definitions.clear()

	var ranger = UnitDefinitionScript.new()
	ranger.id = "ranger"
	ranger.display_name = "Ranger"
	ranger.role = "general infantry"
	ranger.cost = 90
	ranger.build_time = 2.5
	ranger.max_health = 100.0
	ranger.speed = 5.5
	ranger.attack_range = 8.0
	ranger.attack_damage = 13.0
	ranger.attack_cooldown = 0.85
	ranger.vision_range = 15.0
	ranger.body_scale = Vector3(0.8, 1.1, 0.8)
	unit_definitions[ranger.id] = ranger

	var warden = UnitDefinitionScript.new()
	warden.id = "warden"
	warden.display_name = "Warden"
	warden.role = "anti-armour"
	warden.cost = 130
	warden.build_time = 3.5
	warden.max_health = 145.0
	warden.speed = 4.0
	warden.attack_range = 10.0
	warden.attack_damage = 28.0
	warden.attack_cooldown = 1.55
	warden.vision_range = 16.0
	warden.body_scale = Vector3(1.05, 0.75, 1.05)
	unit_definitions[warden.id] = warden

	var raider = UnitDefinitionScript.new()
	raider.id = "raider"
	raider.display_name = "Raider"
	raider.role = "fast attack vehicle"
	raider.cost = 105
	raider.build_time = 3.0
	raider.max_health = 125.0
	raider.speed = 6.4
	raider.attack_range = 8.5
	raider.attack_damage = 16.0
	raider.attack_cooldown = 0.75
	raider.vision_range = 17.0
	raider.body_scale = Vector3(1.25, 0.65, 0.9)
	unit_definitions[raider.id] = raider

	var bulwark = UnitDefinitionScript.new()
	bulwark.id = "bulwark"
	bulwark.display_name = "Bulwark"
	bulwark.role = "heavy assault vehicle"
	bulwark.cost = 160
	bulwark.build_time = 4.5
	bulwark.max_health = 230.0
	bulwark.speed = 3.1
	bulwark.attack_range = 9.0
	bulwark.attack_damage = 34.0
	bulwark.attack_cooldown = 1.9
	bulwark.vision_range = 14.0
	bulwark.body_scale = Vector3(1.4, 0.8, 1.15)
	unit_definitions[bulwark.id] = bulwark

	var command_hub = BuildingDefinitionScript.new()
	command_hub.id = "command_hub"
	command_hub.display_name = "Command Hub"
	command_hub.role = "headquarters"
	command_hub.cost = 0
	command_hub.build_time = 0.0
	command_hub.max_health = 900.0
	command_hub.footprint = Vector2(4.5, 4.5)
	command_hub.body_height = 2.8
	building_definitions[command_hub.id] = command_hub

	var refinery = BuildingDefinitionScript.new()
	refinery.id = "refinery"
	refinery.display_name = "Resource Processor"
	refinery.role = "economy"
	refinery.cost = 250
	refinery.build_time = 4.5
	refinery.max_health = 420.0
	refinery.footprint = Vector2(3.5, 3.5)
	refinery.produces_income = 25.0
	refinery.body_height = 1.8
	building_definitions[refinery.id] = refinery

	var assembly_bay = BuildingDefinitionScript.new()
	assembly_bay.id = "assembly_bay"
	assembly_bay.display_name = "Assembly Bay"
	assembly_bay.role = "production"
	assembly_bay.cost = 220
	assembly_bay.build_time = 4.0
	assembly_bay.max_health = 450.0
	assembly_bay.footprint = Vector2(3.5, 3.5)
	assembly_bay.can_produce = "raider"
	assembly_bay.body_height = 2.0
	building_definitions[assembly_bay.id] = assembly_bay

	var relay = BuildingDefinitionScript.new()
	relay.id = "relay"
	relay.display_name = "Forward Relay"
	relay.role = "logistics"
	relay.cost = 180
	relay.build_time = 4.0
	relay.max_health = 300.0
	relay.footprint = Vector2(2.6, 2.6)
	relay.body_height = 2.5
	building_definitions[relay.id] = relay


func _process_commands() -> void:
	var pending := command_queue
	command_queue = []
	for command in pending:
		var command_type: String = command["type"]
		var issuer: String = command["issuer"]
		var payload: Dictionary = command["payload"]
		match command_type:
			"move":
				_apply_move_command(issuer, payload)
			"attack":
				_apply_attack_command(issuer, payload)
			"attack_move":
				_apply_attack_move_command(issuer, payload)
			"build":
				_try_build(issuer, payload.get("building_type", "relay"), payload.get("position", Vector3.ZERO))
			"produce":
				_try_produce(issuer, payload.get("building_id", ""), payload.get("unit_type", "raider"))
			"stop":
				_apply_stop_command(issuer, payload)
			"capture":
				_apply_move_command(issuer, payload)
			"repair":
				_apply_repair_command(issuer, payload)


func _apply_move_command(issuer: String, payload: Dictionary) -> void:
	var destination: Vector3 = payload.get("position", Vector3.ZERO)
	var entity_ids: Array = payload.get("entity_ids", [])
	var accepted := 0
	for entity_id in entity_ids:
		if not units.has(entity_id) or units[entity_id]["team"] != issuer:
			continue
		var unit: Dictionary = units[entity_id]
		var target_position: Vector3 = destination + _formation_offset(accepted, entity_ids.size())
		unit["target_position"] = target_position
		unit["waypoints"] = _build_navigation_path(unit["position"], target_position)
		unit["attack_target"] = ""
		unit["order"] = "move"
		accepted += 1
	if accepted > 0:
		_emit_event("OrderIssued", {
			"order": "move",
			"team": issuer,
			"count": accepted,
			"position": destination,
			"message": "Move order issued to %d unit%s." % [accepted, "" if accepted == 1 else "s"],
		})


func _apply_attack_move_command(issuer: String, payload: Dictionary) -> void:
	var destination: Vector3 = payload.get("position", Vector3.ZERO)
	var entity_ids: Array = payload.get("entity_ids", [])
	var accepted := 0
	for entity_id in entity_ids:
		if not units.has(entity_id) or units[entity_id]["team"] != issuer:
			continue
		var unit: Dictionary = units[entity_id]
		var target_position: Vector3 = destination + _formation_offset(accepted, entity_ids.size())
		unit["target_position"] = target_position
		unit["waypoints"] = _build_navigation_path(unit["position"], target_position)
		unit["attack_target"] = ""
		unit["order"] = "attack_move"
		accepted += 1
	if accepted > 0:
		_emit_event("OrderIssued", {
			"order": "attack_move",
			"team": issuer,
			"count": accepted,
			"position": destination,
			"message": "Attack-move order issued to %d unit%s." % [accepted, "" if accepted == 1 else "s"],
		})


func _apply_attack_command(issuer: String, payload: Dictionary) -> void:
	var target_id: String = str(payload.get("target_id", ""))
	var entity_ids: Array = payload.get("entity_ids", [])
	if not _entity_exists(target_id):
		_emit_event("OrderRejected", {"team": issuer, "reason": "Target no longer exists."})
		return
	var accepted := 0
	for entity_id in entity_ids:
		if not units.has(entity_id) or units[entity_id]["team"] != issuer:
			continue
		var unit: Dictionary = units[entity_id]
		unit["attack_target"] = target_id
		unit["waypoints"] = []
		unit["order"] = "attack"
		accepted += 1
	if accepted > 0:
		_emit_event("OrderIssued", {
			"order": "attack",
			"team": issuer,
			"count": accepted,
			"target_id": target_id,
			"message": "Attack order issued to %d unit%s." % [accepted, "" if accepted == 1 else "s"],
		})


func _apply_stop_command(issuer: String, payload: Dictionary) -> void:
	var stopped := 0
	for entity_id in payload.get("entity_ids", []):
		if units.has(entity_id) and units[entity_id]["team"] == issuer:
			var unit: Dictionary = units[entity_id]
			unit["order"] = "idle"
			unit["attack_target"] = ""
			unit["target_position"] = unit["position"]
			unit["waypoints"] = []
			stopped += 1
	if stopped > 0:
		_emit_event("OrderIssued", {
			"order": "stop",
			"team": issuer,
			"count": stopped,
			"message": "Stopped %d unit%s." % [stopped, "" if stopped == 1 else "s"],
		})


func _apply_repair_command(issuer: String, payload: Dictionary) -> void:
	var target_id: String = str(payload.get("target_id", ""))
	if buildings.has(target_id) and buildings[target_id]["team"] == issuer:
		var building: Dictionary = buildings[target_id]
		building["health"] = min(float(building["max_health"]), float(building["health"]) + 35.0)
		_emit_event("BuildingRepaired", {"building_id": target_id, "team": issuer})


func _try_build(issuer: String, building_type: String, position: Vector3) -> void:
	if not building_definitions.has(building_type):
		return
	var definition = building_definitions[building_type]
	var cost: float = definition.cost
	if _get_credits(issuer) < cost:
		_emit_event("OrderRejected", {"team": issuer, "reason": "Need %d more credits." % int(cost - _get_credits(issuer)), "order": "build"})
		return
	if not _is_valid_build_position(issuer, position):
		_emit_event("OrderRejected", {"team": issuer, "reason": "Position must be near a connected friendly structure and clear of buildings.", "order": "build"})
		return
	_set_credits(issuer, _get_credits(issuer) - cost)
	var building_id := _add_building(issuer, building_type, Vector3(position.x, 0.0, position.z), true)
	_emit_event("BuildingStarted", {"building_id": building_id, "building_type": building_type, "team": issuer, "message": "%s construction started." % definition.display_name})


func _try_produce(issuer: String, building_id: String, unit_type: String) -> void:
	if not buildings.has(building_id) or not unit_definitions.has(unit_type):
		_emit_event("OrderRejected", {"team": issuer, "reason": "Production source unavailable.", "order": "produce"})
		return
	var building: Dictionary = buildings[building_id]
	if building["team"] != issuer or not building["complete"] or building["kind"] != "assembly_bay":
		_emit_event("OrderRejected", {"team": issuer, "reason": "Assembly Bay is not ready.", "order": "produce"})
		return
	var definition = unit_definitions[unit_type]
	if _get_credits(issuer) < definition.cost:
		_emit_event("OrderRejected", {"team": issuer, "reason": "Need %d more credits." % int(definition.cost - _get_credits(issuer)), "order": "produce"})
		return
	_set_credits(issuer, _get_credits(issuer) - definition.cost)
	var queue: Array = building["queue"]
	queue.append({"unit_type": unit_type, "remaining": definition.build_time})
	building["queue"] = queue
	_emit_event("ProductionStarted", {"building_id": building_id, "unit_type": unit_type, "team": issuer, "message": "%s queued." % definition.display_name})


func _update_construction() -> void:
	for building_id in buildings.keys():
		var building: Dictionary = buildings[building_id]
		if building["complete"]:
			continue
		var definition = building_definitions[building["kind"]]
		if definition.build_time <= 0.0:
			building["construction_progress"] = 1.0
			building["complete"] = true
			continue
		building["construction_progress"] = min(1.0, float(building["construction_progress"]) + TICK_SECONDS / definition.build_time)
		if float(building["construction_progress"]) >= 1.0:
			building["complete"] = true
			_emit_event("BuildingCompleted", {"building_id": building_id, "building_type": building["kind"], "team": building["team"], "message": "%s online." % definition.display_name})


func _update_production() -> void:
	for building_id in buildings.keys():
		var building: Dictionary = buildings[building_id]
		if not building["complete"]:
			continue
		var queue: Array = building["queue"]
		if queue.is_empty():
			continue
		var job: Dictionary = queue[0]
		job["remaining"] = float(job["remaining"]) - TICK_SECONDS
		if float(job["remaining"]) <= 0.0:
			var spawn_offset := Vector3(0.0, 0.0, 4.0 if building["team"] == "player" else -4.0)
			var spawned_id := _add_unit(building["team"], job["unit_type"], building["position"] + spawn_offset)
			queue.pop_front()
			_emit_event("ProductionCompleted", {"building_id": building_id, "unit_id": spawned_id, "unit_type": job["unit_type"], "team": building["team"], "message": "%s ready." % unit_definitions[job["unit_type"]].display_name})
		building["queue"] = queue


func _update_units() -> void:
	var destroyed: Array = []
	for entity_id in units.keys():
		if not units.has(entity_id):
			continue
		var unit: Dictionary = units[entity_id]
		var definition = unit_definitions[unit["kind"]]
		unit["cooldown"] = max(0.0, float(unit["cooldown"]) - TICK_SECONDS)
		var attack_target: String = str(unit["attack_target"])
		if not attack_target.is_empty() and not _entity_exists(attack_target):
			unit["attack_target"] = ""
			attack_target = ""

		var speed_multiplier: float = float(unit.get("supply_speed_multiplier", 1.0))
		var damage_multiplier: float = float(unit.get("supply_damage_multiplier", 1.0))
		if not attack_target.is_empty():
			var target_position: Vector3 = _get_entity_position(attack_target)
			var distance: float = unit["position"].distance_to(target_position)
			if distance > definition.attack_range * 0.86:
				unit["position"] = unit["position"].move_toward(target_position, definition.speed * speed_multiplier * TICK_SECONDS)
			else:
				if float(unit["cooldown"]) <= 0.0:
					_apply_damage(attack_target, definition.attack_damage * damage_multiplier, entity_id)
					unit["cooldown"] = definition.attack_cooldown
			continue

		if unit["order"] == "move" or unit["order"] == "attack_move":
			var waypoints: Array = unit.get("waypoints", [])
			while not waypoints.is_empty() and unit["position"].distance_to(waypoints[0]) <= 0.25:
				unit["position"] = waypoints[0]
				waypoints.pop_front()
			unit["waypoints"] = waypoints
			var destination: Vector3 = unit["target_position"]
			if waypoints.is_empty() and unit["position"].distance_to(destination) <= 0.15:
				unit["position"] = destination
				unit["order"] = "idle"
			else:
				var next_position: Vector3 = destination
				if not waypoints.is_empty():
					next_position = waypoints[0]
				unit["position"] = unit["position"].move_toward(next_position, definition.speed * speed_multiplier * TICK_SECONDS)

		var nearby_target := _find_nearby_enemy(unit["team"], unit["position"], definition.vision_range)
		if not nearby_target.is_empty():
			unit["attack_target"] = nearby_target

	for entity_id in destroyed:
		units.erase(entity_id)


func _build_navigation_path(start: Vector3, destination: Vector3) -> Array:
	var start_point := Vector2(start.x, start.z)
	var destination_point := Vector2(destination.x, destination.z)
	if _navigation_segment_clear(start_point, destination_point):
		return [destination]

	var nodes: Array = [start_point, destination_point]
	for obstacle in NAVIGATION_OBSTACLES:
		var expanded: Rect2 = obstacle.grow(NAV_PATH_MARGIN)
		nodes.append(expanded.position + Vector2(-NAV_CORNER_PADDING, -NAV_CORNER_PADDING))
		nodes.append(Vector2(expanded.end.x + NAV_CORNER_PADDING, expanded.position.y - NAV_CORNER_PADDING))
		nodes.append(Vector2(expanded.end.x + NAV_CORNER_PADDING, expanded.end.y + NAV_CORNER_PADDING))
		nodes.append(Vector2(expanded.position.x - NAV_CORNER_PADDING, expanded.end.y + NAV_CORNER_PADDING))

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
			if visited[neighbor] or not _navigation_segment_clear(nodes[current], nodes[neighbor]):
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


func _navigation_segment_clear(from_point: Vector2, to_point: Vector2) -> bool:
	for obstacle in NAVIGATION_OBSTACLES:
		var blocked: Rect2 = obstacle.grow(NAV_PATH_MARGIN)
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


func _update_control_points() -> void:
	for point_id in control_points.keys():
		var point: Dictionary = control_points[point_id]
		var player_count := _count_units_in_radius("player", point["position"], point["radius"])
		var enemy_count := _count_units_in_radius("enemy", point["position"], point["radius"])
		if player_count == enemy_count:
			continue
		var pressure := 5.0 if player_count > enemy_count else -5.0
		point["capture_progress"] = clamp(float(point["capture_progress"]) + pressure, -100.0, 100.0)
		if float(point["capture_progress"]) >= 100.0 and point["owner"] != "player":
			point["owner"] = "player"
			_emit_event("TerritoryCaptured", {"point_id": point_id, "team": "player", "message": "%s secured." % point["display_name"]})
		elif float(point["capture_progress"]) <= -100.0 and point["owner"] != "enemy":
			point["owner"] = "enemy"
			_emit_event("TerritoryCaptured", {"point_id": point_id, "team": "enemy", "message": "%s lost." % point["display_name"]})


func _update_economy() -> void:
	_economy_timer += TICK_SECONDS
	if _economy_timer < 1.0:
		return
	_economy_timer -= 1.0
	var player_income := _income_for_team("player")
	var enemy_income := _income_for_team("enemy")
	player_credits += player_income
	enemy_credits += enemy_income
	_emit_event("ResourceChanged", {"team": "player", "amount": player_income, "total": player_credits})


func _update_supply_states() -> void:
	var player_sources: Array = _get_connected_supply_sources("player")
	var enemy_sources: Array = _get_connected_supply_sources("enemy")
	for entity_id in units:
		var unit: Dictionary = units[entity_id]
		var sources: Array = player_sources if unit["team"] == "player" else enemy_sources
		var connected := false
		for source_position in sources:
			if unit["position"].distance_to(source_position) <= SUPPLY_EFFECT_RADIUS:
				connected = true
				break
		var next_state := "connected" if connected else "unsupplied"
		var previous_state: String = unit.get("supply_state", "connected")
		unit["supply_state"] = next_state
		unit["supply_speed_multiplier"] = 1.0 if connected else UNSUPPLIED_SPEED_MULTIPLIER
		unit["supply_damage_multiplier"] = 1.0 if connected else UNSUPPLIED_DAMAGE_MULTIPLIER
		if previous_state != next_state:
			_emit_event("SupplyStateChanged", {
				"unit_id": entity_id,
				"team": unit["team"],
				"state": next_state,
				"message": "%s %s." % [unit["display_name"], "resupplied" if connected else "is UNSUPPLIED"],
			})


func _get_connected_supply_sources(team: String) -> Array:
	var candidates: Array = []
	for building_id in buildings:
		var building: Dictionary = buildings[building_id]
		if building["team"] == team and building["complete"] and (building["kind"] == "command_hub" or building["kind"] == "relay"):
			candidates.append({"id": building_id, "position": building["position"]})
	for point_id in control_points:
		var point: Dictionary = control_points[point_id]
		if point["owner"] == team:
			candidates.append({"id": point_id, "position": point["position"]})

	var connected_ids: Array = []
	var connected_positions: Array = []
	for candidate in candidates:
		if buildings.has(candidate["id"]) and buildings[candidate["id"]]["kind"] == "command_hub":
			connected_ids.append(candidate["id"])
			connected_positions.append(candidate["position"])
	var expanded := true
	while expanded:
		expanded = false
		for candidate in candidates:
			if connected_ids.has(candidate["id"]):
				continue
			for connected_position in connected_positions:
				if candidate["position"].distance_to(connected_position) <= SUPPLY_LINK_RADIUS:
					connected_ids.append(candidate["id"])
					connected_positions.append(candidate["position"])
					expanded = true
					break
	return connected_positions


func _income_for_team(team: String) -> float:
	var income := 0.0
	for building_id in buildings:
		var building: Dictionary = buildings[building_id]
		if building["team"] == team and building["complete"]:
			var definition = building_definitions[building["kind"]]
			income += definition.produces_income
	for point_id in control_points:
		if control_points[point_id]["owner"] == team:
			income += 10.0
	return income


func _update_ai() -> void:
	_ai_timer += TICK_SECONDS
	if _ai_timer < 3.0:
		return
	_ai_timer = 0.0
	var assembly_id := _first_building_for_team("enemy", "assembly_bay")
	if not assembly_id.is_empty() and enemy_credits >= unit_definitions["raider"].cost:
		_try_produce("enemy", assembly_id, "raider")

	var player_hq := _first_building_for_team("player", "command_hub")
	if player_hq.is_empty():
		return
	var enemy_units := get_units_for_team("enemy")
	if enemy_units.is_empty():
		return
	var attack_group: Array = []
	for entity_id in enemy_units:
		if units[entity_id]["order"] == "idle" or units[entity_id]["order"] == "move":
			attack_group.append(entity_id)
	if attack_group.size() >= 2 and current_tick % 60 == 0:
		_apply_attack_command("enemy", {"entity_ids": attack_group, "target_id": player_hq})


func _check_victory() -> void:
	if match_over:
		return
	var player_hq := _first_building_for_team("player", "command_hub")
	var enemy_hq := _first_building_for_team("enemy", "command_hub")
	if player_hq.is_empty():
		match_over = true
		_emit_event("MatchLost", {"message": "Command Hub destroyed. The network has fractured."})
	elif enemy_hq.is_empty():
		match_over = true
		_emit_event("MatchWon", {"message": "Enemy Command Hub destroyed. The relay network is yours."})


func _apply_damage(target_id: String, damage: float, attacker_id: String) -> void:
	if units.has(target_id):
		var target: Dictionary = units[target_id]
		target["health"] = max(0.0, float(target["health"]) - damage)
		_emit_event("UnitDamaged", {"target_id": target_id, "attacker_id": attacker_id, "health": target["health"], "max_health": target["max_health"]})
		if float(target["health"]) <= 0.0:
			units.erase(target_id)
			_emit_event("UnitDestroyed", {"unit_id": target_id, "attacker_id": attacker_id, "team": target["team"], "message": "%s destroyed." % unit_definitions[target["kind"]].display_name})
	elif buildings.has(target_id):
		var building: Dictionary = buildings[target_id]
		building["health"] = max(0.0, float(building["health"]) - damage)
		_emit_event("BuildingDamaged", {"building_id": target_id, "attacker_id": attacker_id, "health": building["health"], "max_health": building["max_health"]})
		if float(building["health"]) <= 0.0:
			buildings.erase(target_id)
			_emit_event("BuildingDestroyed", {"building_id": target_id, "attacker_id": attacker_id, "team": building["team"], "message": "%s destroyed." % building_definitions[building["kind"]].display_name})


func _find_nearby_enemy(team: String, position: Vector3, radius: float) -> String:
	var closest_id := ""
	var closest_distance := radius
	for entity_id in units:
		var candidate: Dictionary = units[entity_id]
		if candidate["team"] == team:
			continue
		var distance: float = position.distance_to(candidate["position"])
		if distance < closest_distance:
			closest_distance = distance
			closest_id = entity_id
	for building_id in buildings:
		var building: Dictionary = buildings[building_id]
		if building["team"] == team:
			continue
		var distance: float = position.distance_to(building["position"])
		if distance < closest_distance:
			closest_distance = distance
			closest_id = building_id
	return closest_id


func _count_units_in_radius(team: String, position: Vector3, radius: float) -> int:
	var count := 0
	for entity_id in units:
		var unit: Dictionary = units[entity_id]
		if unit["team"] == team and unit["position"].distance_to(position) <= radius:
			count += 1
	return count


func _is_valid_build_position(team: String, position: Vector3) -> bool:
	var near_network := false
	for source_position in _get_connected_supply_sources(team):
		if source_position.distance_to(position) <= SUPPLY_LINK_RADIUS:
			near_network = true
			break
	for building_id in buildings:
		var building: Dictionary = buildings[building_id]
		if building["position"].distance_to(position) < 4.0:
			return false
	return near_network and abs(position.x) < 53.0 and abs(position.z) < 33.0


func _add_unit(team: String, kind: String, position: Vector3) -> String:
	var definition = unit_definitions[kind]
	var entity_id := _new_entity_id("unit")
	units[entity_id] = {
		"id": entity_id,
		"team": team,
		"kind": kind,
		"display_name": definition.display_name,
		"position": Vector3(position.x, 0.0, position.z),
		"target_position": Vector3(position.x, 0.0, position.z),
		"waypoints": [],
		"attack_target": "",
		"order": "idle",
		"health": definition.max_health,
		"max_health": definition.max_health,
		"cooldown": 0.0,
		"supply_state": "connected",
		"supply_speed_multiplier": 1.0,
		"supply_damage_multiplier": 1.0,
	}
	return entity_id


func _add_building(team: String, kind: String, position: Vector3, under_construction := false) -> String:
	var definition = building_definitions[kind]
	var entity_id := _new_entity_id("building")
	var complete := not under_construction
	buildings[entity_id] = {
		"id": entity_id,
		"team": team,
		"kind": kind,
		"display_name": definition.display_name,
		"position": Vector3(position.x, 0.0, position.z),
		"health": definition.max_health,
		"max_health": definition.max_health,
		"complete": complete,
		"construction_progress": 1.0 if complete else 0.0,
		"queue": [],
	}
	return entity_id


func _add_control_point(point_id: String, display_name: String, position: Vector3) -> void:
	control_points[point_id] = {
		"id": point_id,
		"display_name": display_name,
		"position": position,
		"owner": "neutral",
		"capture_progress": 0.0,
		"radius": 4.5,
	}


func _add_resource_node(node_id: String, display_name: String, position: Vector3, faction_hint: float) -> void:
	resource_nodes[node_id] = {
		"id": node_id,
		"display_name": display_name,
		"position": position,
		"faction_hint": faction_hint,
	}


func _get_entity_position(entity_id: String) -> Vector3:
	if units.has(entity_id):
		return units[entity_id]["position"]
	if buildings.has(entity_id):
		return buildings[entity_id]["position"]
	return Vector3.ZERO


func _entity_exists(entity_id: String) -> bool:
	return units.has(entity_id) or buildings.has(entity_id)


func get_units_for_team(team: String) -> Array:
	var result: Array = []
	for entity_id in units:
		if units[entity_id]["team"] == team:
			result.append(entity_id)
	return result


func _first_building_for_team(team: String, kind: String) -> String:
	for entity_id in buildings:
		if buildings[entity_id]["team"] == team and buildings[entity_id]["kind"] == kind:
			return entity_id
	return ""


func _get_credits(team: String) -> float:
	return player_credits if team == "player" else enemy_credits


func _set_credits(team: String, value: float) -> void:
	if team == "player":
		player_credits = value
	else:
		enemy_credits = value


func _formation_offset(index: int, total: int) -> Vector3:
	if total <= 1:
		return Vector3.ZERO
	var columns := int(ceil(sqrt(float(total))))
	var row := index / columns
	var column := index % columns
	return Vector3((column - (columns - 1) * 0.5) * 1.6, 0.0, row * 1.6)


func _new_entity_id(prefix: String) -> String:
	var result := "%s_%03d" % [prefix, _next_entity_id]
	_next_entity_id += 1
	return result


func _emit_event(event_type: String, payload: Dictionary) -> void:
	_event_sequence += 1
	var event := payload.duplicate(true)
	event["event_type"] = event_type
	event["tick"] = current_tick
	event["sequence"] = _event_sequence
	event_history.append(event)
	if event_history.size() > 100:
		event_history.pop_front()
	simulation_event.emit(event_type, event)

