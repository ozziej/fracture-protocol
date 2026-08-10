class_name RtsSimulation
extends Node

const DefinitionCatalogScript = preload("res://src/simulation/rts_definition_catalog.gd")
const NavigationServiceScript = preload("res://src/simulation/rts_navigation_service.gd")
const AiControllerScript = preload("res://src/simulation/rts_ai_controller.gd")
const LogisticsSystemScript = preload("res://src/simulation/rts_logistics_system.gd")
const ForceCapacityScript = preload("res://src/simulation/rts_force_capacity.gd")

signal simulation_event(event_type: String, payload: Dictionary)

const TICK_SECONDS := 0.1
const MAX_STEPS_PER_FRAME := 8
const SUPPLY_LINK_RADIUS := 19.0
const SUPPLY_EFFECT_RADIUS := 13.0
const UNSUPPLIED_SPEED_MULTIPLIER := 0.82
const UNSUPPLIED_DAMAGE_MULTIPLIER := 0.7
const DEFAULT_NAVIGATION_OBSTACLES := [
	Rect2(-11.0, 14.0, 8.0, 2.0),
	Rect2(8.5, 8.0, 3.0, 8.0),
	Rect2(-20.5, -18.0, 7.0, 2.0),
	Rect2(4.5, -23.5, 3.0, 7.0),
	Rect2(37.5, 8.5, 5.0, 3.0),
	Rect2(-41.5, -9.5, 5.0, 3.0),
]
const LEVEL_DATA_PATH := "res://data/level_data.json"
const MAX_PRODUCTION_QUEUE := 5
const NAV_PATH_MARGIN := 1.25
const NAV_CORNER_PADDING := 0.45
const COLLECTOR_LOAD_SECONDS := 2.5
const COLLECTOR_CAPACITY := 75.0
const COLLECTOR_HOME_DISTANCE := 0.9
const REPAIR_UNIT_AMOUNT := 40.0
const REPAIR_UNIT_COST := 30.0
const REPAIR_BUILDING_AMOUNT := 60.0
const REPAIR_BUILDING_COST := 45.0
const REPAIR_STATION_RADIUS := 7.5

var current_tick := 0
var accumulator := 0.0
var player_credits := 850.0
var enemy_credits := 700.0
var match_over := false
var match_winner := ""

var units: Dictionary = {}
var buildings: Dictionary = {}
var control_points: Dictionary = {}
var resource_nodes: Dictionary = {}
var unit_definitions: Dictionary = {}
var building_definitions: Dictionary = {}
var technology_definitions: Dictionary = {}
var team_technologies: Dictionary = {"player": {}, "enemy": {}}
var command_queue: Array = []
var event_history: Array = []
var level_id := ""
var level_definition: Dictionary = {}
var level_rules: Dictionary = {}
var level_bounds := Vector2(60.0, 40.0)
var navigation_obstacles: Array = []
var requested_level_id := ""
var pending_projectiles: Array = []

var _next_entity_id := 1
var _economy_timer := 0.0
var _ai_timer := 0.0
var _event_sequence := 0
var _ai_controller
var _logistics_system


func _ready() -> void:
	_build_definitions()
	_load_level_data()


func restart_match() -> void:
	start_match(requested_level_id)


func start_match(next_level_id := "") -> void:
	if not next_level_id.is_empty():
		requested_level_id = next_level_id
	_build_definitions()
	_load_level_data()
	_configure_level_runtime()
	current_tick = 0
	accumulator = 0.0
	player_credits = 850.0
	enemy_credits = 700.0
	match_over = false
	match_winner = ""
	_next_entity_id = 1
	_economy_timer = 0.0
	_ai_timer = 0.0
	_event_sequence = 0
	units.clear()
	buildings.clear()
	control_points.clear()
	resource_nodes.clear()
	team_technologies = {"player": {}, "enemy": {}}
	command_queue.clear()
	event_history.clear()
	pending_projectiles.clear()

	if level_definition.is_empty():
		_setup_fallback_match()
	else:
		_setup_match_from_level()

	_emit_event("MatchStarted", {
		"tick": current_tick,
		"message": get_level_briefing(),
	})


func _setup_fallback_match() -> void:
	_add_resource_node("north_field", "Northern Energy Field", Vector3(-15.0, 0.0, -1.0), 1.0)
	_add_resource_node("south_field", "Southern Energy Field", Vector3(17.0, 0.0, 3.0), -1.0)

	_add_control_point("central_relay", "Central Relay", Vector3(0.0, 0.0, -1.0), 4.5, true)
	_add_control_point("east_crossing", "East Crossing", Vector3(23.0, 0.0, -13.0), 4.5, true)
	_add_control_point("west_crossing", "West Crossing", Vector3(-23.0, 0.0, 12.0), 4.5, true)

	var player_hub_id := _add_building("player", "command_hub", Vector3(-30.0, 0.0, 15.0))
	var player_refinery_id := _add_building("player", "refinery", Vector3(-24.0, 0.0, 15.0))
	_add_building("player", "assembly_bay", Vector3(-30.0, 0.0, 9.0))
	_add_unit("player", "ranger", Vector3(-22.0, 0.0, 9.0))
	_add_unit("player", "ranger", Vector3(-20.0, 0.0, 11.0))
	_add_unit("player", "warden", Vector3(-23.0, 0.0, 7.0))
	_add_collector("player", "north_field", player_refinery_id, player_hub_id, buildings[player_refinery_id]["position"])

	var enemy_hub_id := _add_building("enemy", "command_hub", Vector3(30.0, 0.0, -15.0))
	var enemy_refinery_id := _add_building("enemy", "refinery", Vector3(24.0, 0.0, -15.0))
	_add_building("enemy", "assembly_bay", Vector3(30.0, 0.0, -9.0))
	_add_unit("enemy", "raider", Vector3(22.0, 0.0, -9.0))
	_add_unit("enemy", "raider", Vector3(20.0, 0.0, -11.0))
	_add_unit("enemy", "bulwark", Vector3(23.0, 0.0, -7.0))
	_add_collector("enemy", "south_field", enemy_refinery_id, enemy_hub_id, buildings[enemy_refinery_id]["position"])


func _setup_match_from_level() -> void:
	for node_data in level_definition.get("resource_nodes", []):
		var node: Dictionary = node_data
		_add_resource_node(
			str(node.get("id", "resource_%d" % resource_nodes.size())),
			str(node.get("display_name", "Energy Field")),
			_level_vector3(node.get("position", {})),
			float(node.get("faction_hint", 0.0)),
			float(node.get("remaining", 5000.0))
		)
	for point_data in level_definition.get("control_points", []):
		var point: Dictionary = point_data
		_add_control_point(
			str(point.get("id", "relay_%d" % control_points.size())),
			str(point.get("display_name", "Relay")),
			_level_vector3(point.get("position", {})),
			float(point.get("radius", 4.5)),
			bool(point.get("supports_staging", false))
		)

	var authored_buildings: Dictionary = {}
	for team in ["player", "enemy"]:
		var spawn_data: Dictionary = level_definition.get("spawns", {}).get(team, {})
		for building_data in spawn_data.get("buildings", []):
			var building_entry: Dictionary = building_data
			var building_id := _add_building(team, str(building_entry.get("kind", "relay")), _level_vector3(building_entry.get("position", {})))
			var authored_id := str(building_entry.get("id", ""))
			if not authored_id.is_empty():
				authored_buildings[authored_id] = building_id
		for unit_data in spawn_data.get("units", []):
			var unit_entry: Dictionary = unit_data
			var unit_kind := str(unit_entry.get("kind", "ranger"))
			var unit_position := _level_vector3(unit_entry.get("position", {}))
			if unit_kind == "collector":
				var source_id := str(unit_entry.get("source_id", ""))
				var destination_id := str(unit_entry.get("destination_id", ""))
				var home_id := str(unit_entry.get("home_id", ""))
				if authored_buildings.has(destination_id):
					destination_id = authored_buildings[destination_id]
				if authored_buildings.has(home_id):
					home_id = authored_buildings[home_id]
				_add_collector(team, source_id, destination_id, home_id, unit_position)
			else:
				_add_unit(team, unit_kind, unit_position)


