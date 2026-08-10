extends SceneTree

const SimulationScript = preload("res://src/rts_simulation.gd")
const MainScript = preload("res://src/main.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	var simulation = SimulationScript.new()
	root.add_child(simulation)
	simulation.start_match("relay_crossroads")

	var ranger_definition = simulation.unit_definitions["ranger"]
	var bulwark_definition = simulation.unit_definitions["bulwark"]
	if float(ranger_definition.vision_range) <= float(simulation.unit_definitions["raider"].vision_range):
		failures.append("Ranger should have the longest baseline combat vision")
	if float(bulwark_definition.attack_range) < 18.0 or float(bulwark_definition.minimum_attack_range) < 6.0:
		failures.append("Bulwark should have extended maximum range and a meaningful minimum range")

	var enemy_hq_id := _find_building(simulation, "enemy", "command_hub")
	var player_state: Dictionary = simulation.get_state("player")
	if player_state["buildings"].has(enemy_hq_id):
		failures.append("Enemy Command Hub should remain hidden outside player vision")
	if player_state.get("visibility", {}).get("hidden_cells", PackedVector3Array()).is_empty():
		failures.append("Player fog state should include hidden cells at match start")

	var scout_id := simulation._add_unit("player", "ranger", simulation.buildings[enemy_hq_id]["position"] + Vector3(2.0, 0.0, 0.0))
	simulation._visibility_system.invalidate()
	player_state = simulation.get_state("player")
	if not player_state["buildings"].has(enemy_hq_id):
		failures.append("Ranger vision should reveal the enemy Command Hub")
	var enemy_hq_marker_state := str(player_state["control_points"].get("east_crossing", {}).get("visibility_state", "hidden"))
	if enemy_hq_marker_state == "hidden":
		failures.append("Ranger vision should reveal nearby map markers")
	simulation.units[scout_id]["position"] = Vector3(-20.0, 0.0, 20.0)
	simulation._visibility_system.invalidate()
	player_state = simulation.get_state("player")
	if player_state["buildings"].has(enemy_hq_id):
		failures.append("Enemy Command Hub should disappear again when the Ranger leaves vision")
	if str(player_state["buildings"].get(enemy_hq_id, {}).get("visibility_state", "")) == "visible":
		failures.append("Filtered enemy buildings should not leak stale visible state")

	var hidden_player_id := simulation._add_unit("player", "ranger", Vector3.ZERO)
	simulation._visibility_system.invalidate()
	var enemy_state: Dictionary = simulation.get_state("enemy")
	if enemy_state["units"].has(hidden_player_id):
		failures.append("Enemy snapshot should hide player units outside enemy vision")

	var far_range_sim = SimulationScript.new()
	root.add_child(far_range_sim)
	far_range_sim.start_match("relay_crossroads")
	var far_bulwark_id := far_range_sim._add_unit("player", "bulwark", Vector3.ZERO)
	var far_target_id := far_range_sim._add_unit("enemy", "raider", Vector3(18.0, 0.0, 0.0))
	far_range_sim.units[far_target_id]["vision_range"] = 0.1
	far_range_sim.issue_command("attack", "player", {"entity_ids": [far_bulwark_id], "target_id": far_target_id})
	_step_without_ai(far_range_sim, 1)
	if not _has_event(far_range_sim, "ProjectileLaunched"):
		failures.append("Bulwark should fire at targets in its extended range")
	if float(far_range_sim.units[far_target_id]["health"]) != float(far_range_sim.unit_definitions["raider"].max_health):
		failures.append("Bulwark damage should remain delayed until missile impact")

	var close_range_sim = SimulationScript.new()
	root.add_child(close_range_sim)
	close_range_sim.start_match("relay_crossroads")
	var close_bulwark_id := close_range_sim._add_unit("player", "bulwark", Vector3.ZERO)
	var close_target_id := close_range_sim._add_unit("enemy", "raider", Vector3(6.0, 0.0, 0.0))
	close_range_sim.units[close_target_id]["vision_range"] = 0.1
	close_range_sim.issue_command("attack", "player", {"entity_ids": [close_bulwark_id], "target_id": close_target_id})
	_step_without_ai(close_range_sim, 1)
	var close_distance: float = close_range_sim.units[close_bulwark_id]["position"].distance_to(close_range_sim.units[close_target_id]["position"])
	if close_distance <= 6.0 or _has_event(close_range_sim, "ProjectileLaunched"):
		failures.append("Bulwark should back away and refuse fire inside its minimum range")

	var game = MainScript.new()
	root.add_child(game)
	await process_frame
	if game.fog_view == null or game.fog_view.fog_mesh == null or game.fog_view.fog_mesh.get_surface_count() == 0:
		failures.append("Graphical match should create and populate the fog-of-war overlay")
	if game.minimap.snapshot.get("visibility", {}).get("hidden_cells", PackedVector3Array()).is_empty():
		failures.append("Minimap snapshot should carry the same hidden-cell state")
	var graphical_enemy_hq_id := _find_building(game.simulation, "enemy", "command_hub")
	if game.building_views.has(graphical_enemy_hq_id) or game.minimap.snapshot["buildings"].has(graphical_enemy_hq_id):
		failures.append("Hidden enemy buildings should not be present in world or minimap presentation")
	game.simulation._add_unit("player", "ranger", game.simulation.buildings[graphical_enemy_hq_id]["position"])
	game.simulation._visibility_system.invalidate()
	game._sync_views()
	if not game.building_views.has(graphical_enemy_hq_id) or not game.minimap.snapshot["buildings"].has(graphical_enemy_hq_id):
		failures.append("A Ranger reveal should restore the enemy building to world and minimap presentation")
	game.queue_free()

	if failures.is_empty():
		print("FOG_OF_WAR_COMBAT_PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("FOG_OF_WAR_COMBAT_FAIL")
		quit(1)


func _step_without_ai(simulation, count: int) -> void:
	for _index in range(count):
		simulation._ai_timer = 0.0
		simulation.step_fixed()


func _find_building(simulation, team: String, kind: String) -> String:
	for building_id in simulation.buildings:
		var building: Dictionary = simulation.buildings[building_id]
		if building["team"] == team and building["kind"] == kind:
			return building_id
	return ""


func _has_event(simulation, event_type: String) -> bool:
	for event in simulation.event_history:
		if str(event.get("event_type", "")) == event_type:
			return true
	return false
