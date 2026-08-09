extends SceneTree

const MainScript = preload("res://src/main.gd")


func _initialize() -> void:
	await process_frame
	var failures: Array[String] = []
	var main = MainScript.new()
	root.add_child(main)

	if not main.objective_label.text.begins_with("OBJECTIVE"):
		failures.append("HUD should show an actionable first-minute objective")
	if main.collector_button.text != "QUEUE COLLECTOR [C]":
		failures.append("HUD should expose Collector production before a Collector is selected")

	if not main.control_views.has("central_relay") or main.control_views["central_relay"].get_node_or_null("RelayCore") == null:
		failures.append("central relay should expose the representative signal core visual")

	main._on_simulation_event("UnitDamaged", {
		"attacker_position": Vector3(-4.0, 0.0, 0.0),
		"target_position": Vector3(0.0, 0.0, 0.0),
		"damage": 17.0,
		"tick": 1,
	})
	var combat_effect_visible := false
	for child in main.get_children():
		if str(child.name).begins_with("CombatEffect_"):
			combat_effect_visible = true
			break
	if not combat_effect_visible:
		failures.append("damage events should create combat feedback")

	var player_ids: Array = main.simulation.get_player_unit_ids()
	if player_ids.is_empty():
		failures.append("controls smoke test needs player units")
	else:
		main.selected_ids = player_ids.duplicate()
		main._unhandled_input(_key_event(KEY_1, true))
		if not main.control_groups.has("1"):
			failures.append("Ctrl+1 should assign a control group")
		main.selected_ids.clear()
		main._unhandled_input(_key_event(KEY_1))
		if main.selected_ids.size() != player_ids.size():
			failures.append("1 should recall the assigned control group")
		var selected_before_focus: Array = main.selected_ids.duplicate()
		main.camera_target = Vector3(30.0, 0.0, -15.0)
		main._unhandled_input(_key_event(KEY_H))
		if main.selected_ids != selected_before_focus:
			failures.append("camera focus should not change the selected group")
		if main.camera_target.distance_to(Vector3(-21.67, 0.0, 9.0)) > 8.0:
			failures.append("H should focus the camera on the selected force")

		main.simulation.issue_command("move", "player", {
			"entity_ids": main.selected_ids,
			"position": Vector3(0.0, 0.0, 17.0),
		})
		main.simulation.step_fixed()
		main._sync_views()
		var marker_visible := false
		var marker_endpoint_correct := false
		for entity_id in main.selected_ids:
			if main.unit_views.has(entity_id) and main.unit_views[entity_id].order_line.visible:
				marker_visible = true
				var expected_endpoint: Vector3 = main.simulation.units[entity_id]["target_position"] + Vector3(0.0, 0.14, 0.0)
				marker_endpoint_correct = main.unit_views[entity_id].order_target.global_position.distance_to(expected_endpoint) < 0.5
				break
		if not marker_visible:
			failures.append("selected moving units should show destination markers")
		if not marker_endpoint_correct:
			failures.append("destination markers should land on the ordered world position")

		var assembly_id := _find_entity(main.simulation.buildings, "assembly_bay", "player")
		if assembly_id.is_empty():
			failures.append("controls smoke test needs a player Assembly Bay")
		else:
			main._unhandled_input(_key_event(KEY_T))
			main.simulation.step_fixed()
			if str(main.simulation.get_research_status("player")["active_id"]) != "advanced_targeting":
				failures.append("T should start Advanced Targeting research")

		var repair_unit_id: String = player_ids[0]
		var hub_id := _find_entity(main.simulation.buildings, "command_hub", "player")
		if hub_id.is_empty():
			failures.append("controls smoke test needs a player Command Hub")
		else:
			main.simulation.units[repair_unit_id]["position"] = main.simulation.buildings[hub_id]["position"]
			main.simulation.units[repair_unit_id]["target_position"] = main.simulation.units[repair_unit_id]["position"]
			main.simulation.units[repair_unit_id]["health"] = 25.0
			main.selected_ids = [repair_unit_id]
			main._unhandled_input(_key_event(KEY_Y))
			main.simulation.step_fixed()
			if main.simulation.units[repair_unit_id]["health"] <= 25.0:
				failures.append("Y should repair a damaged unit near base")

	var collector_id := _find_entity(main.simulation.units, "collector", "player")
	if collector_id.is_empty():
		failures.append("controls smoke test needs a player Collector")
	else:
		main.selected_ids = [collector_id]
		main._unhandled_input(_key_event(KEY_U))
		if not main.collector_assignment_mode:
			failures.append("U should enter Collector route assignment mode")
		main._unhandled_input(_key_event(KEY_ESCAPE))
		if main.collector_assignment_mode:
			failures.append("Escape should cancel Collector route assignment mode")

	main.pointer_position = Vector2(640.0, 360.0)
	main.camera_target = Vector3.ZERO
	Input.action_press("camera_forward")
	main._process_camera_input(1.0)
	Input.action_release("camera_forward")
	if main.camera_target.z >= 0.0:
		failures.append("W should pan the camera toward negative world Z")
	main.camera_target = Vector3.ZERO
	Input.action_press("camera_back")
	main._process_camera_input(1.0)
	Input.action_release("camera_back")
	if main.camera_target.z <= 0.0:
		failures.append("S should pan the camera toward positive world Z")

	main._unhandled_input(_key_event(KEY_N))
	if main.simulation.current_tick != 0 or main.simulation.match_over or main.simulation.units.size() < 8:
		failures.append("N should restart the match without stale state")

	if failures.is_empty():
		print("CONTROLS_SMOKE_PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("CONTROLS_SMOKE_FAIL")
		quit(1)


func _key_event(keycode: int, modifier := false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	event.ctrl_pressed = modifier
	return event


func _find_entity(entities: Dictionary, kind: String, team: String) -> String:
	for entity_id in entities:
		if entities[entity_id]["kind"] == kind and entities[entity_id]["team"] == team:
			return entity_id
	return ""
