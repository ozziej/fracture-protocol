class_name RtsLogisticsSystem
extends RefCounted

## Owns the periodic territory, staging, supply, and passive-income updates.
## Query helpers remain on the simulation façade for command validation and UI.
var simulation


func _init(owner) -> void:
	simulation = owner


func update_control_points() -> void:
	for point_id in simulation.control_points.keys():
		var point: Dictionary = simulation.control_points[point_id]
		var player_count: int = simulation._count_units_in_radius("player", point["position"], point["radius"])
		var enemy_count: int = simulation._count_units_in_radius("enemy", point["position"], point["radius"])
		if player_count == enemy_count:
			continue
		var pressure := 5.0 if player_count > enemy_count else -5.0
		pressure *= max(0.1, float(point.get("capture_rate_multiplier", 1.0)))
		point["capture_progress"] = clamp(float(point["capture_progress"]) + pressure, -100.0, 100.0)
		if float(point["capture_progress"]) >= 100.0 and point["owner"] != "player":
			point["owner"] = "player"
			simulation._emit_event("TerritoryCaptured", {"point_id": point_id, "team": "player", "role": point.get("strategic_role", ""), "message": "%s secured — %s" % [point["display_name"], point.get("role_description", "territory advantage online")]})
		elif float(point["capture_progress"]) <= -100.0 and point["owner"] != "enemy":
			point["owner"] = "enemy"
			simulation._emit_event("TerritoryCaptured", {"point_id": point_id, "team": "enemy", "role": point.get("strategic_role", ""), "message": "%s lost — %s is now available to the opponent." % [point["display_name"], point.get("role_label", "territory benefit")]})


func update_forward_staging_states() -> void:
	var player_connected_ids: Array = simulation._get_connected_supply_source_ids("player")
	var enemy_connected_ids: Array = simulation._get_connected_supply_source_ids("enemy")
	for point_id in simulation.control_points:
		var point: Dictionary = simulation.control_points[point_id]
		var owner: String = str(point.get("owner", "neutral"))
		var active: bool = bool(point.get("supports_staging", false)) and (owner == "player" or owner == "enemy")
		if active:
			var connected_ids: Array = player_connected_ids if owner == "player" else enemy_connected_ids
			active = connected_ids.has(point_id)
		var was_active := bool(point.get("staging_active", false))
		var previous_team := str(point.get("staging_team", "neutral"))
		point["staging_active"] = active
		point["staging_team"] = owner if active else "neutral"
		if active and not was_active:
			simulation._emit_event("ForwardStagingActivated", {"point_id": point_id, "team": owner, "message": "%s is online — %s." % [point["display_name"], point.get("role_description", "forward staging available")]})
		elif not active and was_active:
			simulation._emit_event("ForwardStagingDeactivated", {"point_id": point_id, "team": previous_team, "message": "%s is offline — its connected staging benefits are unavailable." % point["display_name"]})
	_update_staging_rallies()


func _update_staging_rallies() -> void:
	for building_id in simulation.buildings:
		var building: Dictionary = simulation.buildings[building_id]
		if str(building.get("rally_mode", "ground")) != "control_point":
			continue
		var point_id := str(building.get("rally_point_id", ""))
		var active: bool = simulation.control_points.has(point_id) and simulation._is_forward_staging_active(str(building["team"]), point_id)
		var suspended := bool(building.get("rally_suspended", false))
		if active:
			building["rally_position"] = simulation.control_points[point_id]["position"]
			if suspended:
				building["rally_suspended"] = false
				simulation._emit_event("RallyPointRestored", {"building_id": building_id, "control_point_id": point_id, "team": building["team"], "message": "%s staging rally restored at %s." % [building["display_name"], simulation.control_points[point_id]["display_name"]]})
		elif not suspended:
			building["rally_suspended"] = true
			var point_name := str(simulation.control_points[point_id].get("display_name", "the staging site")) if simulation.control_points.has(point_id) else "the staging site"
			simulation._emit_event("RallyPointSuspended", {"building_id": building_id, "control_point_id": point_id, "team": building["team"], "message": "%s staging rally suspended — %s is not connected." % [building["display_name"], point_name]})


