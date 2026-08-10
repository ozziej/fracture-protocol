extends SceneTree

const MainScript = preload("res://src/main.gd")
const SimulationScript = preload("res://src/rts_simulation.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	_test_finite_resources(failures)
	_test_adaptive_ai(failures)
	await _test_player_hud_and_placement(failures)
	_test_building_survivability(failures)
	if failures.is_empty():
		print("ECONOMY_ADAPTIVE_UX_PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("ECONOMY_ADAPTIVE_UX_FAIL")
		quit(1)


func _test_finite_resources(failures: Array[String]) -> void:
	var simulation = SimulationScript.new()
	root.add_child(simulation)
	simulation.start_match("relay_crossroads")
	var refinery_id := _find_entity(simulation.buildings, "refinery", "player")
	var hub_id := _find_entity(simulation.buildings, "command_hub", "player")
	if refinery_id.is_empty() or hub_id.is_empty():
		failures.append("finite-resource test needs a player Processor and Hub")
		return
	simulation.resource_nodes["north_field"]["remaining"] = 10.0
	simulation.resource_nodes["north_field"]["initial_remaining"] = 10.0
	simulation.resource_nodes["north_field"]["depleted"] = false
	simulation.resource_nodes["north_field"]["depletion_announced"] = false
	var collector_id: String = simulation._add_collector("player", "north_field", refinery_id, hub_id, simulation.resource_nodes["north_field"]["position"])
	_run_ticks(simulation, 35)
	var resource: Dictionary = simulation.resource_nodes["north_field"]
	if float(resource["remaining"]) > 0.01 or not bool(resource["depleted"]):
		failures.append("resource fields should visibly exhaust at zero reserve")
	if not _has_event(simulation, "ResourceDepleted", "source_id", "north_field"):
		failures.append("resource depletion should emit a single readable event")
	_run_ticks(simulation, 80)
	if str(simulation.units[collector_id].get("collector_state", "")) != "depleted":
		failures.append("a Collector should stop and report SOURCE DEPLETED after its final delivery")
	simulation.issue_command("assign_collector", "player", {"collector_id": collector_id, "source_id": "north_field", "destination_id": refinery_id})
	_run_ticks(simulation, 1)
	if not _has_event_with_text(simulation, "OrderRejected", "depleted"):
		failures.append("assigning a depleted field should explain that another field is required")


func _test_adaptive_ai(failures: Array[String]) -> void:
	var passive_sim = SimulationScript.new()
	root.add_child(passive_sim)
	passive_sim.start_match("relay_crossroads")
	passive_sim._emit_event("ResourceDelivered", {"team": "player", "message": "Collector delivered."})
	passive_sim._ai_controller._update_tactical_posture()
	if str(passive_sim.get_ai_summary().get("posture", "")) != "attacking":
		failures.append("a passive harvesting player should trigger the AI attacking posture")

	var battered_sim = SimulationScript.new()
	root.add_child(battered_sim)
	battered_sim.start_match("relay_crossroads")
	var enemy_hq_id := _find_entity(battered_sim.buildings, "command_hub", "enemy")
	battered_sim.buildings[enemy_hq_id]["health"] = 1.0
	battered_sim._ai_controller._update_tactical_posture()
	if str(battered_sim.get_ai_summary().get("posture", "")) != "defensive":
		failures.append("a battered AI should switch to defensive posture")

	var level_one_sim = SimulationScript.new()
	root.add_child(level_one_sim)
	level_one_sim.start_match("relay_divide")
	level_one_sim._emit_event("ResourceDelivered", {"team": "player", "message": "Collector delivered."})
	level_one_sim._ai_controller._update_tactical_posture()
	if str(level_one_sim.get_ai_summary().get("posture", "")) != "opening":
		failures.append("Level 1 should keep its opening posture during the authored grace period")
	level_one_sim.current_tick = int(level_one_sim.level_definition.get("ai", {}).get("proactive_attack_delay_ticks", 0))
	level_one_sim._emit_event("ResourceDelivered", {"team": "player", "message": "Collector delivered."})
	level_one_sim._ai_controller._update_tactical_posture()
	if str(level_one_sim.get_ai_summary().get("posture", "")) != "attacking":
		failures.append("Level 1 should eventually adapt into an attacking posture after its grace period")
	var level_two_sim = SimulationScript.new()
	root.add_child(level_two_sim)
	level_two_sim.start_match("relay_crossroads")
	if str(level_one_sim.get_ai_summary().get("map_tactic", "")) == str(level_two_sim.get_ai_summary().get("map_tactic", "")):
		failures.append("authored maps should select different automatic opening tactics")


func _test_player_hud_and_placement(failures: Array[String]) -> void:
	var main = MainScript.new()
	root.add_child(main)
	await process_frame
	if main.start_menu_panel == null or not main.start_menu_panel.visible:
		failures.append("campaign deployment should open as a start menu")
	if main.find_child("ControlsHelp", true, false) != null or main.find_child("OpponentPolicyPanel", true, false) != null:
		failures.append("battlefield HUD should not contain the removed help or policy panels")
	main.campaign_progress.mark_complete("relay_divide")
	main._load_campaign_level("relay_crossroads")
	var resource_position: Vector3 = main.simulation.resource_nodes["north_field"]["position"]
	var resource_screen: Vector2 = main.camera.unproject_position(resource_position + Vector3.UP * 0.6)
	main.pointer_position = resource_screen
	main.drag_start = resource_screen
	main.drag_current = resource_screen
	main._finish_left_click()
	main._update_hud()
	if main.selected_resource_id != "north_field" or main.selected_label.text.find("ENERGY") < 0 or main.selected_label.text.find("/") < 0:
		failures.append("clicking an Energy Field should show its current finite reserve")

	var hub_id := _find_entity(main.simulation.buildings, "command_hub", "player")
	main.simulation.player_credits = 5000.0
	main.build_mode = "assembly_bay"
	main.build_source_id = hub_id
	main._create_build_ghost()
	var blocked_position: Vector3 = main.simulation.buildings[hub_id]["position"]
	var blocked_screen: Vector2 = main.camera.unproject_position(blocked_position + Vector3.UP * 0.6)
	main.pointer_position = blocked_screen
	main._update_build_ghost()
	if main.build_ghost_valid or main.build_ghost_mesh.material_override.albedo_color.r < 0.7:
		failures.append("overlapping building placement should turn the preview red")
	main.drag_start = blocked_screen
	main.drag_current = blocked_screen
	main._finish_left_click()
	if main.build_mode.is_empty() or main.status_label.text.find("CANNOT PLACE") < 0:
		failures.append("invalid placement should keep the build preview active and explain the rejection")


func _test_building_survivability(failures: Array[String]) -> void:
	var simulation = SimulationScript.new()
	root.add_child(simulation)
	simulation.start_match("relay_crossroads")
	var hub_id := _find_entity(simulation.buildings, "command_hub", "player")
	if hub_id.is_empty():
		failures.append("survivability test needs a player Command Hub")
		return
	var max_health: float = simulation.buildings[hub_id]["max_health"]
	if max_health < 2000.0:
		failures.append("Command Hub should have enough health for a meaningful response window")
	var raider_ids: Array[String] = []
	for entity_id in simulation.units:
		if simulation.units[entity_id]["team"] == "enemy" and simulation.units[entity_id]["kind"] == "raider":
			raider_ids.append(entity_id)
	for raider_id in raider_ids:
		simulation.units[raider_id]["position"] = simulation.buildings[hub_id]["position"] + Vector3(2.0, 0.0, 0.0)
		simulation.units[raider_id]["target_position"] = simulation.units[raider_id]["position"]
		simulation.issue_command("attack", "enemy", {"entity_ids": [raider_id], "target_id": hub_id})
	_run_ticks(simulation, 100)
	if not simulation.buildings.has(hub_id) or float(simulation.buildings[hub_id]["health"]) <= max_health * 0.7:
		failures.append("two Raiders should not erase a Command Hub before the player can respond")


func _run_ticks(simulation, count: int) -> void:
	for _index in range(count):
		simulation.step_fixed()


func _find_entity(entities: Dictionary, kind: String, team: String) -> String:
	for entity_id in entities:
		if entities[entity_id]["kind"] == kind and entities[entity_id]["team"] == team:
			return entity_id
	return ""


func _has_event(simulation, event_type: String, key: String, value: String) -> bool:
	for event in simulation.event_history:
		if str(event.get("event_type", "")) == event_type and str(event.get(key, "")) == value:
			return true
	return false


func _has_event_with_text(simulation, event_type: String, text: String) -> bool:
	for event in simulation.event_history:
		if str(event.get("event_type", "")) == event_type and str(event.get("message", "")).to_lower().find(text.to_lower()) >= 0:
			return true
	return false
