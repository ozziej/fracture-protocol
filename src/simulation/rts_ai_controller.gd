class_name RtsAiController
extends RefCounted

const AiProfileScript = preload("res://src/simulation/rts_ai_profile.gd")

## Enemy policy only. It composes normal player-visible simulation commands,
## so it cannot bypass costs, queue caps, tech gates, or combat rules.
##
## Mission intent is authored in level_data.json. Difficulty changes the
## policy's timing, force thresholds, production reservations, and risk
## tolerance without changing the economy or combat definitions.
var simulation
var profile: Dictionary = {}
var difficulty_id := "standard"
var intent_id := "secure_then_assault"
var intent_display_name := "SECURE THEN ASSAULT"
var intent_message := "Secure the forward network, then assault the enemy command hub."
var target_point_id := ""
var phase := "opening"
var posture := "opening"
var map_tactic_id := "relay_first"
var map_tactic_display_name := "RELAY FIRST"
var map_tactic_message := "Secure the authored forward network before the main assault."
var map_tactic_attack_delay_multiplier := 1.0
var proactive_attack_delay_ticks := 0
var _enemy_baseline_health := 0.0
var _last_posture_change_tick := -999999
var _announced := false


func _init(owner) -> void:
	simulation = owner
	_refresh_policy()


func configure(requested_difficulty := "", requested_intent := "") -> void:
	_refresh_policy(requested_difficulty, requested_intent)


func set_difficulty(requested_difficulty: String) -> void:
	var previous_id := difficulty_id
	_refresh_policy(requested_difficulty, intent_id)
	if previous_id == difficulty_id:
		return
	_set_phase("opening")
	simulation._emit_event("AIDifficultyChanged", {
		"team": "enemy",
		"difficulty": difficulty_id,
		"message": "Enemy AI difficulty set to %s." % str(profile.get("display_name", difficulty_id)),
	})


func set_intent(requested_intent: String) -> void:
	if requested_intent.is_empty() or requested_intent == intent_id:
		return
	var intent_catalog: Dictionary = simulation.level_definition.get("ai_intents", {})
	if intent_catalog.has(requested_intent):
		var authored_intent: Dictionary = intent_catalog[requested_intent]
		intent_id = requested_intent
		intent_display_name = str(authored_intent.get("display_name", requested_intent.replace("_", " ").to_upper()))
		intent_message = str(authored_intent.get("message", intent_message))
	else:
		intent_id = requested_intent
		intent_display_name = requested_intent.replace("_", " ").to_upper()
		intent_message = "Follow the %s policy." % requested_intent.replace("_", " ")
	_set_phase("opening")
	simulation._emit_event("AIIntentChanged", {
		"team": "enemy",
		"intent": intent_id,
		"message": "Enemy AI intent changed: %s." % intent_display_name,
	})


func announce_intent() -> void:
	if _announced:
		return
	_announced = true
	simulation._emit_event("AIIntentDeclared", {
		"team": "enemy",
		"difficulty": difficulty_id,
		"intent": intent_id,
		"target_point_id": target_point_id,
		"message": "ENEMY INTENT — %s. %s" % [intent_display_name, intent_message],
	})


func get_summary() -> Dictionary:
	return {
		"difficulty": difficulty_id,
		"difficulty_display_name": str(profile.get("display_name", difficulty_id)),
		"intent": intent_id,
		"intent_display_name": intent_display_name,
		"intent_message": intent_message,
		"target_point_id": target_point_id,
		"phase": phase,
		"phase_display_name": _phase_display_name(phase),
		"posture": posture,
		"posture_display_name": _posture_display_name(posture),
		"map_tactic": map_tactic_id,
		"map_tactic_display_name": map_tactic_display_name,
		"map_tactic_message": map_tactic_message,
		"proactive_attack_delay_ticks": proactive_attack_delay_ticks,
	}


func update() -> void:
	if simulation.match_over:
		return
	var decision_interval: float = max(0.1, float(profile.get("decision_interval_seconds", 2.0)))
	simulation._ai_timer += simulation.TICK_SECONDS
	if simulation._ai_timer < decision_interval:
		return
	simulation._ai_timer = 0.0
	announce_intent()
	_update_tactical_posture()
	_update_phase()
	_manage_repairs()
	_manage_collectors()
	_manage_research()
	_manage_technology_construction()
	_manage_relay()
	_manage_staging()
	_manage_production()
	_manage_combat()


