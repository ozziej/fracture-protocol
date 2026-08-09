extends SceneTree

const SimulationScript = preload("res://src/rts_simulation.gd")


func _initialize() -> void:
	var failures: Array[String] = []

	# Greedy opener: the starting Collector should pay back the opening economy.
	var greedy_sim = SimulationScript.new()
	root.add_child(greedy_sim)
	greedy_sim.start_match()
	var greedy_collector_id := _find_entity(greedy_sim.units, "collector", "player")
	var greedy_refinery_id := _find_entity(greedy_sim.buildings, "refinery", "player")
	_run_ticks(greedy_sim, 50)
	if greedy_collector_id.is_empty() or greedy_refinery_id.is_empty():
		failures.append("Collector should visibly travel from its resource source toward its assigned refinery")
	else:
		var greedy_collector: Dictionary = greedy_sim.units[greedy_collector_id]
		var greedy_state: String = str(greedy_collector["collector_state"])
		var greedy_target: Vector3 = greedy_sim.resource_nodes["north_field"]["position"] if greedy_state == "loading" else greedy_sim.buildings[greedy_refinery_id]["position"]
		if greedy_state != "loading" or float(greedy_collector["collector_cargo"]) <= 0.0 or float(greedy_collector["collector_cargo"]) >= float(greedy_collector["collector_capacity"]) or greedy_collector["target_position"].distance_to(greedy_target) > 0.2:
			failures.append("Collector should visibly load at a slower, partial-load pace before returning to its refinery")
	_run_ticks(greedy_sim, 70)
	if greedy_sim.player_credits <= 850.0 or not _has_team_event(greedy_sim, "ResourceDelivered", "player"):
		failures.append("greedy scenario should deliver energy during the first 12 seconds")
	else:
		var delivery_event := _first_team_event(greedy_sim, "ResourceDelivered", "player")
		if int(delivery_event.get("tick", 9999)) > 120:
			failures.append("greedy scenario delivery should arrive within the first 12 seconds")

	# Collector killed: replacing and reassigning the worker should recover the economy.
	var collector_loss_sim = SimulationScript.new()
	root.add_child(collector_loss_sim)
	collector_loss_sim.start_match()
	var lost_collector_id := _find_entity(collector_loss_sim.units, "collector", "player")
	if lost_collector_id.is_empty():
		failures.append("collector-loss scenario needs a player Collector")
	else:
		collector_loss_sim.units.erase(lost_collector_id)
		_run_ticks(collector_loss_sim, 100)
		if _has_team_event(collector_loss_sim, "ResourceDelivered", "player"):
			failures.append("a destroyed Collector should stop resource delivery")
		var assembly_id := _find_entity(collector_loss_sim.buildings, "assembly_bay", "player")
		var refinery_id := _find_entity(collector_loss_sim.buildings, "refinery", "player")
		collector_loss_sim.issue_command("produce", "player", {"building_id": assembly_id, "unit_type": "collector"})
		_run_ticks(collector_loss_sim, 37)
		var replacement_id := _find_entity(collector_loss_sim.units, "collector", "player")
		if replacement_id.is_empty():
			failures.append("collector-loss scenario should support replacement production")
		else:
			collector_loss_sim.issue_command("assign_collector", "player", {"collector_id": replacement_id, "source_id": "north_field", "destination_id": refinery_id})
			_run_ticks(collector_loss_sim, 130)
			if not _has_team_event(collector_loss_sim, "ResourceDelivered", "player"):
				failures.append("a replaced and reassigned Collector should restore income")

	# Tech-first and unit-first openings are both valid paths.
	var tech_sim = SimulationScript.new()
	root.add_child(tech_sim)
	tech_sim.start_match()
	var tech_assembly_id := _find_entity(tech_sim.buildings, "assembly_bay", "player")
	tech_sim.issue_command("research", "player", {"building_id": tech_assembly_id, "technology_id": "advanced_targeting"})
	_run_ticks(tech_sim, 1)
	if tech_sim.player_credits != 550.0:
		failures.append("tech-first opening should pay the research cost")
	_run_ticks(tech_sim, 85)
	if not tech_sim.is_technology_unlocked("player", "advanced_targeting"):
		failures.append("tech-first opening should unlock Advanced Targeting")
	tech_sim.issue_command("produce", "player", {"building_id": tech_assembly_id, "unit_type": "bulwark"})
	_run_ticks(tech_sim, 46)
	if _find_entity(tech_sim.units, "bulwark", "player").is_empty():
		failures.append("tech-first opening should produce a Bulwark after research")

	var unit_first_sim = SimulationScript.new()
	root.add_child(unit_first_sim)
	unit_first_sim.start_match()
	var unit_first_assembly_id := _find_entity(unit_first_sim.buildings, "assembly_bay", "player")
	unit_first_sim.issue_command("produce", "player", {"building_id": unit_first_assembly_id, "unit_type": "raider"})
	_run_ticks(unit_first_sim, 36)
	if _find_entity(unit_first_sim.units, "raider", "player").is_empty():
		failures.append("unit-first opening should produce a Raider")

	# Supply cut and recovery should be legible and reversible.
	var supply_sim = SimulationScript.new()
	root.add_child(supply_sim)
	supply_sim.start_match()
	var supply_unit_id := _find_entity(supply_sim.units, "ranger", "player")
	var supply_hub_id := _find_entity(supply_sim.buildings, "command_hub", "player")
	if supply_unit_id.is_empty() or supply_hub_id.is_empty():
		failures.append("supply scenario needs a Ranger and Command Hub")
	else:
		supply_sim.units[supply_unit_id]["position"] = Vector3(-1.0, 0.0, 28.0)
		supply_sim.units[supply_unit_id]["target_position"] = supply_sim.units[supply_unit_id]["position"]
		_run_ticks(supply_sim, 20)
		if supply_sim.units[supply_unit_id]["supply_state"] != "unsupplied":
			failures.append("supply cut scenario should mark a remote unit unsupplied")
		supply_sim.units[supply_unit_id]["position"] = supply_sim.buildings[supply_hub_id]["position"]
		_run_ticks(supply_sim, 5)
		if supply_sim.units[supply_unit_id]["supply_state"] != "connected":
			failures.append("supply cut scenario should recover at the Command Hub")

	# Turtle posture: a damaged structure can be held with a paid repair.
	var turtle_sim = SimulationScript.new()
	root.add_child(turtle_sim)
	turtle_sim.start_match()
	var turtle_refinery_id := _find_entity(turtle_sim.buildings, "refinery", "player")
	if turtle_refinery_id.is_empty():
		failures.append("turtle scenario needs a player Resource Processor")
	else:
		turtle_sim.buildings[turtle_refinery_id]["health"] = 100.0
		var turtle_credits: float = turtle_sim.player_credits
		turtle_sim.issue_command("repair", "player", {"entity_ids": [turtle_refinery_id]})
		_run_ticks(turtle_sim, 1)
		if turtle_sim.buildings[turtle_refinery_id]["health"] <= 100.0 or turtle_sim.player_credits >= turtle_credits:
			failures.append("turtle scenario should trade credits for structure repairs")

	# Rush posture: decisive HQ damage should resolve the MVP victory condition.
	var rush_sim = SimulationScript.new()
	root.add_child(rush_sim)
	rush_sim.start_match()
	var rush_hq_id := _find_entity(rush_sim.buildings, "command_hub", "enemy")
	var rush_unit_id := _find_entity(rush_sim.units, "warden", "player")
	if rush_hq_id.is_empty() or rush_unit_id.is_empty():
		failures.append("rush scenario needs a Warden and enemy Command Hub")
	else:
		rush_sim.buildings[rush_hq_id]["health"] = 1.0
		rush_sim.units[rush_unit_id]["position"] = rush_sim.buildings[rush_hq_id]["position"] + Vector3(-2.0, 0.0, 0.0)
		rush_sim.units[rush_unit_id]["target_position"] = rush_sim.units[rush_unit_id]["position"]
		rush_sim.issue_command("attack", "player", {"entity_ids": [rush_unit_id], "target_id": rush_hq_id})
		_run_ticks(rush_sim, 3)
		if not rush_sim.match_over or not _has_event(rush_sim, "MatchWon"):
			failures.append("rush scenario should destroy the enemy HQ and win")

	if failures.is_empty():
		print("BALANCE_SCENARIOS_PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("BALANCE_SCENARIOS_FAIL")
		quit(1)


func _run_ticks(simulation, count: int) -> void:
	for _index in range(count):
		simulation._ai_timer = 0.0
		simulation.step_fixed()


func _find_entity(entities: Dictionary, kind: String, team: String) -> String:
	for entity_id in entities:
		if entities[entity_id]["kind"] == kind and entities[entity_id]["team"] == team:
			return entity_id
	return ""


func _has_event(simulation, event_type: String) -> bool:
	for event in simulation.event_history:
		if event.get("event_type", "") == event_type:
			return true
	return false


func _has_team_event(simulation, event_type: String, team: String) -> bool:
	return not _first_team_event(simulation, event_type, team).is_empty()


func _first_team_event(simulation, event_type: String, team: String) -> Dictionary:
	for event in simulation.event_history:
		if event.get("event_type", "") == event_type and event.get("team", "") == team:
			return event
	return {}
