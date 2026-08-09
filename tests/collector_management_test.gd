extends SceneTree

const SimulationScript = preload("res://src/rts_simulation.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	var simulation = SimulationScript.new()
	root.add_child(simulation)
	simulation.start_match("relay_crossroads")
	var collector_id := _find_entity(simulation.units, "collector", "player")
	var refinery_id := _find_entity(simulation.buildings, "refinery", "player")
	var assembly_id := _find_entity(simulation.buildings, "assembly_bay", "player")
	if collector_id.is_empty() or refinery_id.is_empty() or assembly_id.is_empty():
		failures.append("collector management needs a starting Collector, Resource Processor, and Assembly Bay")
	else:
		simulation.issue_command("assign_collector", "player", {
			"collector_id": collector_id,
			"source_id": "south_field",
			"destination_id": refinery_id,
		})
		_run_ticks(simulation, 1)
		var reassigned: Dictionary = simulation.units[collector_id]
		if reassigned["collector_source_id"] != "south_field" or reassigned["collector_destination_id"] != refinery_id:
			failures.append("manual Collector assignment should persist the chosen source and refinery")
		if not _has_event(simulation, "CollectorAssigned", "unit_id", collector_id):
			failures.append("manual Collector assignment should emit CollectorAssigned")

		var units_before_queue: int = simulation.units.size()
		simulation.issue_command("produce", "player", {"building_id": assembly_id, "unit_type": "collector"})
		_run_ticks(simulation, 60)
		if simulation.units.size() <= units_before_queue:
			failures.append("Assembly Bay should produce a replacement Collector")
		else:
			var replacement_id := _find_unassigned_collector(simulation, collector_id)
			if replacement_id.is_empty():
				failures.append("a newly produced Collector should begin unassigned")
			else:
				simulation.issue_command("assign_collector", "player", {
					"collector_id": replacement_id,
					"source_id": "north_field",
					"destination_id": refinery_id,
				})
				_run_ticks(simulation, 1)
				if simulation.units[replacement_id]["collector_state"] == "unassigned":
					failures.append("replacement Collector should accept a new route")

		simulation.restart_match()
		if simulation.current_tick != 0 or simulation.match_over or simulation.player_credits != 850.0:
			failures.append("simulation restart should restore a fresh playable match")
		if _count_entities(simulation.units, "collector", "player") != 1:
			failures.append("simulation restart should restore exactly one starting player Collector")

	if failures.is_empty():
		print("COLLECTOR_MANAGEMENT_PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("COLLECTOR_MANAGEMENT_FAIL")
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


func _find_unassigned_collector(simulation, excluded_id: String) -> String:
	for entity_id in simulation.units:
		var unit: Dictionary = simulation.units[entity_id]
		if entity_id != excluded_id and unit["team"] == "player" and unit["kind"] == "collector" and unit["collector_state"] == "unassigned":
			return entity_id
	return ""


func _count_entities(entities: Dictionary, kind: String, team: String) -> int:
	var count := 0
	for entity_id in entities:
		if entities[entity_id]["kind"] == kind and entities[entity_id]["team"] == team:
			count += 1
	return count


func _has_event(simulation, event_type: String, field_name: String, expected_value: String) -> bool:
	for event in simulation.event_history:
		if event.get("event_type", "") == event_type and str(event.get(field_name, "")) == expected_value:
			return true
	return false