func _refresh_policy(requested_difficulty := "", requested_intent := "") -> void:
	var resolved: Dictionary = AiProfileScript.resolve(simulation.level_definition, requested_difficulty, requested_intent)
	profile = resolved.get("profile", {}).duplicate(true)
	difficulty_id = str(resolved.get("difficulty", "standard"))
	intent_id = str(resolved.get("intent", "secure_then_assault"))
	intent_display_name = str(resolved.get("intent_display_name", "SECURE THEN ASSAULT"))
	intent_message = str(resolved.get("intent_message", "Secure the forward network, then assault the enemy command hub."))
	target_point_id = str(resolved.get("target_point_id", ""))
	map_tactic_id = str(resolved.get("map_tactic_id", "relay_first"))
	map_tactic_display_name = str(resolved.get("map_tactic_display_name", map_tactic_id.replace("_", " ").to_upper()))
	map_tactic_message = str(resolved.get("map_tactic_message", "Secure the authored forward network before the main assault."))
	map_tactic_attack_delay_multiplier = max(0.25, float(resolved.get("map_tactic_attack_delay_multiplier", 1.0)))
	proactive_attack_delay_ticks = max(0, int(resolved.get("proactive_attack_delay_ticks", 0)))
	if _enemy_baseline_health <= 0.0:
		_enemy_baseline_health = _enemy_total_max_health()


func _update_phase() -> void:
	if posture == "defensive":
		_set_phase("defending")
		return
	if posture == "attacking":
		_set_phase("attacking")
		return
	var next_phase := "massing"
	var player_hq_id: String = simulation._first_building_for_team("player", "command_hub")
	var player_hq_position: Vector3 = simulation.buildings[player_hq_id]["position"] if not player_hq_id.is_empty() else Vector3.INF
	var immediate_threat := _has_enemy_unit_near_position(player_hq_position, 20.0)
	if immediate_threat:
		next_phase = "defending"
	elif _intent_requires_staging() and not target_point_id.is_empty() and simulation.control_points.has(target_point_id) and not simulation._is_forward_staging_active("enemy", target_point_id):
		next_phase = "securing"
	elif simulation._first_building_for_team("enemy", "tech_centre").is_empty() and simulation.is_level_allowed("allowed_buildings", "tech_centre"):
		next_phase = "building"
	elif not str(simulation.get_research_status("enemy").get("active_id", "")).is_empty():
		next_phase = "researching"
	elif _intent_requires_staging() and not simulation._first_building_for_team("enemy", "relay").is_empty():
		next_phase = "extending"
	elif intent_id == "raid_economy":
		next_phase = "raiding"
	_set_phase(next_phase)


func _update_tactical_posture() -> void:
	var next_posture := "opening"
	if _enemy_is_battered() or _player_is_pressuring_enemy():
		next_posture = "defensive"
	elif _player_is_passive() and _proactive_attack_window_open():
		next_posture = "attacking"
	if next_posture == posture:
		return
	var cooldown_ticks: int = max(0, int(profile.get("posture_change_cooldown_ticks", 120)))
	if simulation.current_tick - _last_posture_change_tick < cooldown_ticks:
		return
	posture = next_posture
	_last_posture_change_tick = simulation.current_tick
	if _announced:
		simulation._emit_event("AIPostureChanged", {
			"team": "enemy",
			"posture": posture,
			"map_tactic": map_tactic_id,
			"message": "Enemy posture changed to %s — %s" % [_posture_display_name(posture), _posture_reason(posture)],
		})


func _proactive_attack_window_open() -> bool:
	var difficulty_multiplier: float = max(0.25, float(profile.get("opening_attack_delay_multiplier", 1.0)))
	return simulation.current_tick >= int(float(proactive_attack_delay_ticks) * difficulty_multiplier)


func _enemy_total_max_health() -> float:
	var total := 0.0
	for unit_id in simulation.units:
		var unit: Dictionary = simulation.units[unit_id]
		if unit["team"] == "enemy":
			total += float(unit.get("max_health", 0.0))
	for building_id in simulation.buildings:
		var building: Dictionary = simulation.buildings[building_id]
		if building["team"] == "enemy":
			total += float(building.get("max_health", 0.0))
	return total


