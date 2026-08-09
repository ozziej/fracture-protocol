extends SceneTree

const SimulationScript = preload("res://src/rts_simulation.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	var ai_sim = SimulationScript.new()
	root.add_child(ai_sim)
	ai_sim.start_match()
	ai_sim.enemy_credits = 1500.0
	var player_hq_id := _find_entity(ai_sim.buildings, "command_hub", "player")
	if not player_hq_id.is_empty():
		ai_sim.buildings[player_hq_id]["health"] = 100000.0
	var enemy_refinery_id := _find_entity(ai_sim.buildings, "refinery", "enemy")
	var damaged_enemy_id := _find_entity(ai_sim.units, "raider", "enemy")
	if enemy_refinery_id.is_empty() or damaged_enemy_id.is_empty():
		failures.append("AI test needs an enemy refinery and Raider")
	else:
		ai_sim.units[damaged_enemy_id]["position"] = ai_sim.buildings[enemy_refinery_id]["position"]
		ai_sim.units[damaged_enemy_id]["target_position"] = ai_sim.units[damaged_enemy_id]["position"]
		ai_sim.units[damaged_enemy_id]["health"] = 45.0
		_run_ticks(ai_sim, 80)
		if not ai_sim.units.has(damaged_enemy_id) or float(ai_sim.units[damaged_enemy_id]["health"]) <= 45.0:
			failures.append("AI should repair a damaged unit at its repair station")
		if not _has_event(ai_sim, "UnitRepaired", "unit_id", damaged_enemy_id):
			failures.append("AI repair should emit UnitRepaired feedback")
		_run_ticks(ai_sim, 570)
		if not ai_sim.is_technology_unlocked("enemy", "advanced_targeting"):
			failures.append("AI should research Advanced Targeting using its own credits")
		if _find_entity(ai_sim.buildings, "relay", "enemy").is_empty():
			failures.append("AI should build a Forward Relay")
		if not _has_team_event(ai_sim, "ResourceDelivered", "enemy"):
			failures.append("AI Collector should deliver resources through the shared economy")
		if not _has_team_event(ai_sim, "ProductionCompleted", "enemy"):
			failures.append("AI should complete at least one production queue")
		if not _has_order_event(ai_sim, "attack", "enemy"):
			failures.append("AI should issue a coordinated attack order")

	var replacement_sim = SimulationScript.new()
	root.add_child(replacement_sim)
	replacement_sim.start_match()
	replacement_sim.enemy_credits = 1000.0
	var enemy_collector_id := _find_entity(replacement_sim.units, "collector", "enemy")
	if enemy_collector_id.is_empty():
		failures.append("AI replacement test needs a starting enemy Collector")
	else:
		replacement_sim.units.erase(enemy_collector_id)
		_run_ticks(replacement_sim, 180)
		var replacement_id := _find_entity(replacement_sim.units, "collector", "enemy")
		if replacement_id.is_empty():
			failures.append("AI should replace a destroyed Collector")
		elif replacement_sim.units[replacement_id]["collector_state"] == "unassigned":
			failures.append("AI replacement Collector should receive a route")

	var loss_sim = SimulationScript.new()
	root.add_child(loss_sim)
	loss_sim.start_match()
	var loss_hq_id := _find_entity(loss_sim.buildings, "command_hub", "player")
	var loss_attacker_id := _find_entity(loss_sim.units, "raider", "enemy")
	if loss_hq_id.is_empty() or loss_attacker_id.is_empty():
		failures.append("loss test needs an enemy Raider and player Command Hub")
	else:
		loss_sim.buildings[loss_hq_id]["health"] = 1.0
		loss_sim.units[loss_attacker_id]["position"] = loss_sim.buildings[loss_hq_id]["position"] + Vector3(2.0, 0.0, 0.0)
		loss_sim.units[loss_attacker_id]["target_position"] = loss_sim.units[loss_attacker_id]["position"]
		loss_sim.issue_command("attack", "enemy", {"entity_ids": [loss_attacker_id], "target_id": loss_hq_id})
		_run_ticks(loss_sim, 3)
		if not loss_sim.match_over or not _has_event(loss_sim, "MatchLost", "message", "Command Hub destroyed. The network has fractured."):
			failures.append("destroying the player Command Hub should end the match in defeat")

	var ai_match_sim = SimulationScript.new()
	root.add_child(ai_match_sim)
	ai_match_sim.start_match()
	var ai_match_hq_id := _find_entity(ai_match_sim.buildings, "command_hub", "player")
	if ai_match_hq_id.is_empty():
		failures.append("AI match-end test needs a player Command Hub")
	else:
		ai_match_sim.buildings[ai_match_hq_id]["health"] = 300.0
		for entity_id in ai_match_sim.units:
			if ai_match_sim.units[entity_id]["team"] == "player":
				ai_match_sim.units[entity_id]["position"] = Vector3(0.0, 0.0, 30.0)
				ai_match_sim.units[entity_id]["target_position"] = ai_match_sim.units[entity_id]["position"]
		var placed := 0
		for entity_id in ai_match_sim.units:
			var unit: Dictionary = ai_match_sim.units[entity_id]
			if unit["team"] != "enemy" or unit["kind"] == "collector":
				continue
			unit["position"] = ai_match_sim.buildings[ai_match_hq_id]["position"] + Vector3(12.0 + float(placed), 0.0, float(placed))
			unit["target_position"] = unit["position"]
			unit["health"] = 10000.0
			placed += 1
		_run_ticks(ai_match_sim, 180)
		if not ai_match_sim.match_over or not _has_event(ai_match_sim, "MatchLost", "message", "Command Hub destroyed. The network has fractured."):
			failures.append("AI should be able to finish a vulnerable skirmish through its normal attack behavior")

	var normal_match_sim = SimulationScript.new()
	root.add_child(normal_match_sim)
	normal_match_sim.start_match()
	_run_ticks(normal_match_sim, 1800)
	if not normal_match_sim.match_over:
		failures.append("a normal no-input AI skirmish should reach a win/loss state within three minutes")

	if failures.is_empty():
		print("AI_SKIRMISH_PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("AI_SKIRMISH_FAIL")
		quit(1)


func _run_ticks(simulation, count: int) -> void:
	for _index in range(count):
		simulation.step_fixed()


func _find_entity(entities: Dictionary, kind: String, team: String) -> String:
	for entity_id in entities:
		if entities[entity_id]["kind"] == kind and entities[entity_id]["team"] == team:
			return entity_id
	return ""


func _has_event(simulation, event_type: String, field_name: String, expected_value: String) -> bool:
	for event in simulation.event_history:
		if event.get("event_type", "") == event_type and str(event.get(field_name, "")) == expected_value:
			return true
	return false


func _has_team_event(simulation, event_type: String, team: String) -> bool:
	for event in simulation.event_history:
		if event.get("event_type", "") == event_type and event.get("team", "") == team:
			return true
	return false


func _has_order_event(simulation, order: String, team: String) -> bool:
	for event in simulation.event_history:
		if event.get("event_type", "") == "OrderIssued" and event.get("order", "") == order and event.get("team", "") == team:
			return true
	return false
