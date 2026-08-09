extends SceneTree

const SimulationScript = preload("res://src/rts_simulation.gd")


func _initialize() -> void:
	var simulation = SimulationScript.new()
	root.add_child(simulation)
	simulation.start_match()

	var failures: Array[String] = []
	if simulation.units.size() < 6:
		failures.append("match should start with player and enemy units")
	if simulation.buildings.size() < 6:
		failures.append("match should start with both bases")
	if simulation.control_points.size() != 3:
		failures.append("match should start with three control points")

	var player_unit_ids := simulation.get_player_unit_ids()
	var first_unit_id: String = player_unit_ids[0] if not player_unit_ids.is_empty() else ""
	var initial_position: Vector3 = simulation.units[first_unit_id]["position"] if not first_unit_id.is_empty() else Vector3.ZERO
	simulation.issue_command("move", "player", {"entity_ids": [first_unit_id], "position": Vector3(-12.0, 0.0, 6.0)})
	_run_ticks(simulation, 20)
	if first_unit_id.is_empty() or simulation.units[first_unit_id]["position"].distance_to(initial_position) < 1.0:
		failures.append("move command should advance a unit")

	var credits_before_build: float = simulation.player_credits
	simulation.issue_command("build", "player", {"building_type": "relay", "position": Vector3(-18.0, 0.0, 12.0)})
	_run_ticks(simulation, 2)
	var relay_id := _find_entity(simulation.buildings, "relay", "player")
	if relay_id.is_empty():
		failures.append("valid relay placement should create a building")
	elif simulation.player_credits >= credits_before_build:
		failures.append("building placement should spend credits")
	_run_ticks(simulation, 45)
	if not relay_id.is_empty() and not simulation.buildings[relay_id]["complete"]:
		failures.append("relay should finish construction")

	var assembly_id := _find_entity(simulation.buildings, "assembly_bay", "player")
	var unit_count_before_production: int = simulation.units.size()
	simulation.issue_command("produce", "player", {"building_id": assembly_id, "unit_type": "raider"})
	_run_ticks(simulation, 45)
	if simulation.units.size() <= unit_count_before_production:
		failures.append("production queue should spawn a unit")

	if failures.is_empty():
		print("SIMULATION_SMOKE_PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("SIMULATION_SMOKE_FAIL")
		quit(1)


func _run_ticks(simulation, count: int) -> void:
	for _index in range(count):
		simulation.step_fixed()


func _find_entity(entities: Dictionary, kind: String, team: String) -> String:
	for entity_id in entities:
		if entities[entity_id]["kind"] == kind and entities[entity_id]["team"] == team:
			return entity_id
	return ""