func _enemy_current_health() -> float:
	var total := 0.0
	for unit_id in simulation.units:
		var unit: Dictionary = simulation.units[unit_id]
		if unit["team"] == "enemy":
			total += float(unit.get("health", 0.0))
	for building_id in simulation.buildings:
		var building: Dictionary = simulation.buildings[building_id]
		if building["team"] == "enemy":
			total += float(building.get("health", 0.0))
	return total


func _enemy_is_battered() -> bool:
	if _enemy_baseline_health <= 0.0:
		return false
	var threshold: float = clamp(float(profile.get("defensive_health_threshold", 0.72)), 0.25, 0.95)
	return _enemy_current_health() / _enemy_baseline_health <= threshold


func _player_is_pressuring_enemy() -> bool:
	var window_ticks: int = max(60, int(profile.get("passive_window_ticks", 360)))
	var damage_events := 0
	for event in simulation.event_history:
		if simulation.current_tick - int(event.get("tick", 0)) > window_ticks:
			continue
		if (str(event.get("event_type", "")) == "UnitDamaged" or str(event.get("event_type", "")) == "BuildingDamaged") and str(event.get("attacker_team", "")) == "player":
			damage_events += 1
	return damage_events >= 3


func _player_is_passive() -> bool:
	var window_ticks: int = max(60, int(profile.get("passive_window_ticks", 360)))
	var delivery_threshold: int = max(1, int(profile.get("passive_delivery_threshold", 1)))
	var delivery_events := 0
	var active_attack := false
	for event in simulation.event_history:
		if simulation.current_tick - int(event.get("tick", 0)) > window_ticks:
			continue
		var event_type := str(event.get("event_type", ""))
		if event_type == "ResourceDelivered" and str(event.get("team", "")) == "player":
			delivery_events += 1
		if event_type == "OrderIssued" and str(event.get("team", "")) == "player" and str(event.get("order", "")) == "attack":
			active_attack = true
		if (event_type == "UnitDamaged" or event_type == "BuildingDamaged") and str(event.get("attacker_team", "")) == "player":
			active_attack = true
	return delivery_events >= delivery_threshold and not active_attack


func _posture_display_name(value: String) -> String:
	match value:
		"attacking":
			return "ATTACKING"
		"defensive":
			return "DEFENSIVE"
		_:
			return "OPENING"


func _posture_reason(value: String) -> String:
	match value:
		"attacking":
			return "your economy is active while the network is unchallenged"
		"defensive":
			return "enemy losses or direct pressure require a network defence"
		_:
			return "the authored opening is in progress"


func _set_phase(next_phase: String) -> void:
	if phase == next_phase:
		return
	phase = next_phase
	if simulation == null or not _announced:
		return
	simulation._emit_event("AIPhaseChanged", {
		"team": "enemy",
		"phase": phase,
		"intent": intent_id,
		"message": "Enemy AI phase: %s." % _phase_display_name(phase),
	})


func _phase_display_name(value: String) -> String:
	match value:
		"securing":
			return "SECURING TERRITORY"
		"building":
			return "BUILDING NETWORK"
		"researching":
			return "RESEARCHING"
		"extending":
			return "EXTENDING SUPPLY"
		"massing":
			return "MASSING FORCES"
		"attacking":
			return "ATTACKING"
		"defending":
			return "DEFENDING"
		"raiding":
			return "RAIDING ECONOMY"
		_:
			return "OPENING"


func _intent_requires_staging() -> bool:
	return intent_id == "secure_then_assault" or intent_id == "hold_network"


func _has_enemy_unit_near_position(position: Vector3, radius: float) -> bool:
	if position == Vector3.INF:
		return false
	for entity_id in simulation.units:
		var unit: Dictionary = simulation.units[entity_id]
		if unit["team"] == "enemy" and unit["kind"] != "collector" and unit["position"].distance_to(position) <= radius:
			return true
	return false