func update_economy() -> void:
	simulation._economy_timer += simulation.TICK_SECONDS
	if simulation._economy_timer < 1.0:
		return
	simulation._economy_timer -= 1.0
	var player_income: float = simulation._income_for_team("player")
	var enemy_income: float = simulation._income_for_team("enemy")
	simulation.player_credits += player_income
	simulation.enemy_credits += enemy_income
	simulation._emit_event("ResourceChanged", {"team": "player", "amount": player_income, "total": simulation.player_credits})


func update_supply_states() -> void:
	for entity_id in simulation.units:
		var unit: Dictionary = simulation.units[entity_id]
		if bool(simulation.level_rules.get("supply_disabled", false)):
			unit["supply_state"] = "connected"
			unit["supply_reason"] = "Mission supply rules are active"
			unit["supply_speed_multiplier"] = 1.0
			unit["supply_damage_multiplier"] = 1.0
			continue
		var supply_info: Dictionary = _supply_info(str(unit["team"]), unit["position"])
		var connected: bool = bool(supply_info.get("connected", false))
		var next_state: String = "connected" if connected else "unsupplied"
		var previous_state: String = unit.get("supply_state", "connected")
		unit["supply_state"] = next_state
		unit["supply_reason"] = str(supply_info.get("reason", "Outside the connected network."))
		unit["supply_speed_multiplier"] = 1.0 if connected else simulation.UNSUPPLIED_SPEED_MULTIPLIER
		unit["supply_damage_multiplier"] = 1.0 if connected else simulation.UNSUPPLIED_DAMAGE_MULTIPLIER
		if previous_state != next_state:
			var message := "%s resupplied — %s." % [unit["display_name"], unit["supply_reason"]] if connected else "%s is UNSUPPLIED — move nearer to a connected Hub, Relay, or forward base." % unit["display_name"]
			simulation._emit_event("SupplyStateChanged", {"unit_id": entity_id, "team": unit["team"], "state": next_state, "reason": unit["supply_reason"], "message": message})


func _supply_info(team: String, position: Vector3) -> Dictionary:
	var connected_source_ids: Array = simulation._get_connected_supply_source_ids(team)
	var connected_source_positions: Array = []
	var closest_source_name := ""
	var closest_source_distance := INF
	for source_id in connected_source_ids:
		var source_position := Vector3.INF
		var source_name := "connected network"
		if simulation.buildings.has(source_id):
			source_position = simulation.buildings[source_id]["position"]
			source_name = str(simulation.buildings[source_id]["display_name"])
		elif simulation.control_points.has(source_id):
			source_position = simulation.control_points[source_id]["position"]
			source_name = str(simulation.control_points[source_id]["display_name"])
		if source_position == Vector3.INF:
			continue
		connected_source_positions.append({"position": source_position, "name": source_name})
		var source_distance: float = position.distance_to(source_position)
		if source_distance < closest_source_distance:
			closest_source_distance = source_distance
			closest_source_name = source_name
		if source_distance <= simulation.SUPPLY_EFFECT_RADIUS:
			return {"connected": true, "reason": "Within %s supply radius" % source_name}

	# A completed friendly structure connected to the network acts as a small
	# forward base. This keeps units beside a Processor/Assembly/Tech Centre
	# supplied without making every building a new network source.
	for building_id in simulation.buildings:
		var building: Dictionary = simulation.buildings[building_id]
		if building["team"] != team or not building["complete"]:
			continue
		var building_position: Vector3 = building["position"]
		var building_connected := false
		for source in connected_source_positions:
			if building_position.distance_to(source["position"]) <= simulation.SUPPLY_LINK_RADIUS:
				building_connected = true
				break
		if building_connected and position.distance_to(building_position) <= simulation.SUPPLY_EFFECT_RADIUS:
			return {"connected": true, "reason": "Forward base: %s" % building["display_name"]}
	return {"connected": false, "reason": "Outside the connected network%s" % (" near %s" % closest_source_name if not closest_source_name.is_empty() else "")}