func _load_level_data() -> void:
	level_id = ""
	level_definition = {}
	level_rules = {}
	var file := FileAccess.open(LEVEL_DATA_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_warning("Level data must contain a JSON object: %s" % LEVEL_DATA_PATH)
		return
	var root: Dictionary = parsed
	var missions: Dictionary = root.get("mission_maps", {})
	var selected_id := requested_level_id if not requested_level_id.is_empty() else str(root.get("default_level_id", ""))
	if selected_id.is_empty() or not missions.has(selected_id):
		if missions.is_empty():
			return
		selected_id = str(missions.keys()[0])
	var mission: Dictionary = missions.get(selected_id, {})
	var base_maps: Dictionary = root.get("base_maps", {})
	var base_id := str(mission.get("base_map_id", ""))
	var base: Dictionary = base_maps.get(base_id, {})
	level_definition = base.duplicate(true)
	for key in mission:
		if key != "base_map_id":
			level_definition[key] = mission[key]
	level_id = selected_id


func _configure_level_runtime() -> void:
	level_rules = level_definition.get("rules", {})
	var bounds: Dictionary = level_definition.get("map_bounds", {})
	level_bounds = Vector2(float(bounds.get("half_width", 60.0)), float(bounds.get("half_depth", 40.0)))
	navigation_obstacles.clear()
	var terrain: Dictionary = level_definition.get("terrain", {})
	for obstacle_data in terrain.get("obstacles", []):
		var obstacle: Dictionary = obstacle_data
		var position := _level_vector3(obstacle.get("position", {}))
		var size := _level_vector3(obstacle.get("size", {}), Vector3(1.0, 1.0, 1.0))
		navigation_obstacles.append(Rect2(position.x - size.x * 0.5, position.z - size.z * 0.5, size.x, size.z))
	if navigation_obstacles.is_empty():
		navigation_obstacles = DEFAULT_NAVIGATION_OBSTACLES.duplicate()


func _level_vector3(value: Variant, fallback: Vector3 = Vector3.ZERO) -> Vector3:
	if value is Vector3:
		return value
	if value is Dictionary:
		var data: Dictionary = value
		return Vector3(float(data.get("x", fallback.x)), float(data.get("y", fallback.y)), float(data.get("z", fallback.z)))
	return fallback


func get_level_id() -> String:
	return level_id


func get_level_terrain() -> Dictionary:
	return level_definition.get("terrain", {})


func get_level_bounds() -> Vector2:
	return level_bounds
func get_level_objectives() -> Dictionary:
	return level_definition.get("objectives", {})


func get_level_objective_text() -> Dictionary:
	return level_definition.get("objective_text", {})


func get_level_catalog(name: String) -> Array:
	return level_definition.get(name, [])


func is_level_allowed(name: String, id: String) -> bool:
	var entries: Array = get_level_catalog(name)
	return entries.is_empty() or id in entries


func is_team_allowed(team: String, category: String, id: String) -> bool:
	var entries: Array = get_level_catalog("allowed_%s_%s" % [team, category])
	if entries.is_empty():
		entries = get_level_catalog("allowed_%s" % category)
	return entries.is_empty() or id in entries

func get_level_briefing() -> String:
	return str(level_definition.get("briefing", ""))
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
	_update_upgrades()
	_update_research()
	_update_control_points()
	_update_supply_states()
	_update_forward_staging_states()
	_update_production()
	_update_units()
	_update_projectiles()
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
		"technologies": team_technologies,
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


func get_limit_summary(team: String) -> Dictionary:
	var current_force: int = _count_force(team, false)
	var queued_force: int = _count_force(team, true) - current_force
	var unit_by_kind: Dictionary = {}
	for kind in unit_definitions:
		unit_by_kind[kind] = {
			"current": _count_units(team, kind),
			"queued": _count_queued_units(team, kind),
			"force_slots": _force_slots_for_kind(kind),
			"force_current": _count_force(team, false, kind),
			"force_queued": _count_force(team, true, kind) - _count_force(team, false, kind),
		}
	var building_by_kind: Dictionary = {}
	for kind in building_definitions:
		building_by_kind[kind] = {
			"current": _count_buildings(team, kind),
			"max": _building_limit(team, kind),
		}
	return {
		"units": {
			"current": current_force,
			"queued": queued_force,
			"max": _max_units_total(),
			"current_count": _count_units(team),
			"queued_count": _count_queued_units(team),
			"by_kind": unit_by_kind,
		},
		"buildings": {
			"current": _count_buildings(team),
			"max": _max_buildings_total(),
			"by_kind": building_by_kind,
		},
		"queue": {"max": _max_production_queue()},
	}


func is_technology_unlocked(team: String, technology_id: String) -> bool:
	var unlocked: Dictionary = team_technologies.get(team, {})
	return bool(unlocked.get(technology_id, false))


func get_research_status(team: String) -> Dictionary:
	var active_id := ""
	var active_building_id := ""
	var remaining := 0.0
	var total := 0.0
	for building_id in buildings:
		var building: Dictionary = buildings[building_id]
		if building["team"] != team:
			continue
		var research_id: String = str(building.get("research_id", ""))
		if research_id.is_empty():
			continue
		active_id = research_id
		active_building_id = building_id
		remaining = float(building.get("research_remaining", 0.0))
		total = float(building.get("research_total", 0.0))
		break
	var unlocked_ids: Array = []
	var unlocked: Dictionary = team_technologies.get(team, {})
	for technology_id in unlocked:
		if unlocked[technology_id]:
			unlocked_ids.append(technology_id)
	return {
		"active_id": active_id,
		"active_building_id": active_building_id,
		"remaining": remaining,
		"total": total,
		"unlocked": unlocked_ids,
	}


func _build_definitions() -> void:
	DefinitionCatalogScript.populate(unit_definitions, building_definitions, technology_definitions)


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
				_try_build(issuer, payload.get("building_type", "relay"), payload.get("position", Vector3.ZERO), str(payload.get("source_building_id", "")))
			"produce":
				_try_produce(issuer, payload.get("building_id", ""), payload.get("unit_type", "raider"))
			"cancel_production":
				_try_cancel_production(issuer, str(payload.get("building_id", "")), int(payload.get("queue_index", -1)))
			"set_rally_point":
				_try_set_rally_point(issuer, payload)
			"research":
				_try_research(issuer, payload.get("building_id", ""), payload.get("technology_id", "advanced_targeting"))
			"assign_collector":
				_try_assign_collector(issuer, payload)
			"upgrade":
				_try_upgrade(issuer, str(payload.get("building_id", "")))
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
		unit["move_fire_target"] = str(unit.get("attack_target", "")) if _entity_exists(str(unit.get("attack_target", ""))) else ""
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
		unit["move_fire_target"] = ""
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
		unit["move_fire_target"] = ""
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
			unit["move_fire_target"] = ""
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
	var entity_ids: Array = payload.get("entity_ids", [])
	if entity_ids.is_empty() and payload.has("target_id"):
		entity_ids = [payload["target_id"]]
	var repaired_count := 0
	var failure_reason := ""
	for entity_id in entity_ids:
		if units.has(entity_id):
			var unit: Dictionary = units[entity_id]
			if unit["team"] != issuer or float(unit["health"]) >= float(unit["max_health"]):
				continue
			if not _is_repair_station_nearby(issuer, unit["position"]):
				failure_reason = "%s must be near a Command Hub, Resource Processor, or Forward Relay." % unit["display_name"]
				continue
			if _get_credits(issuer) < REPAIR_UNIT_COST:
				failure_reason = "Need %d more credits to repair %s." % [int(REPAIR_UNIT_COST - _get_credits(issuer)), unit["display_name"]]
				continue
			var repaired_amount: float = min(REPAIR_UNIT_AMOUNT, float(unit["max_health"]) - float(unit["health"]))
			_set_credits(issuer, _get_credits(issuer) - REPAIR_UNIT_COST)
			unit["health"] = min(float(unit["max_health"]), float(unit["health"]) + repaired_amount)
			repaired_count += 1
			_emit_event("UnitRepaired", {
				"unit_id": entity_id,
				"team": issuer,
				"amount": repaired_amount,
				"cost": REPAIR_UNIT_COST,
				"health": unit["health"],
				"message": "%s repaired +%d HP at a repair station." % [unit["display_name"], int(repaired_amount)],
			})
		elif buildings.has(entity_id):
			var building: Dictionary = buildings[entity_id]
			if building["team"] != issuer or not building["complete"] or float(building["health"]) >= float(building["max_health"]):
				continue
			if _get_credits(issuer) < REPAIR_BUILDING_COST:
				failure_reason = "Need %d more credits to repair %s." % [int(REPAIR_BUILDING_COST - _get_credits(issuer)), building["display_name"]]
				continue
			var building_amount: float = min(REPAIR_BUILDING_AMOUNT, float(building["max_health"]) - float(building["health"]))
			_set_credits(issuer, _get_credits(issuer) - REPAIR_BUILDING_COST)
			building["health"] = min(float(building["max_health"]), float(building["health"]) + building_amount)
			repaired_count += 1
			_emit_event("BuildingRepaired", {
				"building_id": entity_id,
				"team": issuer,
				"amount": building_amount,
				"cost": REPAIR_BUILDING_COST,
				"message": "%s repaired +%d HP." % [building["display_name"], int(building_amount)],
			})
	if repaired_count == 0:
		if failure_reason.is_empty():
			failure_reason = "No selected friendly entity needs repair."
		_reject_order(issuer, failure_reason, "repair")


func _is_repair_station_nearby(team: String, position: Vector3) -> bool:
	for building_id in buildings:
		var building: Dictionary = buildings[building_id]
		if building["team"] != team or not building["complete"]:
			continue
		if building["kind"] != "command_hub" and building["kind"] != "refinery" and building["kind"] != "relay":
			continue
		if building["position"].distance_to(position) <= REPAIR_STATION_RADIUS:
			return true
	for point_id in control_points:
		var point: Dictionary = control_points[point_id]
		if not _is_forward_staging_active(team, point_id):
			continue
		if point["position"].distance_to(position) <= float(point["radius"]):
			return true
	return false


func _reject_order(issuer: String, reason: String, order: String) -> void:
	_emit_event("OrderRejected", {"team": issuer, "reason": reason, "message": reason, "order": order})


func _try_assign_collector(issuer: String, payload: Dictionary) -> void:
	var collector_id: String = str(payload.get("collector_id", ""))
	var source_id: String = str(payload.get("source_id", ""))
	var destination_id: String = str(payload.get("destination_id", ""))
	if not units.has(collector_id):
		_reject_order(issuer, "Collector no longer exists.", "assign_collector")
		return
	var collector: Dictionary = units[collector_id]
	if collector["team"] != issuer or collector["kind"] != "collector":
		_reject_order(issuer, "Select a friendly Collector.", "assign_collector")
		return
	if not resource_nodes.has(source_id):
		_reject_order(issuer, "Select a valid resource field.", "assign_collector")
		return
	if not buildings.has(destination_id):
		_reject_order(issuer, "Select a valid Resource Processor.", "assign_collector")
		return
	var destination: Dictionary = buildings[destination_id]
	if destination["team"] != issuer or destination["kind"] != "refinery" or not destination["complete"]:
		_reject_order(issuer, "Route destination must be a completed friendly Resource Processor.", "assign_collector")
		return
	if float(collector.get("collector_cargo", 0.0)) > 0.0:
		_reject_order(issuer, "Wait for the Collector to deliver its current load.", "assign_collector")
		return
	_configure_collector_route(collector, source_id, destination_id)
	_emit_event("CollectorAssigned", {
		"unit_id": collector_id,
		"source_id": source_id,
		"destination_id": destination_id,
		"team": issuer,
		"message": "Collector route set: %s to %s." % [resource_nodes[source_id]["display_name"], destination["display_name"]],
	})


func _try_build(issuer: String, building_type: String, position: Vector3, source_building_id := "") -> void:
	if not building_definitions.has(building_type):
		return
	var definition = building_definitions[building_type]
	if not is_team_allowed(issuer, "buildings", building_type):
		_reject_order(issuer, "%s is not available in this level." % definition.display_name, "build")
		return
	if not definition.prerequisite_building.is_empty() and _first_building_for_team(issuer, definition.prerequisite_building).is_empty():
		_reject_order(issuer, "Build %s before %s." % [building_definitions[definition.prerequisite_building].display_name, definition.display_name], "build")
		return
	if not source_building_id.is_empty() and (not buildings.has(source_building_id) or buildings[source_building_id]["team"] != issuer or buildings[source_building_id]["kind"] != definition.build_source_kind):
		_reject_order(issuer, "%s construction must start from a %s." % [definition.display_name, definition.build_source_kind.replace("_", " ")], "build")
		return
	var limit_reason := _building_limit_reason(issuer, building_type)
	if not limit_reason.is_empty():
		_reject_order(issuer, limit_reason, "build")
		return
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
		_reject_order(issuer, "Production source unavailable.", "produce")
		return
	var building: Dictionary = buildings[building_id]
	if building["team"] != issuer or not building["complete"]:
		_reject_order(issuer, "Production source is not ready.", "produce")
		return
	var definition = unit_definitions[unit_type]
	if not is_team_allowed(issuer, "units", unit_type):
		_reject_order(issuer, "%s is not available in this level." % definition.display_name, "produce")
		return
	if unit_type == "collector" and _count_units(issuer, "collector") + _count_queued_units(issuer, "collector") >= 1 + _count_buildings(issuer, "storage_silo"):
		_reject_order(issuer, "Build a Storage Silo before assigning another Collector.", "produce")
		return
	if not unit_type in str(building_definitions[building["kind"]].can_produce).split(","):
		_reject_order(issuer, "%s cannot produce %s." % [building["display_name"], definition.display_name], "produce")
		return
	var queue: Array = building.get("queue", [])
	if queue.size() >= _max_production_queue():
		_reject_order(issuer, "%s queue full." % building["display_name"], "produce")
		return
	var unit_limit_reason := _unit_queue_limit_reason(issuer, unit_type)
	if not unit_limit_reason.is_empty():
		_reject_order(issuer, unit_limit_reason, "produce")
		return
	if not definition.required_technology.is_empty() and not is_technology_unlocked(issuer, definition.required_technology):
		_reject_order(issuer, "%s required before %s production." % [technology_definitions[definition.required_technology].display_name, definition.display_name], "produce")
		return
	if _get_credits(issuer) < definition.cost:
		_reject_order(issuer, "Need %d more credits." % int(definition.cost - _get_credits(issuer)), "produce")
		return
	_set_credits(issuer, _get_credits(issuer) - definition.cost)
	var total_time: float = definition.build_time * _production_time_multiplier(issuer, unit_type)
	queue.append({
		"id": _new_entity_id("queue"),
		"unit_type": unit_type,
		"remaining": total_time,
		"total": total_time,
		"cost": definition.cost,
	})
	building["queue"] = queue
	_emit_event("ProductionStarted", {"building_id": building_id, "unit_type": unit_type, "team": issuer, "message": "%s queued." % definition.display_name})


func _try_cancel_production(issuer: String, building_id: String, queue_index: int) -> void:
	if not buildings.has(building_id):
		_reject_order(issuer, "Production source unavailable; the queued item can no longer be cancelled.", "cancel_production")
		return
	var building: Dictionary = buildings[building_id]
	if building["team"] != issuer or not building["complete"]:
		_reject_order(issuer, "Only a completed friendly production building can cancel its queue.", "cancel_production")
		return
	var queue: Array = building.get("queue", [])
	if queue_index < 0 or queue_index >= queue.size():
		_reject_order(issuer, "That queue item has already completed or was cancelled.", "cancel_production")
		return
	var job: Dictionary = queue[queue_index]
	var unit_type := str(job.get("unit_type", ""))
	var definition = unit_definitions.get(unit_type)
	var refund: float = float(job.get("cost", definition.cost if definition else 0.0))
	queue.remove_at(queue_index)
	building["queue"] = queue
	_set_credits(issuer, _get_credits(issuer) + refund)
	var display_name: String = definition.display_name if definition else unit_type.replace("_", " ").capitalize()
	_emit_event("ProductionCancelled", {
		"building_id": building_id,
		"unit_type": unit_type,
		"queue_index": queue_index,
		"refund": refund,
		"team": issuer,
		"message": "%s cancelled — %d credits refunded." % [display_name, int(refund)],
	})


func _try_upgrade(issuer: String, building_id: String) -> void:
	if not buildings.has(building_id):
		_reject_order(issuer, "Select a building to upgrade.", "upgrade")
		return
	var building: Dictionary = buildings[building_id]
	var definition = building_definitions[building["kind"]]
	if building["team"] != issuer or not building["complete"] or definition.upgrade_id.is_empty():
		_reject_order(issuer, "This building has no available upgrade.", "upgrade")
		return
	if bool(building.get("upgrade_complete", false)) or not str(building.get("upgrade_id", "")).is_empty():
		_reject_order(issuer, "This building upgrade is already active or complete.", "upgrade")
		return
	if _get_credits(issuer) < definition.upgrade_cost:
		_reject_order(issuer, "Need %d more credits for %s." % [definition.upgrade_cost - int(_get_credits(issuer)), definition.upgrade_id.replace("_", " ")], "upgrade")
		return
	_set_credits(issuer, _get_credits(issuer) - definition.upgrade_cost)
	building["upgrade_id"] = definition.upgrade_id
	building["upgrade_remaining"] = definition.upgrade_time
	building["upgrade_total"] = definition.upgrade_time
	_emit_event("UpgradeStarted", {"building_id": building_id, "team": issuer, "message": "%s upgrade started." % definition.upgrade_id.replace("_", " ").capitalize()})


func _try_set_rally_point(issuer: String, payload: Dictionary) -> void:
	var building_id := str(payload.get("building_id", ""))
	if not buildings.has(building_id):
		_reject_order(issuer, "Select a friendly Assembly Bay.", "set_rally_point")
		return
	var building: Dictionary = buildings[building_id]
	if building["team"] != issuer or building["kind"] != "assembly_bay" or not building["complete"]:
		_reject_order(issuer, "Rally points require a completed friendly Assembly Bay.", "set_rally_point")
		return
	var control_point_id := str(payload.get("control_point_id", ""))
	if not control_point_id.is_empty():
		if not control_points.has(control_point_id):
			_reject_order(issuer, "Choose a valid forward staging site.", "set_rally_point")
			return
		var control_point: Dictionary = control_points[control_point_id]
		if control_point["owner"] != issuer or not _is_forward_staging_active(issuer, control_point_id):
			_reject_order(issuer, "Secure and connect %s before assigning it as a staging rally." % control_point["display_name"], "set_rally_point")
			return
		building["rally_position"] = control_point["position"]
		building["rally_enabled"] = true
		building["rally_mode"] = "control_point"
		building["rally_point_id"] = control_point_id
		building["rally_suspended"] = false
		_emit_event("RallyPointSet", {
			"building_id": building_id,
			"team": issuer,
			"position": control_point["position"],
			"control_point_id": control_point_id,
			"message": "%s staging rally assigned to %s." % [building["display_name"], control_point["display_name"]],
		})
		return
	var requested_position: Vector3 = payload.get("position", Vector3.ZERO)
	var position := Vector3(requested_position.x, 0.0, requested_position.z)
	if abs(position.x) > level_bounds.x - 2.0 or abs(position.z) > level_bounds.y - 2.0:
		_reject_order(issuer, "Rally point must be inside the level bounds.", "set_rally_point")
		return
	var definition = building_definitions[building["kind"]]
	var minimum_distance: float = max(3.0, max(definition.footprint.x, definition.footprint.y) * 0.5 + 1.0)
	if building["position"].distance_to(position) < minimum_distance:
		_reject_order(issuer, "Rally point must be outside the Assembly Bay.", "set_rally_point")
		return
	building["rally_position"] = position
	building["rally_enabled"] = true
	building["rally_mode"] = "ground"
	building["rally_point_id"] = ""
	building["rally_suspended"] = false
	_emit_event("RallyPointSet", {
		"building_id": building_id,
		"team": issuer,
		"position": position,
		"message": "%s rally point set." % building["display_name"],
	})


func _try_research(issuer: String, building_id: String, technology_id: String) -> void:
	if not technology_definitions.has(technology_id):
		_reject_order(issuer, "Unknown technology.", "research")
		return
	var technology = technology_definitions[technology_id]
	if is_technology_unlocked(issuer, technology_id):
		_reject_order(issuer, "%s is already online." % technology.display_name, "research")
		return
	if not buildings.has(building_id):
		_reject_order(issuer, "Research source unavailable.", "research")
		return
	var building: Dictionary = buildings[building_id]
	if building["team"] != issuer or not building["complete"] or str(building_definitions[building["kind"]].can_research) != technology_id:
		_reject_order(issuer, "Assembly Bay is not ready to research %s." % technology.display_name, "research")
		return
	var active_research: String = str(building.get("research_id", ""))
	if not active_research.is_empty():
		var active_name: String = technology_definitions[active_research].display_name if technology_definitions.has(active_research) else active_research
		_reject_order(issuer, "%s is already researching %s." % [building["display_name"], active_name], "research")
		return
	if _get_credits(issuer) < technology.cost:
		_reject_order(issuer, "Need %d more credits to research %s." % [int(technology.cost - _get_credits(issuer)), technology.display_name], "research")
		return
	_set_credits(issuer, _get_credits(issuer) - technology.cost)
	building["research_id"] = technology_id
	building["research_remaining"] = technology.research_time
	building["research_total"] = technology.research_time
	_emit_event("ResearchStarted", {
		"building_id": building_id,
		"technology_id": technology_id,
		"team": issuer,
		"message": "%s research started at %s." % [technology.display_name, building["display_name"]],
	})


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


func _update_upgrades() -> void:
	for building_id in buildings:
		var building: Dictionary = buildings[building_id]
		var upgrade_id := str(building.get("upgrade_id", ""))
		if upgrade_id.is_empty() or not building["complete"] or bool(building.get("upgrade_complete", false)):
			continue
		building["upgrade_remaining"] = max(0.0, float(building["upgrade_remaining"]) - TICK_SECONDS)
		if float(building["upgrade_remaining"]) > 0.0:
			continue
		building["completed_upgrade_id"] = upgrade_id
		building["upgrade_remaining"] = 0.0
		building["upgrade_total"] = 0.0
		building["upgrade_complete"] = true
		_emit_event("UpgradeCompleted", {"building_id": building_id, "team": building["team"], "message": "%s upgrade complete." % building["display_name"]})


func _update_research() -> void:
	for building_id in buildings.keys():
		var building: Dictionary = buildings[building_id]
		var technology_id: String = str(building.get("research_id", ""))
		if technology_id.is_empty() or not building["complete"] or not technology_definitions.has(technology_id):
			continue
		building["research_remaining"] = max(0.0, float(building.get("research_remaining", 0.0)) - TICK_SECONDS)
		if float(building["research_remaining"]) > 0.0:
			continue
		var technology = technology_definitions[technology_id]
		var unlocked: Dictionary = team_technologies.get(building["team"], {})
		unlocked[technology_id] = true
		team_technologies[building["team"]] = unlocked
		building["research_id"] = ""
		building["research_remaining"] = 0.0
		building["research_total"] = 0.0
		_emit_event("TechnologyUnlocked", {"building_id": building_id, "technology_id": technology_id, "team": building["team"], "message": "%s online. Bulwark production unlocked." % technology.display_name})


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
			var exit_position := _production_exit_position(building)
			var spawned_id := _add_unit(building["team"], job["unit_type"], exit_position)
			var rally_position := _active_rally_position(building, exit_position)
			if spawned_id.is_empty():
				continue
			if rally_position.distance_to(exit_position) > 0.15:
				var spawned_unit: Dictionary = units[spawned_id]
				spawned_unit["target_position"] = rally_position
				spawned_unit["waypoints"] = _build_navigation_path(exit_position, rally_position)
				spawned_unit["order"] = "move"
			queue.pop_front()
			var spawned_name: String = unit_definitions[job["unit_type"]].display_name
			var completion_message := "%s ready at rally point." % spawned_name
			if bool(building.get("rally_suspended", false)):
				completion_message = "%s ready at the Assembly Bay exit — staging rally is suspended." % spawned_name
			if job["unit_type"] == "collector":
				completion_message = "Collector ready at the Assembly Bay exit — assign a resource route."
			_emit_event("ProductionCompleted", {"building_id": building_id, "unit_id": spawned_id, "unit_type": job["unit_type"], "team": building["team"], "message": completion_message})
		building["queue"] = queue


func _max_production_queue() -> int:
	return max(1, int(level_rules.get("max_queue", MAX_PRODUCTION_QUEUE)))


func _production_time_multiplier(team: String, unit_type: String) -> float:
	var multiplier: float = max(0.1, float(level_rules.get("production_time_multiplier", 1.0)))
	if unit_type == "collector":
		multiplier *= max(0.1, float(level_rules.get("collector_production_time_multiplier", 1.0)))
	if _has_completed_upgrade(team, "fabrication_systems"):
		multiplier *= 0.8
	return multiplier
func _has_completed_upgrade(team: String, upgrade_id: String) -> bool:
	for building_id in buildings:
		var building: Dictionary = buildings[building_id]
		if building["team"] == team and str(building.get("completed_upgrade_id", "")) == upgrade_id:
			return true
	return false




func _collector_speed_multiplier() -> float:
	return max(0.1, float(level_rules.get("collector_speed_multiplier", 1.0)))


func _collector_load_seconds() -> float:
	return max(0.1, float(level_rules.get("collector_load_seconds", COLLECTOR_LOAD_SECONDS)))


func _production_exit_position(building: Dictionary) -> Vector3:
	var definition = building_definitions[building["kind"]]
	var clearance: float = max(3.5, max(definition.footprint.x, definition.footprint.y) * 0.5 + 2.0)
	var direction := 1.0 if building["team"] == "player" else -1.0
	return building["position"] + Vector3(0.0, 0.0, direction * clearance)

func _fire_weapon(unit: Dictionary, target_id: String, damage_multiplier: float) -> void:
	if not _entity_exists(target_id):
		return
	var definition = unit_definitions[unit["kind"]]
	var base_damage: float = definition.attack_damage * damage_multiplier
	if definition.projectile_mode == "arc_missile":
		var launch_position: Vector3 = unit["position"] + Vector3.UP * 0.8
		var impact_position: Vector3 = _get_entity_position(target_id)
		var travel_time: float = clamp(launch_position.distance_to(impact_position) / 24.0, 0.35, 0.9)
		pending_projectiles.append({
			"attacker_id": unit["id"],
			"team": unit["team"],
			"target_id": target_id,
			"launch_position": launch_position,
			"impact_position": impact_position,
			"remaining": travel_time,
			"total": travel_time,
			"damage": base_damage,
			"structure_damage_multiplier": definition.structure_damage_multiplier,
			"splash_radius": definition.splash_radius,
			"splash_minimum_multiplier": definition.splash_minimum_multiplier,
		})
		_emit_event("ProjectileLaunched", {
			"attacker_id": unit["id"],
			"target_id": target_id,
			"launch_position": launch_position,
			"impact_position": impact_position,
			"travel_time": travel_time,
		})
		return
	if buildings.has(target_id):
		base_damage *= definition.structure_damage_multiplier
	_apply_damage(target_id, base_damage, unit["id"])


func _update_projectiles() -> void:
	for projectile_index in range(pending_projectiles.size() - 1, -1, -1):
		var projectile: Dictionary = pending_projectiles[projectile_index]
		projectile["remaining"] = float(projectile["remaining"]) - TICK_SECONDS
		if float(projectile["remaining"]) > 0.0:
			continue
		var target_id := str(projectile["target_id"])
		var impact_position: Vector3 = projectile["impact_position"]
		if _entity_exists(target_id):
			impact_position = _get_entity_position(target_id)
		var damage: float = float(projectile["damage"])
		if buildings.has(target_id):
			damage *= float(projectile["structure_damage_multiplier"])
		if _entity_exists(target_id):
			_apply_damage(target_id, damage, str(projectile["attacker_id"]))
		var splash_radius: float = float(projectile["splash_radius"])
		if splash_radius > 0.0:
			for entity_id in units.keys():
				if entity_id == target_id or not units.has(entity_id):
					continue
				var candidate: Dictionary = units[entity_id]
				if candidate["team"] == projectile["team"]:
					continue
				var distance: float = candidate["position"].distance_to(impact_position)
				if distance <= splash_radius:
					var ratio: float = clamp(distance / splash_radius, 0.0, 1.0)
					var falloff: float = lerp(1.0, float(projectile["splash_minimum_multiplier"]), ratio)
					_apply_damage(entity_id, damage * falloff, str(projectile["attacker_id"]))
		_emit_event("ProjectileImpact", {
			"attacker_id": projectile["attacker_id"],
			"target_id": target_id,
			"position": impact_position,
		})
		pending_projectiles.remove_at(projectile_index)



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
		if unit["kind"] == "collector":
			_update_collector_unit(unit, definition, speed_multiplier, damage_multiplier)
			continue
		if unit["order"] == "move":
			# An explicit move is the primary objective. Units may fire at a remembered or newly
			# detected target in range, but they must never turn toward or chase it while moving.
			_advance_unit_along_route(unit, definition.speed * speed_multiplier)
			var fire_target: String = attack_target
			if fire_target.is_empty():
				fire_target = str(unit.get("move_fire_target", ""))
			if not fire_target.is_empty():
				if not _entity_exists(fire_target):
					unit["move_fire_target"] = ""
				else:
					var move_target_position: Vector3 = _get_entity_position(fire_target)
					var move_target_distance: float = unit["position"].distance_to(move_target_position)
					if move_target_distance <= definition.attack_range and float(unit["cooldown"]) <= 0.0:
						_fire_weapon(unit, fire_target, damage_multiplier)
						unit["cooldown"] = definition.attack_cooldown
			if unit["waypoints"].is_empty() and unit["position"].distance_to(unit["target_position"]) <= 0.15:
				unit["order"] = "idle"
				unit["attack_target"] = ""
				unit["move_fire_target"] = ""
				continue
			var moving_nearby_target := _find_nearby_enemy(unit["team"], unit["position"], definition.vision_range)
			if not moving_nearby_target.is_empty() and fire_target.is_empty():
				unit["move_fire_target"] = moving_nearby_target
			continue
		if not attack_target.is_empty():
			var target_position: Vector3 = _get_entity_position(attack_target)
			var distance: float = unit["position"].distance_to(target_position)
			if distance > definition.attack_range * 0.86:
				unit["position"] = unit["position"].move_toward(target_position, definition.speed * speed_multiplier * TICK_SECONDS)
			else:
				if float(unit["cooldown"]) <= 0.0:
					_fire_weapon(unit, attack_target, damage_multiplier)
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


func _update_collector_unit(unit: Dictionary, definition, speed_multiplier: float, damage_multiplier: float) -> void:
	var collector_speed: float = definition.speed * speed_multiplier * _collector_speed_multiplier()
	var state: String = str(unit.get("collector_state", "unassigned"))
	var source_id: String = str(unit.get("collector_source_id", ""))
	var destination_id: String = str(unit.get("collector_destination_id", ""))
	var attack_target: String = str(unit.get("attack_target", ""))
	if not attack_target.is_empty() and not _entity_exists(attack_target):
		unit["attack_target"] = ""
		attack_target = ""

	var route_valid := not source_id.is_empty() and resource_nodes.has(source_id) and not destination_id.is_empty() and buildings.has(destination_id)
	if route_valid:
		var destination: Dictionary = buildings[destination_id]
		route_valid = destination["team"] == unit["team"] and destination["kind"] == "refinery" and destination["complete"]
	if not route_valid:
		unit["collector_state"] = "unassigned"
		unit["order"] = "idle"
		unit["target_position"] = unit["position"]
		unit["waypoints"] = []
		state = "unassigned"

	if not attack_target.is_empty():
		var target_position: Vector3 = _get_entity_position(attack_target)
		var distance: float = unit["position"].distance_to(target_position)
		if distance <= definition.attack_range:
			if float(unit["cooldown"]) <= 0.0:
				_fire_weapon(unit, attack_target, damage_multiplier)
				unit["cooldown"] = definition.attack_cooldown
		else:
			unit["attack_target"] = ""
			attack_target = ""

	if state == "unassigned":
		unit["order"] = "idle"
		unit["target_position"] = unit["position"]
		unit["waypoints"] = []
	elif state == "retreating":
		var home_position: Vector3 = _collector_home_position(unit)
		_advance_unit_along_route(unit, collector_speed)
		if unit["position"].distance_to(home_position) <= COLLECTOR_HOME_DISTANCE:
			if float(unit.get("collector_cargo", 0.0)) > 0.0 and buildings.has(destination_id):
				unit["collector_state"] = "to_destination"
				_set_collector_route(unit, buildings[destination_id]["position"])
			else:
				unit["collector_state"] = "to_source"
				_set_collector_route(unit, resource_nodes[source_id]["position"])
			state = str(unit["collector_state"])
	elif state == "to_source":
		var source_position: Vector3 = resource_nodes[source_id]["position"]
		_advance_unit_along_route(unit, collector_speed)
		if unit["position"].distance_to(source_position) <= COLLECTOR_HOME_DISTANCE:
			unit["collector_state"] = "loading"
			unit["collector_timer"] = _collector_load_seconds()
			unit["order"] = "idle"
			unit["waypoints"] = []
	elif state == "loading":
		unit["order"] = "idle"
		var source: Dictionary = resource_nodes[source_id]
		var previous_cargo: float = float(unit.get("collector_cargo", 0.0))
		unit["collector_timer"] = max(0.0, float(unit.get("collector_timer", 0.0)) - TICK_SECONDS)
		var load_ratio: float = clamp(1.0 - float(unit["collector_timer"]) / _collector_load_seconds(), 0.0, 1.0)
		var desired_cargo: float = float(unit["collector_capacity"]) * load_ratio
		var cargo_increment: float = min(max(0.0, desired_cargo - previous_cargo), float(source["remaining"]))
		var amount: float = previous_cargo + cargo_increment
		unit["collector_cargo"] = amount
		source["remaining"] = max(0.0, float(source["remaining"]) - cargo_increment)
		var load_complete := amount >= float(unit["collector_capacity"]) - 0.01 or float(unit["collector_timer"]) <= 0.0 or float(source["remaining"]) <= 0.0
		if load_complete:
			if amount > 0.0:
				unit["collector_state"] = "to_destination"
				_set_collector_route(unit, buildings[destination_id]["position"])
				_emit_event("ResourceCollected", {
					"unit_id": unit["id"],
					"team": unit["team"],
					"amount": amount,
					"message": "%s loaded %d energy." % [unit["display_name"], int(amount)],
				})
			else:
				unit["collector_state"] = "idle"
	elif state == "to_destination":
		var destination_position: Vector3 = buildings[destination_id]["position"]
		_advance_unit_along_route(unit, collector_speed)
		if unit["position"].distance_to(destination_position) <= COLLECTOR_HOME_DISTANCE:
			_deliver_collector_cargo(unit, destination_id)
			unit["collector_state"] = "to_source"
			_set_collector_route(unit, resource_nodes[source_id]["position"])

	var nearby_target := _find_nearby_enemy(unit["team"], unit["position"], definition.vision_range)
	if not nearby_target.is_empty():
		unit["attack_target"] = nearby_target


func _advance_unit_along_route(unit: Dictionary, movement_speed: float) -> void:
	var waypoints: Array = unit.get("waypoints", [])
	while not waypoints.is_empty() and unit["position"].distance_to(waypoints[0]) <= 0.25:
		unit["position"] = waypoints[0]
		waypoints.pop_front()
	unit["waypoints"] = waypoints
	var destination: Vector3 = unit["target_position"]
	if waypoints.is_empty() and unit["position"].distance_to(destination) <= 0.15:
		unit["position"] = destination
	else:
		var next_position: Vector3 = destination
		if not waypoints.is_empty():
			next_position = waypoints[0]
		unit["position"] = unit["position"].move_toward(next_position, movement_speed * TICK_SECONDS)


func _configure_collector_route(unit: Dictionary, source_id: String, destination_id: String) -> void:
	if not resource_nodes.has(source_id) or not buildings.has(destination_id):
		return
	unit["collector_source_id"] = source_id
	unit["collector_source_name"] = resource_nodes[source_id]["display_name"]
	unit["collector_destination_id"] = destination_id
	unit["collector_destination_name"] = buildings[destination_id]["display_name"]
	if str(unit.get("collector_home_id", "")).is_empty():
		unit["collector_home_id"] = _first_building_for_team(unit["team"], "command_hub")
	unit["collector_state"] = "to_source"
	unit["collector_timer"] = 0.0
	unit["collector_cargo"] = 0.0
	unit["attack_target"] = ""
	_set_collector_route(unit, resource_nodes[source_id]["position"])


func _set_collector_route(unit: Dictionary, destination: Vector3) -> void:
	unit["target_position"] = destination
	unit["waypoints"] = _build_navigation_path(unit["position"], destination)
	unit["order"] = "move"


func _collector_home_position(unit: Dictionary) -> Vector3:
	var home_id: String = str(unit.get("collector_home_id", ""))
	if buildings.has(home_id) and buildings[home_id]["team"] == unit["team"]:
		return buildings[home_id]["position"]
	return unit["position"]


func _begin_collector_retreat(unit_id: String) -> void:
	if not units.has(unit_id):
		return
	var unit: Dictionary = units[unit_id]
	if str(unit.get("collector_state", "")) == "retreating":
		return
	unit["collector_state"] = "retreating"
	_set_collector_route(unit, _collector_home_position(unit))
	_emit_event("CollectorRetreating", {
		"unit_id": unit_id,
		"team": unit["team"],
		"message": "%s hit — retreating to base." % unit["display_name"],
	})


func _deliver_collector_cargo(unit: Dictionary, destination_id: String) -> void:
	var amount: float = float(unit.get("collector_cargo", 0.0))
	if amount <= 0.0:
		return
	var team: String = unit["team"]
	_set_credits(team, _get_credits(team) + amount)
	unit["collector_cargo"] = 0.0
	if buildings.has(destination_id) and str(buildings[destination_id].get("completed_upgrade_id", "")) == "refining_efficiency":
		amount *= 1.25
	var destination_name: String = buildings[destination_id]["display_name"] if buildings.has(destination_id) else "base"
	_emit_event("ResourceDelivered", {
		"unit_id": unit["id"],
		"building_id": destination_id,
		"team": team,
		"amount": amount,
		"total": _get_credits(team),
		"message": "%s delivered %d energy to %s." % [unit["display_name"], int(amount), destination_name],
	})


func _build_navigation_path(start: Vector3, destination: Vector3) -> Array:
	return NavigationServiceScript.build_path(start, destination, navigation_obstacles, NAV_PATH_MARGIN, NAV_CORNER_PADDING)


func _navigation_segment_clear(from_point: Vector2, to_point: Vector2) -> bool:
	return NavigationServiceScript.segment_clear(from_point, to_point, navigation_obstacles, NAV_PATH_MARGIN)


func _update_control_points() -> void:
	_logistics().update_control_points()


func _update_forward_staging_states() -> void:
	_logistics().update_forward_staging_states()


func _is_forward_staging_active(team: String, point_id: String) -> bool:
	if not control_points.has(point_id):
		return false
	var point: Dictionary = control_points[point_id]
	return bool(point.get("staging_active", false)) and str(point.get("staging_team", "")) == team


func _active_rally_position(building: Dictionary, exit_position: Vector3) -> Vector3:
	if not bool(building.get("rally_enabled", false)) or bool(building.get("rally_suspended", false)):
		return exit_position
	return building.get("rally_position", exit_position)

func _update_economy() -> void:
	_logistics().update_economy()


func _update_supply_states() -> void:
	_logistics().update_supply_states()


func _get_connected_supply_source_ids(team: String) -> Array:
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
	return connected_ids


func _get_connected_supply_sources(team: String) -> Array:
	var positions: Array = []
	for entity_id in _get_connected_supply_source_ids(team):
		if buildings.has(entity_id):
			positions.append(buildings[entity_id]["position"])
		elif control_points.has(entity_id):
			positions.append(control_points[entity_id]["position"])
	return positions

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


func _logistics():
	if _logistics_system == null:
		_logistics_system = LogisticsSystemScript.new(self)
	return _logistics_system


func _update_ai() -> void:
	if _ai_controller == null:
		_ai_controller = AiControllerScript.new(self)
	_ai_controller.update()


func _production_queue_contains(building_id: String, unit_type: String) -> bool:
	if not buildings.has(building_id):
		return false
	for job in buildings[building_id].get("queue", []):
		if str(job.get("unit_type", "")) == unit_type:
			return true
	return false


func _check_victory() -> void:
	if match_over:
		return
	var player_hq := _first_building_for_team("player", "command_hub")
	var enemy_hq := _first_building_for_team("enemy", "command_hub")
	if player_hq.is_empty():
		match_over = true
		match_winner = "enemy"
		_emit_event("MatchLost", {"message": "Command Hub destroyed. The network has fractured."})
	elif enemy_hq.is_empty():
		match_over = true
		match_winner = "player"
		_emit_event("MatchWon", {"message": "Enemy Command Hub destroyed. The relay network is yours."})


func _apply_damage(target_id: String, damage: float, attacker_id: String) -> void:
	var attacker_position: Vector3 = _get_entity_position(attacker_id)
	if units.has(target_id):
		var target: Dictionary = units[target_id]
		var target_position: Vector3 = target["position"]
		var armour: float = unit_definitions[target["kind"]].armour
		var actual_damage: float = max(1.0, damage - armour)
		target["health"] = max(0.0, float(target["health"]) - actual_damage)
		_emit_event("UnitDamaged", {"target_id": target_id, "attacker_id": attacker_id, "attacker_position": attacker_position, "target_position": target_position, "damage": actual_damage, "health": target["health"], "max_health": target["max_health"]})
		if target["kind"] == "collector":
			_begin_collector_retreat(target_id)
		if float(target["health"]) <= 0.0:
			units.erase(target_id)
			_emit_event("UnitDestroyed", {"unit_id": target_id, "attacker_id": attacker_id, "attacker_position": attacker_position, "position": target_position, "team": target["team"], "message": "%s destroyed." % unit_definitions[target["kind"]].display_name})
	elif buildings.has(target_id):
		var building: Dictionary = buildings[target_id]
		var building_position: Vector3 = building["position"]
		var actual_damage: float = max(1.0, damage)
		building["health"] = max(0.0, float(building["health"]) - actual_damage)
		_emit_event("BuildingDamaged", {"building_id": target_id, "attacker_id": attacker_id, "attacker_position": attacker_position, "target_position": building_position, "damage": actual_damage, "health": building["health"], "max_health": building["max_health"]})
		if float(building["health"]) <= 0.0:
			buildings.erase(target_id)
			_emit_event("BuildingDestroyed", {"building_id": target_id, "attacker_id": attacker_id, "attacker_position": attacker_position, "position": building_position, "team": building["team"], "message": "%s destroyed." % building_definitions[building["kind"]].display_name})



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


func _max_units_total() -> int:
	return ForceCapacityScript.capacity(level_rules)


func _max_buildings_total() -> int:
	return max(1, int(level_rules.get("max_buildings_total", 9999)))


func _unit_limit(_team: String, _kind: String) -> int:
	# Compatibility façade: force capacity is global; unit types have no separate cap.
	return _max_units_total()


func _building_limit(_team: String, kind: String) -> int:
	var limits: Dictionary = level_rules.get("max_buildings_by_kind", {})
	return max(1, int(limits.get(kind, _max_buildings_total())))


func _count_units(team: String, kind: String = "") -> int:
	var count := 0
	for entity_id in units:
		var unit: Dictionary = units[entity_id]
		if unit["team"] == team and (kind.is_empty() or unit["kind"] == kind):
			count += 1
	return count


func _count_queued_units(team: String, kind: String = "") -> int:
	var count := 0
	for building_id in buildings:
		var building: Dictionary = buildings[building_id]
		if building["team"] != team:
			continue
		for job in building.get("queue", []):
			if kind.is_empty() or str(job.get("unit_type", "")) == kind:
				count += 1
	return count


func _count_force(team: String, include_queued: bool = true, kind: String = "") -> int:
	return ForceCapacityScript.occupied(unit_definitions, units, buildings, team, include_queued, kind)


func _force_slots_for_kind(kind: String) -> int:
	return ForceCapacityScript.slots_for_kind(unit_definitions, kind)



func _count_buildings(team: String, kind: String = "") -> int:
	var count := 0
	for entity_id in buildings:
		var building: Dictionary = buildings[entity_id]
		if building["team"] == team and (kind.is_empty() or building["kind"] == kind):
			count += 1
	return count


func _unit_queue_limit_reason(team: String, kind: String) -> String:
	return ForceCapacityScript.queue_limit_reason(unit_definitions, units, buildings, level_rules, team, kind)


func _building_limit_reason(team: String, kind: String) -> String:
	var current_total := _count_buildings(team)
	if current_total >= _max_buildings_total():
		return "Building capacity reached (%d/%d)." % [current_total, _max_buildings_total()]
	var current_kind := _count_buildings(team, kind)
	if current_kind >= _building_limit(team, kind):
		return "%s limit reached (%d/%d)." % [building_definitions[kind].display_name, current_kind, _building_limit(team, kind)]
	return ""


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
	return near_network and abs(position.x) <= level_bounds.x - 2.0 and abs(position.z) <= level_bounds.y - 2.0


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
		"move_fire_target": "",
		"collector_state": "unassigned" if kind == "collector" else "",
		"collector_source_id": "",
		"collector_source_name": "",
		"collector_destination_id": "",
		"collector_destination_name": "",
		"collector_home_id": "",
		"collector_cargo": 0.0,
		"collector_capacity": COLLECTOR_CAPACITY if kind == "collector" else 0.0,
		"collector_timer": 0.0,
		"order": "idle",
		"health": definition.max_health,
		"max_health": definition.max_health,
		"cooldown": 0.0,
		"supply_state": "connected",
		"supply_speed_multiplier": 1.0,
		"supply_damage_multiplier": 1.0,
	}
	return entity_id


