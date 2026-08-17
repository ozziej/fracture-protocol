extends SceneTree

const SimulationScript = preload("res://src/rts_simulation.gd")


func _initialize() -> void:
	await process_frame
	var failures: Array[String] = []

	var production_sim: Node = SimulationScript.new()
	root.add_child(production_sim)
	production_sim.start_match("relay_crossroads")
	var enemy_assembly_id := _find_building(production_sim, "enemy", "assembly_bay")
	var player_attacker_id := _find_unit(production_sim, "player", "ranger")
	if enemy_assembly_id.is_empty() or player_attacker_id.is_empty():
		failures.append("production destruction fixture needs an enemy Assembly Bay and player attacker")
	else:
		for _index in range(3):
			production_sim.issue_command("produce", "enemy", {"building_id": enemy_assembly_id, "unit_type": "raider"})
		production_sim.step_fixed()
		if production_sim.buildings[enemy_assembly_id].get("queue", []).size() != 3:
			failures.append("the fixture should queue three enemy Raiders before the Assembly Bay is destroyed")
		production_sim._apply_damage(enemy_assembly_id, 99999.0, player_attacker_id)
		if production_sim.buildings.has(enemy_assembly_id):
			failures.append("a destroyed Assembly Bay should be removed from the simulation")
		var completed_before := _count_production_events(production_sim, enemy_assembly_id)
		_run_ticks(production_sim, 100)
		if _count_production_events(production_sim, enemy_assembly_id) != completed_before:
			failures.append("a destroyed Assembly Bay must not complete queued units afterward")
		if _has_event(production_sim, "ProductionCompleted", "building_id", enemy_assembly_id):
			failures.append("destroying an Assembly Bay must not emit a stale ProductionCompleted event")

	var dead_source_sim: Node = SimulationScript.new()
	root.add_child(dead_source_sim)
	dead_source_sim.start_match("relay_crossroads")
	var dead_source_id := _find_building(dead_source_sim, "enemy", "assembly_bay")
	if not dead_source_id.is_empty():
		dead_source_sim.buildings[dead_source_id]["health"] = 0.0
		dead_source_sim.issue_command("produce", "enemy", {"building_id": dead_source_id, "unit_type": "raider"})
		dead_source_sim.step_fixed()
		if not _has_event(dead_source_sim, "OrderRejected", "order", "produce"):
			failures.append("a zero-health production source should reject new production orders")

	var campaign_sim: Node = SimulationScript.new()
	root.add_child(campaign_sim)
	campaign_sim.start_match("network_sever")
	var campaign_assembly_id := _find_building(campaign_sim, "enemy", "assembly_bay")
	var campaign_assembly_position: Vector3 = campaign_sim.buildings[campaign_assembly_id]["position"] if not campaign_assembly_id.is_empty() else Vector3.ZERO
	var units_before: Array = campaign_sim.units.keys()
	_run_ticks(campaign_sim, 90)
	var wave_event := _find_event(campaign_sim, "CampaignNetworkWaveStarted")
	if wave_event.is_empty():
		failures.append("Network Sever should still launch its authored reserve wave")
	else:
		if str(wave_event.get("spawn_type", "")) != "scripted_reserve":
			failures.append("campaign reserve waves should identify themselves as scripted reserves")
		var wave_position: Vector3 = wave_event.get("spawn_position", Vector3.ZERO)
		if wave_position.distance_to(campaign_assembly_position) < 10.0:
			failures.append("campaign reserve waves should enter away from the enemy Assembly Bay")
		for unit_id in campaign_sim.units:
			if units_before.has(unit_id):
				continue
			if campaign_sim.units[unit_id]["position"].distance_to(campaign_assembly_position) < 10.0:
				failures.append("scripted reserve units should not materialize at the Assembly Bay position")
				break

	if failures.is_empty():
		print("PRODUCTION_SOURCE_DESTRUCTION_PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("PRODUCTION_SOURCE_DESTRUCTION_FAIL")
		quit(1)


func _run_ticks(simulation: Node, count: int) -> void:
	for _index in range(count):
		simulation.step_fixed()


func _find_building(simulation: Node, team: String, kind: String) -> String:
	for building_id in simulation.buildings:
		var building: Dictionary = simulation.buildings[building_id]
		if str(building.get("team", "")) == team and str(building.get("kind", "")) == kind:
			return str(building_id)
	return ""


func _find_unit(simulation: Node, team: String, kind: String) -> String:
	for unit_id in simulation.units:
		var unit: Dictionary = simulation.units[unit_id]
		if str(unit.get("team", "")) == team and str(unit.get("kind", "")) == kind:
			return str(unit_id)
	return ""


func _count_production_events(simulation: Node, building_id: String) -> int:
	var count := 0
	for event in simulation.event_history:
		if str(event.get("event_type", "")) == "ProductionCompleted" and str(event.get("building_id", "")) == building_id:
			count += 1
	return count


func _has_event(simulation: Node, event_type: String, field: String, value: String) -> bool:
	for event in simulation.event_history:
		if str(event.get("event_type", "")) == event_type and str(event.get(field, "")) == value:
			return true
	return false


func _find_event(simulation: Node, event_type: String) -> Dictionary:
	for event in simulation.event_history:
		if str(event.get("event_type", "")) == event_type:
			return event
	return {}