func _manage_repairs() -> void:
	var repair_ids: Array = []
	var repair_ratio: float = clamp(float(profile.get("repair_health_ratio", 0.45)), 0.1, 0.95)
	var retreat_ratio: float = clamp(float(profile.get("retreat_health_ratio", 0.45)), 0.1, 0.95)
	for entity_id in simulation.units:
		var unit: Dictionary = simulation.units[entity_id]
		if unit["team"] != "enemy" or float(unit["health"]) >= float(unit["max_health"]):
			continue
		if simulation._is_repair_station_nearby("enemy", unit["position"]) and float(unit["health"]) <= float(unit["max_health"]) * repair_ratio:
			repair_ids.append(entity_id)
		elif unit["kind"] != "collector" and float(unit["health"]) <= float(unit["max_health"]) * retreat_ratio and str(unit.get("attack_target", "")).is_empty():
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
	if refinery_id.is_empty():
		return
	var collector_source_id := _available_collector_source(str(ai_config.get("collector_source_id", "south_field")), simulation.buildings[refinery_id]["position"])
	var collector_count := 0
	for entity_id in simulation.units:
		var unit: Dictionary = simulation.units[entity_id]
		if unit["team"] != "enemy" or unit["kind"] != "collector":
			continue
		collector_count += 1
		if not collector_source_id.is_empty() and (str(unit.get("collector_state", "")) == "unassigned" or str(unit.get("collector_state", "")) == "depleted") and float(unit.get("collector_cargo", 0.0)) <= 0.0:
			simulation.issue_command("assign_collector", "enemy", {"collector_id": entity_id, "source_id": collector_source_id, "destination_id": refinery_id})
	if collector_count == 0 and not collector_source_id.is_empty() and simulation.enemy_credits >= simulation.unit_definitions["collector"].cost and not simulation._production_queue_contains(refinery_id, "collector"):
		simulation.issue_command("produce", "enemy", {"building_id": refinery_id, "unit_type": "collector"})


func _available_collector_source(preferred_id: String, origin: Vector3) -> String:
	if simulation.resource_nodes.has(preferred_id) and float(simulation.resource_nodes[preferred_id].get("remaining", 0.0)) > simulation.RESOURCE_EPSILON:
		return preferred_id
	var closest_id := ""
	var closest_distance := INF
	for resource_id in simulation.resource_nodes:
		var resource: Dictionary = simulation.resource_nodes[resource_id]
		if float(resource.get("remaining", 0.0)) <= simulation.RESOURCE_EPSILON:
			continue
		var distance: float = origin.distance_to(resource["position"])
		if distance < closest_distance:
			closest_distance = distance
			closest_id = str(resource_id)
	return closest_id


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
	if intent_id == "pressure_hq" or intent_id == "raid_economy":
		return
	var point_id := target_point_id
	if point_id.is_empty() or not simulation.control_points.has(point_id):
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
		var capture_group_size: int = max(1, int(profile.get("capture_group_size", 3)))
		if capture_group.size() < capture_group_size:
			return
		capture_group = capture_group.slice(0, capture_group_size)
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
	var queue_target: int = clamp(int(profile.get("production_queue_target", 2)), 1, simulation.MAX_PRODUCTION_QUEUE)
	if queue.size() >= queue_target:
		return
	var unit_type: String = "bulwark" if simulation.is_technology_unlocked("enemy", "advanced_targeting") else "raider"
	if simulation.enemy_credits >= simulation.unit_definitions[unit_type].cost:
		simulation.issue_command("produce", "enemy", {"building_id": assembly_id, "unit_type": unit_type})


