class_name RtsAiController
extends RefCounted

## Enemy policy only. It composes normal player-visible simulation commands,
## so it cannot bypass costs, queue caps, tech gates, or combat rules.
var simulation


func _init(owner) -> void:
	simulation = owner


func update() -> void:
	simulation._ai_timer += simulation.TICK_SECONDS
	if simulation._ai_timer < 2.0:
		return
	simulation._ai_timer = 0.0
	if simulation.match_over:
		return
	_manage_repairs()
	_manage_collectors()
	_manage_research()
	_manage_technology_construction()
	_manage_relay()
	_manage_staging()
	_manage_production()
	_manage_combat()


func _manage_repairs() -> void:
	var repair_ids: Array = []
	for entity_id in simulation.units:
		var unit: Dictionary = simulation.units[entity_id]
		if unit["team"] != "enemy" or float(unit["health"]) >= float(unit["max_health"]):
			continue
		if simulation._is_repair_station_nearby("enemy", unit["position"]):
			repair_ids.append(entity_id)
		elif unit["kind"] != "collector" and float(unit["health"]) <= float(unit["max_health"]) * 0.45 and str(unit.get("attack_target", "")).is_empty():
			var home_id: String = simulation._first_building_for_team("enemy", "command_hub")
			if not home_id.is_empty():
				simulation.issue_command("move", "enemy", {"entity_ids": [entity_id], "position": simulation.buildings[home_id]["position"]})
	if not repair_ids.is_empty() and simulation.enemy_credits >= simulation.REPAIR_UNIT_COST:
		simulation.issue_command("repair", "enemy", {"entity_ids": repair_ids})
	for building_id in simulation.buildings:
		var building: Dictionary = simulation.buildings[building_id]
		if building["team"] == "enemy" and building["complete"] and float(building["health"]) < float(building["max_health"]) and simulation.enemy_credits >= simulation.REPAIR_BUILDING_COST:
			simulation.issue_command("repair", "enemy", {"entity_ids": [building_id]})
			break


func _manage_collectors() -> void:
	var refinery_id: String = simulation._first_building_for_team("enemy", "refinery")
	var ai_config: Dictionary = simulation.level_definition.get("ai", {})
	var collector_source_id := str(ai_config.get("collector_source_id", "south_field"))
	if refinery_id.is_empty():
		return
	var collector_count := 0
	for entity_id in simulation.units:
		var unit: Dictionary = simulation.units[entity_id]
		if unit["team"] != "enemy" or unit["kind"] != "collector":
			continue
		collector_count += 1
		if str(unit.get("collector_state", "")) == "unassigned" and float(unit.get("collector_cargo", 0.0)) <= 0.0:
			simulation.issue_command("assign_collector", "enemy", {"collector_id": entity_id, "source_id": collector_source_id, "destination_id": refinery_id})
	if collector_count == 0 and simulation.enemy_credits >= simulation.unit_definitions["collector"].cost and not simulation._production_queue_contains(refinery_id, "collector"):
		simulation.issue_command("produce", "enemy", {"building_id": refinery_id, "unit_type": "collector"})


func _manage_technology_construction() -> void:
	if not simulation.is_level_allowed("allowed_buildings", "tech_centre") or not simulation._first_building_for_team("enemy", "tech_centre").is_empty():
		return
	var hub_id: String = simulation._first_building_for_team("enemy", "command_hub")
	if hub_id.is_empty() or simulation.enemy_credits < simulation.building_definitions["tech_centre"].cost:
		return
	var hub_position: Vector3 = simulation.buildings[hub_id]["position"]
	simulation.issue_command("build", "enemy", {"building_type": "tech_centre", "position": hub_position + Vector3(6.0, 0.0, 3.0), "source_building_id": hub_id})


func _manage_research() -> void:
	if simulation.is_technology_unlocked("enemy", "advanced_targeting"):
		return
	var tech_centre_id: String = simulation._first_building_for_team("enemy", "tech_centre")
	if tech_centre_id.is_empty():
		return
	var research_status: Dictionary = simulation.get_research_status("enemy")
	if not str(research_status.get("active_id", "")).is_empty():
		return
	var technology = simulation.technology_definitions["advanced_targeting"]
	if simulation.enemy_credits >= technology.cost:
		simulation.issue_command("research", "enemy", {"building_id": tech_centre_id, "technology_id": "advanced_targeting"})


func _manage_relay() -> void:
	for building_id in simulation.buildings:
		var existing: Dictionary = simulation.buildings[building_id]
		if existing["team"] == "enemy" and existing["kind"] == "relay":
			return
	if simulation.enemy_credits < simulation.building_definitions["relay"].cost:
		return
	var ai_config: Dictionary = simulation.level_definition.get("ai", {})
	var relay_position: Vector3 = simulation._level_vector3(ai_config.get("relay_position", Vector3(17.0, 0.0, -5.0)))
	simulation.issue_command("build", "enemy", {"building_type": "relay", "position": relay_position})