func _add_collector(team: String, source_id: String, destination_id: String, home_id: String, position: Vector3) -> String:
	var entity_id := _add_unit(team, "collector", position)
	var collector: Dictionary = units[entity_id]
	collector["collector_home_id"] = home_id
	collector["collector_capacity"] = COLLECTOR_CAPACITY
	_configure_collector_route(collector, source_id, destination_id)
	return entity_id


func _add_building(team: String, kind: String, position: Vector3, under_construction := false) -> String:
	var definition = building_definitions[kind]
	var entity_id := _new_entity_id("building")
	var complete := not under_construction
	var normalized_position := Vector3(position.x, 0.0, position.z)
	var rally_enabled: bool = not str(definition.can_produce).is_empty()
	var rally_position := normalized_position
	if rally_enabled:
		var clearance: float = max(3.5, max(definition.footprint.x, definition.footprint.y) * 0.5 + 2.0)
		var direction := 1.0 if team == "player" else -1.0
		rally_position += Vector3(0.0, 0.0, direction * clearance)
	buildings[entity_id] = {
		"id": entity_id,
		"team": team,
		"kind": kind,
		"display_name": definition.display_name,
		"position": normalized_position,
		"health": definition.max_health,
		"max_health": definition.max_health,
		"complete": complete,
		"construction_progress": 1.0 if complete else 0.0,
		"queue": [],
		"rally_enabled": rally_enabled,
		"rally_position": rally_position,
		"rally_mode": "ground",
		"rally_point_id": "",
		"rally_suspended": false,
		"research_id": "",
		"research_remaining": 0.0,
		"research_total": 0.0,
		"upgrade_id": "",
		"upgrade_remaining": 0.0,
		"upgrade_total": 0.0,
		"upgrade_complete": false,
		"completed_upgrade_id": "",
	}
	return entity_id


func _add_control_point(point_id: String, display_name: String, position: Vector3, radius: float = 4.5, supports_staging := false) -> void:
	control_points[point_id] = {
		"id": point_id,
		"display_name": display_name,
		"position": position,
		"owner": "neutral",
		"capture_progress": 0.0,
		"radius": radius,
		"supports_staging": supports_staging,
		"staging_active": false,
		"staging_team": "neutral",
	}


func _add_resource_node(node_id: String, display_name: String, position: Vector3, faction_hint: float, remaining: float = 5000.0) -> void:
	resource_nodes[node_id] = {
		"id": node_id,
		"display_name": display_name,
		"position": position,
		"faction_hint": faction_hint,
		"remaining": remaining,
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