func _manage_combat() -> void:
	var player_hq: String = simulation._first_building_for_team("player", "command_hub")
	var enemy_hq: String = simulation._first_building_for_team("enemy", "command_hub")
	var attack_interval: int = max(1, int(profile.get("attack_reissue_ticks", 60)))
	if player_hq.is_empty() or enemy_hq.is_empty() or simulation.current_tick % attack_interval != 0:
		return
	var ai_config: Dictionary = simulation.level_definition.get("ai", {})
	var opening_attack_delay: int = int(float(ai_config.get("opening_attack_delay_ticks", 0)) * float(profile.get("opening_attack_delay_multiplier", 1.0)) * map_tactic_attack_delay_multiplier)
	var immediate_hq_threat: bool = _has_enemy_unit_near_position(simulation.buildings[player_hq]["position"], 20.0)
	if posture == "defensive":
		var defensive_target := _nearest_player_unit_to(simulation.buildings[enemy_hq]["position"], 24.0)
		if defensive_target.is_empty() and not immediate_hq_threat:
			return
		opening_attack_delay = 0
	elif posture == "attacking":
		opening_attack_delay = 0
	if simulation.current_tick < opening_attack_delay and not immediate_hq_threat:
		return
	if _intent_requires_staging() and not target_point_id.is_empty() and simulation.control_points.has(target_point_id) and not simulation._is_forward_staging_active("enemy", target_point_id) and not immediate_hq_threat:
		return
	if intent_id == "hold_network" and not immediate_hq_threat:
		var network_target := _nearest_player_unit_to(simulation.control_points[target_point_id]["position"] if simulation.control_points.has(target_point_id) else simulation.buildings[enemy_hq]["position"])
		if network_target.is_empty():
			return
	var attack_group: Array = []
	for entity_id in simulation.units:
		var unit: Dictionary = simulation.units[entity_id]
		if unit["team"] == "enemy" and unit["kind"] != "collector" and (unit["order"] == "idle" or unit["order"] == "move" or unit["order"] == "attack_move"):
			attack_group.append(entity_id)
	var minimum_attack_group_size: int = max(2, int(ai_config.get("minimum_attack_group_size", 2)) + int(profile.get("minimum_attack_group_size_delta", 0)))
	if attack_group.size() < minimum_attack_group_size:
		return
	var target_id := _select_attack_target(player_hq, enemy_hq)
	if target_id.is_empty():
		return
	simulation.issue_command("attack", "enemy", {"entity_ids": attack_group, "target_id": target_id})
	_set_phase("attacking")


func _select_attack_target(player_hq: String, enemy_hq: String) -> String:
	if posture == "defensive":
		var defensive_target := _nearest_player_unit_to(simulation.buildings[enemy_hq]["position"], 24.0)
		if not defensive_target.is_empty():
			return defensive_target
	if posture == "attacking":
		var economy_target := _nearest_player_economic_target(simulation.buildings[enemy_hq]["position"])
		if not economy_target.is_empty():
			return economy_target
	if intent_id == "raid_economy":
		var raid_target := _nearest_player_economic_target(simulation.buildings[enemy_hq]["position"])
		if not raid_target.is_empty():
			return raid_target
	if intent_id == "hold_network" and not target_point_id.is_empty() and simulation.control_points.has(target_point_id):
		var network_target := _nearest_player_unit_to(simulation.control_points[target_point_id]["position"])
		if not network_target.is_empty():
			return network_target
	var target_id := player_hq
	var enemy_hq_position: Vector3 = simulation.buildings[enemy_hq]["position"]
	var closest_threat := _nearest_player_unit_to(enemy_hq_position, 18.0)
	if not closest_threat.is_empty():
		target_id = closest_threat
	return target_id


func _nearest_player_economic_target(origin: Vector3) -> String:
	var nearest_id := ""
	var nearest_distance := INF
	for entity_id in simulation.units:
		var unit: Dictionary = simulation.units[entity_id]
		if unit["team"] != "player" or unit["kind"] != "collector":
			continue
		if not simulation.is_entity_visible_to_team("enemy", entity_id):
			continue
		var distance: float = unit["position"].distance_to(origin)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_id = entity_id
	if not nearest_id.is_empty():
		return nearest_id
	for building_id in simulation.buildings:
		var building: Dictionary = simulation.buildings[building_id]
		if building["team"] == "player" and building["kind"] == "refinery":
			if not simulation.is_entity_visible_to_team("enemy", building_id):
				continue
			var distance: float = building["position"].distance_to(origin)
			if distance < nearest_distance:
				nearest_distance = distance
				nearest_id = building_id
	return nearest_id


func _nearest_player_unit_to(origin: Vector3, max_distance := INF) -> String:
	var nearest_id := ""
	var nearest_distance: float = max_distance
	for entity_id in simulation.units:
		var unit: Dictionary = simulation.units[entity_id]
		if unit["team"] != "player":
			continue
		if not simulation.is_entity_visible_to_team("enemy", entity_id):
			continue
		var distance: float = unit["position"].distance_to(origin)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_id = entity_id
	return nearest_id