func _manage_staging() -> void:
	var ai_config: Dictionary = simulation.level_definition.get("ai", {})
	var point_id := str(ai_config.get("staging_point_id", "east_crossing"))
	if not simulation.control_points.has(point_id):
		return
	var assembly_id: String = simulation._first_building_for_team("enemy", "assembly_bay")
	if assembly_id.is_empty():
		return
	if not simulation._is_forward_staging_active("enemy", point_id):
		var capture_group: Array = []
		var player_hq_id: String = simulation._first_building_for_team("player", "command_hub")
		var player_hq_position: Vector3 = simulation.buildings[player_hq_id]["position"] if not player_hq_id.is_empty() else Vector3.INF
		for entity_id in simulation.units:
			var unit: Dictionary = simulation.units[entity_id]
			if unit["team"] == "enemy" and unit["kind"] != "collector" and unit["position"].distance_to(player_hq_position) > 20.0 and (unit["order"] == "idle" or unit["order"] == "move" or unit["order"] == "attack_move"):
				capture_group.append(entity_id)
		if not capture_group.is_empty():
			simulation.issue_command("move", "enemy", {"entity_ids": capture_group, "position": simulation.control_points[point_id]["position"]})
		return
	var assembly: Dictionary = simulation.buildings[assembly_id]
	if str(assembly.get("rally_mode", "ground")) != "control_point" or str(assembly.get("rally_point_id", "")) != point_id or bool(assembly.get("rally_suspended", false)):
		simulation.issue_command("set_rally_point", "enemy", {"building_id": assembly_id, "control_point_id": point_id})


func _manage_production() -> void:
	var assembly_id: String = simulation._first_building_for_team("enemy", "assembly_bay")
	if assembly_id.is_empty() or not simulation.buildings.has(assembly_id):
		return
	var assembly: Dictionary = simulation.buildings[assembly_id]
	var queue: Array = assembly.get("queue", [])
	if queue.size() >= 2:
		return
	var unit_type: String = "bulwark" if simulation.is_technology_unlocked("enemy", "advanced_targeting") else "raider"
	if simulation.enemy_credits >= simulation.unit_definitions[unit_type].cost:
		simulation.issue_command("produce", "enemy", {"building_id": assembly_id, "unit_type": unit_type})


func _manage_combat() -> void:
	var player_hq: String = simulation._first_building_for_team("player", "command_hub")
	var enemy_hq: String = simulation._first_building_for_team("enemy", "command_hub")
	if player_hq.is_empty() or enemy_hq.is_empty() or simulation.current_tick % 60 != 0:
		return
	var ai_config: Dictionary = simulation.level_definition.get("ai", {})
	var opening_attack_delay: int = int(ai_config.get("opening_attack_delay_ticks", 0))
	if simulation.current_tick < opening_attack_delay:
		return
	var staging_point_id := str(ai_config.get("staging_point_id", "east_crossing"))
	var immediate_hq_threat := false
	var player_hq_position: Vector3 = simulation.buildings[player_hq]["position"]
	for entity_id in simulation.units:
		var candidate: Dictionary = simulation.units[entity_id]
		if candidate["team"] == "enemy" and candidate["kind"] != "collector" and candidate["position"].distance_to(player_hq_position) <= 20.0:
			immediate_hq_threat = true
			break
	if simulation.control_points.has(staging_point_id) and not simulation._is_forward_staging_active("enemy", staging_point_id) and not immediate_hq_threat:
		return
	var attack_group: Array = []
	for entity_id in simulation.units:
		var unit: Dictionary = simulation.units[entity_id]
		if unit["team"] == "enemy" and unit["kind"] != "collector" and (unit["order"] == "idle" or unit["order"] == "move" or unit["order"] == "attack_move"):
			attack_group.append(entity_id)
	if attack_group.size() < 2:
		return
	var target_id: String = player_hq
	var enemy_hq_position: Vector3 = simulation.buildings[enemy_hq]["position"]
	var closest_threat := ""
	var closest_distance := 18.0
	for entity_id in simulation.units:
		var unit: Dictionary = simulation.units[entity_id]
		if unit["team"] != "player":
			continue
		var distance: float = unit["position"].distance_to(enemy_hq_position)
		if distance < closest_distance:
			closest_distance = distance
			closest_threat = entity_id
	if not closest_threat.is_empty():
		target_id = closest_threat
	simulation.issue_command("attack", "enemy", {"entity_ids": attack_group, "target_id": target_id})
