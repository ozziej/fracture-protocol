extends SceneTree

const SimulationScript = preload("res://src/rts_simulation.gd")


func _initialize() -> void:
	var failures: Array[String] = []

	var splash_sim = SimulationScript.new()
	root.add_child(splash_sim)
	splash_sim.start_match("relay_crossroads")
	var launcher_id := splash_sim._add_unit("enemy", "bulwark", Vector3(0.0, 0.0, 0.0))
	var primary_id := splash_sim._add_unit("player", "warden", Vector3(10.0, 0.0, 0.0))
	var grouped_id := splash_sim._add_unit("player", "warden", Vector3(10.0, 1.2, 0.0))
	splash_sim._fire_weapon(splash_sim.units[launcher_id], primary_id, 1.0)
	for _index in range(12):
		splash_sim._update_projectiles()
	if not splash_sim.units.has(primary_id) or not splash_sim.units.has(grouped_id):
		failures.append("launcher splash should not delete a pair of heavy vehicles")
	else:
		var primary_damage: float = 190.0 - float(splash_sim.units[primary_id]["health"])
		var grouped_damage: float = 190.0 - float(splash_sim.units[grouped_id]["health"])
		if grouped_damage >= primary_damage * 0.4:
			failures.append("launcher splash should be substantially weaker than the direct hit")
		if grouped_damage >= 35.0:
			failures.append("armour and splash falloff should keep a nearby Warden above half health")
	if not _has_event(splash_sim, "ProjectileLaunched") or not _has_event(splash_sim, "ProjectileImpact"):
		failures.append("launcher fire should expose launch and impact events")

	var targeting_sim = SimulationScript.new()
	root.add_child(targeting_sim)
	targeting_sim.start_match("relay_crossroads")
	var base_range: float = targeting_sim.get_effective_attack_range("player", "ranger")
	var base_vision: float = targeting_sim.get_effective_vision_range("player", "ranger")
	targeting_sim.team_technologies["player"]["advanced_targeting"] = true
	targeting_sim._refresh_team_combat_stats("player")
	var upgraded_range: float = targeting_sim.get_effective_attack_range("player", "ranger")
	var upgraded_vision: float = targeting_sim.get_effective_vision_range("player", "ranger")
	if upgraded_range <= base_range or upgraded_vision <= base_vision:
		failures.append("Advanced Targeting should visibly extend weapon and vision range")
	if abs(upgraded_range - base_range * 1.18) > 0.01 or abs(upgraded_vision - base_vision * 1.15) > 0.01:
		failures.append("Advanced Targeting should apply its authored range bonuses")

	var reaction_sim = SimulationScript.new()
	root.add_child(reaction_sim)
	reaction_sim.start_match("relay_crossroads")
	var enemy_id := _find_unit(reaction_sim, "raider", "enemy")
	var attacker_id := _find_unit(reaction_sim, "ranger", "player")
	if enemy_id.is_empty() or attacker_id.is_empty():
		failures.append("combat reaction fixture needs an enemy Raider and player Ranger")
	else:
		reaction_sim.units[enemy_id]["position"] = Vector3(18.0, 0.0, -18.0)
		reaction_sim.units[attacker_id]["position"] = Vector3(20.0, 0.0, -18.0)
		reaction_sim.units[enemy_id]["health"] = 100.0
		reaction_sim._apply_damage(enemy_id, 12.0, attacker_id)
		if str(reaction_sim.units[enemy_id].get("combat_state", "")) != "defending" or str(reaction_sim.units[enemy_id].get("attack_target", "")) != attacker_id:
			failures.append("an enemy hit above the retreat threshold should halt and defend")
		reaction_sim.units[enemy_id]["health"] = 30.0
		reaction_sim._apply_damage(enemy_id, 12.0, attacker_id)
		var retreat_position: Vector3 = reaction_sim.units[enemy_id]["retreat_position"]
		var distance_before: float = reaction_sim.units[enemy_id]["position"].distance_to(retreat_position)
		reaction_sim._update_units()
		if str(reaction_sim.units[enemy_id].get("combat_state", "")) != "retreating":
			failures.append("a heavily damaged enemy should enter retreating combat state")
		elif reaction_sim.units[enemy_id]["position"].distance_to(retreat_position) >= distance_before:
			failures.append("retreating enemies should move toward safety while retaining their threat")
		if not _has_event(reaction_sim, "AICombatReaction"):
			failures.append("enemy defensive reactions should be visible in the event stream")

	var pursuit_sim = SimulationScript.new()
	root.add_child(pursuit_sim)
	pursuit_sim.start_match("relay_crossroads")
	pursuit_sim.units.clear()
	var pursuit_player_id := pursuit_sim._add_unit("player", "ranger", Vector3.ZERO)
	var pursuit_enemy_id := pursuit_sim._add_unit("enemy", "raider", Vector3.ZERO)
	var pursuit_player: Dictionary = pursuit_sim.units[pursuit_player_id]
	var pursuit_enemy: Dictionary = pursuit_sim.units[pursuit_enemy_id]
	var pursuit_definition = pursuit_sim.unit_definitions["ranger"]
	var pursuit_distance: float = min(float(pursuit_definition.vision_range) - 1.0, pursuit_sim._attack_standoff_range(pursuit_definition, "player") + 2.0)
	pursuit_enemy["position"] = Vector3(pursuit_distance, 0.0, 0.0)
	pursuit_player["order"] = "attack_move"
	pursuit_player["target_position"] = Vector3(0.0, 0.0, 30.0)
	pursuit_player["waypoints"] = []
	for _index in range(4):
		pursuit_sim.current_tick += 1
		pursuit_sim._update_units()
	if str(pursuit_player.get("attack_target", "")) != pursuit_enemy_id or str(pursuit_player.get("attack_target_source", "")) != "opportunistic":
		failures.append("moving player units should opportunistically engage nearby contacts")
	var pursuit_cancelled := false
	for _index in range(50):
		pursuit_enemy["position"] = pursuit_player["position"] + Vector3(pursuit_distance, 0.0, 0.0)
		pursuit_sim.current_tick += 1
		pursuit_sim._update_units()
		if str(pursuit_player.get("attack_target", "")).is_empty():
			pursuit_cancelled = true
			break
	if not pursuit_cancelled:
		failures.append("opportunistic player pursuit should disengage after a short leash")
	elif str(pursuit_player.get("order", "")) not in ["auto_return", "auto_hold"]:
		failures.append("disengaged player units should return and hold before resuming their route")
	var cooldown_until: int = int(pursuit_player.get("auto_pursuit_cooldown_until_tick", 0))
	for _index in range(70):
		if str(pursuit_player.get("order", "")) == "auto_hold":
			break
		pursuit_sim.current_tick += 1
		pursuit_sim._visibility_system.invalidate()
		pursuit_sim._update_units()
	if str(pursuit_player.get("order", "")) != "auto_hold":
		failures.append("disengaged player units should reach their five-second hold")
	if cooldown_until > 0:
		pursuit_sim.current_tick = max(pursuit_sim.current_tick, cooldown_until - 1)
		pursuit_sim._update_units()
		if str(pursuit_player.get("order", "")) != "auto_hold":
			failures.append("the pursuit hold should last for the full five seconds")
		pursuit_sim.current_tick = cooldown_until
		pursuit_sim._update_units()
		if str(pursuit_player.get("order", "")) != "attack_move" or pursuit_player["target_position"].z < 29.0:
			failures.append("disengaged player units should resume their attack-move route after the hold")
	pursuit_player["position"] = Vector3.ZERO
	pursuit_player["target_position"] = Vector3.ZERO
	pursuit_enemy["position"] = pursuit_player["position"] + Vector3(pursuit_distance, 0.0, 0.0)
	pursuit_enemy["target_position"] = pursuit_enemy["position"]
	pursuit_enemy["health"] = 1000.0
	pursuit_sim._visibility_system.invalidate()
	pursuit_sim._apply_attack_command("player", {"entity_ids": [pursuit_player_id], "target_id": pursuit_enemy_id})
	for _index in range(10):
		pursuit_enemy["position"] = pursuit_player["position"] + Vector3(pursuit_distance, 0.0, 0.0)
		pursuit_sim.current_tick += 1
		pursuit_sim._visibility_system.invalidate()
		pursuit_sim._update_units()
	if str(pursuit_player.get("attack_target", "")) != pursuit_enemy_id or str(pursuit_player.get("attack_target_source", "")) != "ordered":
		failures.append("explicit player attack orders should remain committed")

	var scenario_sim = SimulationScript.new()
	root.add_child(scenario_sim)
	scenario_sim.start_match("relay_crossroads", "", {"mode": "skirmish", "scenario_id": "network_hold"})
	var player_hq_id := scenario_sim._first_building_for_team("player", "command_hub")
	var enemy_hq_id := scenario_sim._first_building_for_team("enemy", "command_hub")
	if not scenario_sim.control_points.has("network_east") or not scenario_sim.control_points.has("network_west"):
		failures.append("Network Hold should add its midfield control points")
	else:
		var east_position: Vector3 = scenario_sim.control_points["network_east"]["position"]
		var west_position: Vector3 = scenario_sim.control_points["network_west"]["position"]
		if east_position.distance_to(scenario_sim.buildings[player_hq_id]["position"]) < 30.0 or east_position.distance_to(scenario_sim.buildings[enemy_hq_id]["position"]) < 30.0:
			failures.append("East Network should be away from both bases")
		if west_position.distance_to(scenario_sim.buildings[player_hq_id]["position"]) < 30.0 or west_position.distance_to(scenario_sim.buildings[enemy_hq_id]["position"]) < 30.0:
			failures.append("West Network should be away from both bases")

	if failures.is_empty():
		print("COMBAT_ENGAGEMENT_PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("COMBAT_ENGAGEMENT_FAIL")
		quit(1)


func _find_unit(simulation, kind: String, team: String) -> String:
	for entity_id in simulation.units:
		var unit: Dictionary = simulation.units[entity_id]
		if str(unit.get("kind", "")) == kind and str(unit.get("team", "")) == team:
			return str(entity_id)
	return ""


func _has_event(simulation, event_type: String) -> bool:
	for event in simulation.event_history:
		if str(event.get("event_type", "")) == event_type:
			return true
	return false
