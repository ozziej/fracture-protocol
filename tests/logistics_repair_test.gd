extends SceneTree

const SimulationScript = preload("res://src/rts_simulation.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	var simulation = SimulationScript.new()
	root.add_child(simulation)
	simulation.start_match("relay_crossroads")
	var hub_id := _find_entity(simulation.buildings, "command_hub", "player")
	var assembly_id := _find_entity(simulation.buildings, "assembly_bay", "player")
	var refinery_id := _find_entity(simulation.buildings, "refinery", "player")
	var ranger_id := _find_entity(simulation.units, "ranger", "player")
	if hub_id.is_empty() or assembly_id.is_empty() or refinery_id.is_empty() or ranger_id.is_empty():
		failures.append("logistics test needs a player Hub, Assembly Bay, Processor, and Ranger")
	else:
		var hub_position: Vector3 = simulation.buildings[hub_id]["position"]
		var assembly_position: Vector3 = simulation.buildings[assembly_id]["position"]
		var outside_position := hub_position + Vector3(10.0, 0.0, 0.0)
		simulation.units[ranger_id]["position"] = outside_position
		simulation.units[ranger_id]["target_position"] = outside_position
		simulation.units[ranger_id]["health"] = 20.0
		simulation.issue_command("repair", "player", {"entity_ids": [ranger_id]})
		_step_without_ai(simulation, 1)
		if float(simulation.units[ranger_id]["health"]) != 20.0 or bool(simulation.units[ranger_id].get("repair_active", false)):
			failures.append("units outside a repair circle should not start repair")

		simulation.units[ranger_id]["position"] = assembly_position
		simulation.units[ranger_id]["target_position"] = assembly_position
		simulation.issue_command("repair", "player", {"entity_ids": [ranger_id]})
		_step_without_ai(simulation, 1)
		var first_repair_health: float = float(simulation.units[ranger_id]["health"])
		_step_without_ai(simulation, 10)
		if first_repair_health <= 20.0 or float(simulation.units[ranger_id]["health"]) <= first_repair_health:
			failures.append("one repair command should produce repeated incremental unit repair")
		if not _has_event(simulation, "UnitRepaired", "unit_id", ranger_id):
			failures.append("continuous unit repair should emit UnitRepaired feedback")

		simulation.units[ranger_id]["health"] = 20.0
		simulation.units[ranger_id]["position"] = hub_position
		simulation.units[ranger_id]["target_position"] = hub_position
		simulation.issue_command("repair", "player", {"entity_ids": [ranger_id]})
		_step_without_ai(simulation, 2)
		if float(simulation.units[ranger_id]["health"]) <= 20.0:
			failures.append("the Command Hub should repair combat units")

		var collector_id := simulation._add_collector("player", "", refinery_id, hub_id, simulation.buildings[refinery_id]["position"])
		if str(simulation.units[collector_id]["collector_state"]) != "to_source" or str(simulation.units[collector_id]["collector_source_id"]) != "north_field":
			failures.append("a deployed Collector should auto-start toward the nearest nearby field")
		simulation.units[collector_id]["health"] = 20.0
		simulation.units[collector_id]["position"] = hub_position
		simulation.units[collector_id]["target_position"] = hub_position
		simulation.issue_command("repair", "player", {"entity_ids": [collector_id]})
		_step_without_ai(simulation, 1)
		if float(simulation.units[collector_id]["health"]) <= 20.0:
			failures.append("the Command Hub should repair Collectors")

		var refinery: Dictionary = simulation.buildings[refinery_id]
		refinery["health"] = 100.0
		simulation.issue_command("repair", "player", {"entity_ids": [refinery_id]})
		_step_without_ai(simulation, 1)
		if float(refinery["health"]) <= 100.0 or not bool(refinery.get("repair_active", false)):
			failures.append("one building repair command should start persistent repair")

		var transfer_seconds := simulation.get_collector_transfer_seconds("player", refinery_id)
		if transfer_seconds < 3.9:
			failures.append("base Collector recovery should be deliberately slower")
		refinery["completed_upgrade_id"] = "refining_efficiency"
		if simulation.get_collector_transfer_seconds("player", refinery_id) >= transfer_seconds:
			failures.append("Refining Efficiency should shorten both collection and deposit time")

	var level_one = SimulationScript.new()
	root.add_child(level_one)
	level_one.start_match("relay_divide")
	if level_one.is_upgrade_available("refining_efficiency"):
		failures.append("building upgrades should be unavailable on the opening level")
	var level_one_refinery := _find_entity(level_one.buildings, "refinery", "player")
	if not level_one_refinery.is_empty():
		level_one.issue_command("upgrade", "player", {"building_id": level_one_refinery})
		_step_without_ai(level_one, 1)
		if not _has_event(level_one, "OrderRejected", "order", "upgrade"):
			failures.append("level-one upgrade attempts should explain that upgrades unlock later")

	if failures.is_empty():
		print("LOGISTICS_REPAIR_PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("LOGISTICS_REPAIR_FAIL")
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


func _has_event(simulation, event_type: String, field_name: String, expected_value: String) -> bool:
	for event in simulation.event_history:
		if str(event.get("event_type", "")) == event_type and str(event.get(field_name, "")) == expected_value:
			return true
	return false
