extends SceneTree

const MainScript = preload("res://src/main.gd")


func _initialize() -> void:
	await process_frame
	var failures: Array[String] = []
	var main = MainScript.new()
	root.add_child(main)

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
