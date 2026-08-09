extends SceneTree

const SimulationScript = preload("res://src/rts_simulation.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	var simulation = SimulationScript.new()
	root.add_child(simulation)
	simulation.start_match("relay_crossroads")
	var assembly_id := _find_entity(simulation.buildings, "assembly_bay", "player")
	var ranger_id := _find_entity(simulation.units, "ranger", "player")
	if assembly_id.is_empty() or ranger_id.is_empty():
		failures.append("staging test needs a player Assembly Bay and Ranger")
	else:
		var west: Dictionary = simulation.control_points["west_crossing"]
		simulation.units[ranger_id]["position"] = west["position"]
		simulation.units[ranger_id]["target_position"] = west["position"]
		_step_without_ai(simulation, 21)
		if simulation.control_points["west_crossing"]["owner"] != "player" or not bool(simulation.control_points["west_crossing"].get("staging_active", false)):
			failures.append("a captured connected West Crossing should become an active forward staging site")
		else:
			simulation.units[ranger_id]["health"] = 20.0
			simulation.issue_command("repair", "player", {"entity_ids": [ranger_id]})
			_step_without_ai(simulation, 1)
			if float(simulation.units[ranger_id]["health"]) <= 20.0:
				failures.append("a damaged unit should receive a paid repair inside an active staging radius")
			simulation.issue_command("set_rally_point", "player", {"building_id": assembly_id, "control_point_id": "west_crossing"})
			_step_without_ai(simulation, 1)
			var assembly: Dictionary = simulation.buildings[assembly_id]
			if str(assembly.get("rally_mode", "")) != "control_point" or str(assembly.get("rally_point_id", "")) != "west_crossing" or bool(assembly.get("rally_suspended", true)):
				failures.append("an active friendly control point should accept a named staging rally")
			simulation.control_points["west_crossing"]["owner"] = "enemy"
			simulation.control_points["west_crossing"]["capture_progress"] = -100.0
			_step_without_ai(simulation, 1)
			if not bool(simulation.buildings[assembly_id].get("rally_suspended", false)):
				failures.append("losing a staging point should suspend, rather than erase, its named rally")
			var units_before: int = simulation.units.size()
			simulation.issue_command("produce", "player", {"building_id": assembly_id, "unit_type": "ranger"})
			_step_without_ai(simulation, 45)
			if simulation.units.size() <= units_before:
				failures.append("production should continue while a staging rally is suspended")
			else:
				var produced_id := _latest_unit_of_kind(simulation.units, "ranger", "player")
				var exit_position := simulation._production_exit_position(simulation.buildings[assembly_id])
				if produced_id.is_empty() or simulation.units[produced_id]["target_position"].distance_to(exit_position) > 0.15:
					failures.append("a suspended staging rally should leave produced units at the Assembly Bay exit")
			simulation.control_points["west_crossing"]["owner"] = "player"
			simulation.control_points["west_crossing"]["capture_progress"] = 100.0
			_step_without_ai(simulation, 1)
			if bool(simulation.buildings[assembly_id].get("rally_suspended", true)):
				failures.append("recapturing a connected staging point should restore its named rally")

	var generic_sim = SimulationScript.new()
	root.add_child(generic_sim)
	generic_sim.start_match("relay_crossroads")
	var generic_assembly_id := _find_entity(generic_sim.buildings, "assembly_bay", "player")
	var ground_rally := Vector3(-12.0, 0.0, 8.0)
	generic_sim.issue_command("set_rally_point", "player", {"building_id": generic_assembly_id, "position": ground_rally})
	_step_without_ai(generic_sim, 1)
	if str(generic_sim.buildings[generic_assembly_id].get("rally_mode", "")) != "ground" or generic_sim.buildings[generic_assembly_id]["rally_position"].distance_to(ground_rally) > 0.05:
		failures.append("ordinary ground rallies should remain available")
	generic_sim.issue_command("set_rally_point", "player", {"building_id": generic_assembly_id, "control_point_id": "central_relay"})
	_step_without_ai(generic_sim, 1)
	if not _has_rejection(generic_sim, "Secure and connect"):
		failures.append("an unowned staging point should explain why rally assignment was rejected")

	var ai_sim = SimulationScript.new()
	root.add_child(ai_sim)
	ai_sim.start_match("relay_crossroads")
	ai_sim.enemy_credits = 1500.0
	for entity_id in ai_sim.units:
		if ai_sim.units[entity_id]["team"] == "player":
			ai_sim.units[entity_id]["position"] = Vector3(-45.0, 0.0, 30.0)
			ai_sim.units[entity_id]["target_position"] = ai_sim.units[entity_id]["position"]
	for _index in range(100):
		ai_sim.step_fixed()
	var enemy_assembly_id := _find_entity(ai_sim.buildings, "assembly_bay", "enemy")
	if ai_sim.control_points["east_crossing"]["owner"] != "enemy" or not bool(ai_sim.control_points["east_crossing"].get("staging_active", false)):
		failures.append("AI should secure East Crossing before its HQ assault")
	elif enemy_assembly_id.is_empty() or str(ai_sim.buildings[enemy_assembly_id].get("rally_point_id", "")) != "east_crossing":
		failures.append("AI should assign East Crossing as its staging rally through the normal command")

	if failures.is_empty():
		print("STAGING_SLICE_SMOKE_PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("STAGING_SLICE_SMOKE_FAIL")
		quit(1)


func _step_without_ai(simulation, count: int) -> void:
	for _index in range(count):
		simulation._ai_timer = 0.0
		simulation.step_fixed()


func _find_entity(entities: Dictionary, kind: String, team: String) -> String:
	for entity_id in entities:
		if entities[entity_id]["kind"] == kind and entities[entity_id]["team"] == team:
			return entity_id
	return ""


func _latest_unit_of_kind(units: Dictionary, kind: String, team: String) -> String:
	var latest_id := ""
	for entity_id in units:
		if units[entity_id]["kind"] == kind and units[entity_id]["team"] == team:
			latest_id = entity_id
	return latest_id


func _has_rejection(simulation, reason_fragment: String) -> bool:
	for event in simulation.event_history:
		if str(event.get("event_type", "")) == "OrderRejected" and str(event.get("reason", "")).find(reason_fragment) >= 0:
			return true
	return false
