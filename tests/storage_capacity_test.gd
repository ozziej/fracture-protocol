extends SceneTree

const SimulationScript = preload("res://src/rts_simulation.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	_test_player_storage(failures)
	_test_enemy_storage_policy(failures)
	if failures.is_empty():
		print("STORAGE_CAPACITY_PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("STORAGE_CAPACITY_FAIL")
		quit(1)


func _test_player_storage(failures: Array[String]) -> void:
	var simulation = SimulationScript.new()
	root.add_child(simulation)
	simulation.start_match("relay_crossroads")
	var refinery_id: String = _find_entity(simulation.buildings, "refinery", "player")
	var hub_id: String = _find_entity(simulation.buildings, "command_hub", "player")
	var assembly_id: String = _find_entity(simulation.buildings, "assembly_bay", "player")
	if refinery_id.is_empty() or hub_id.is_empty() or assembly_id.is_empty():
		failures.append("storage test needs a player Processor, Hub, and Assembly Bay")
		return

	if absf(float(simulation.building_definitions["refinery"].storage_capacity) - 2000.0) > 0.01:
		failures.append("Resource Processor definition should expose 2,000 storage capacity")
	if absf(float(simulation.building_definitions["storage_silo"].storage_capacity) - 2000.0) > 0.01:
		failures.append("Storage Silo definition should expose 2,000 storage capacity")
	var initial_storage: Dictionary = simulation.get_storage_summary("player")
	if absf(float(initial_storage.get("capacity", 0.0)) - 2000.0) > 0.01:
		failures.append("one completed Resource Processor should provide 2,000 team storage")

	var source_id := "north_field"
	simulation.resource_nodes[source_id]["remaining"] = 600.0
	simulation.resource_nodes[source_id]["initial_remaining"] = 600.0
	simulation.resource_nodes[source_id]["depleted"] = false
	simulation.resource_nodes[source_id]["depletion_announced"] = false
	var collector_id: String = simulation._add_collector("player", source_id, refinery_id, hub_id, simulation.resource_nodes[source_id]["position"])
	simulation._set_credits("player", 2000.0)
	var remaining_before: float = float(simulation.resource_nodes[source_id]["remaining"])
	_step_without_ai(simulation, 1)
	if str(simulation.units[collector_id].get("collector_state", "")) != "storage_full":
		failures.append("a Collector should stop at a full storage network")
	if absf(float(simulation.resource_nodes[source_id]["remaining"]) - remaining_before) > 0.01:
		failures.append("a storage-blocked Collector must not drain the Energy Field")
	if not _has_event(simulation, "CollectorStorageFull", "unit_id", collector_id):
		failures.append("storage blockage should emit one readable CollectorStorageFull event")

	simulation.issue_command("produce", "player", {"building_id": assembly_id, "unit_type": "ranger"})
	_step_without_ai(simulation, 1)
	if simulation.player_credits >= 2000.0:
		failures.append("spending on a unit should immediately free storage capacity")
	if str(simulation.units[collector_id].get("collector_state", "")) == "storage_full":
		failures.append("a full Collector should resume after the player spends resources")

	var silo_id: String = simulation._add_building("player", "storage_silo", simulation.buildings[refinery_id]["position"] + Vector3(7.0, 0.0, 0.0))
	var expanded_storage: Dictionary = simulation.get_storage_summary("player")
	if absf(float(expanded_storage.get("capacity", 0.0)) - 4000.0) > 0.01:
		failures.append("a completed Storage Silo should add another 2,000 capacity")
	if absf(float(simulation.buildings[silo_id].get("storage_capacity", 0.0)) - 2000.0) > 0.01:
		failures.append("built Storage Silo state should retain its storage_capacity attribute")
	simulation._set_credits("player", 9999.0)
	if absf(simulation.player_credits - 4000.0) > 0.01:
		failures.append("credits should never exceed the combined Processor and Silo capacity")


func _test_enemy_storage_policy(failures: Array[String]) -> void:
	var simulation = SimulationScript.new()
	root.add_child(simulation)
	simulation.start_match("relay_crossroads")
	simulation._set_credits("enemy", 2000.0)
	simulation._ai_timer = 1.9
	simulation.step_fixed()
	var silo_queued: bool = false
	for command in simulation.command_queue:
		if str(command.get("type", "")) == "build" and str(command.get("payload", {}).get("building_type", "")) == "storage_silo":
			silo_queued = true
			break
	if not silo_queued:
		failures.append("AI should queue a Storage Silo when its network reaches capacity")
	else:
		simulation._ai_timer = -1000.0
		simulation.step_fixed()
		if _find_entity(simulation.buildings, "storage_silo", "enemy").is_empty():
			failures.append("AI storage-capacity response should use the normal build command")
	var enemy_storage: Dictionary = simulation.get_storage_summary("enemy")
	if float(enemy_storage.get("capacity", 0.0)) < 2000.0:
		failures.append("enemy storage capacity should use the same Processor rule as the player")


func _step_without_ai(simulation, count: int) -> void:
	for _index in range(count):
		simulation._ai_timer = -1000.0
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
