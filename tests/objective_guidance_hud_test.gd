extends SceneTree

const MainScript = preload("res://src/main.gd")
const MinimapScript = preload("res://src/minimap.gd")


func _initialize() -> void:
	await process_frame
	var failures: Array[String] = []
	var main = MainScript.new()
	root.add_child(main)
	await process_frame

	if main.find_child("TechnologyChip", true, false) != null:
		failures.append("top HUD should remove the Tech status section")
	if main.territory_label == null or main.territory_label.clip_text:
		failures.append("Territory status should not clip its text")
	main._update_hud()
	if main.territory_label.text.find("C/S") < 0:
		failures.append("Territory status should show the complete income suffix")
	var territory_chip: Control = main.find_child("TerritoryChip", true, false)
	if territory_chip == null or territory_chip.custom_minimum_size.x < 210.0:
		failures.append("Territory status should reserve enough width for its complete label")

	main._load_campaign_level("relay_divide")
	if not main.objective_briefing_visible or not main.objective_briefing_overlay.visible:
		failures.append("starting a campaign level should show the objective briefing modal")
	if main.objective_briefing_body_label.text.find("PRIMARY OBJECTIVE") < 0 or main.objective_briefing_body_label.text.find("FIRST ACTION") < 0:
		failures.append("campaign briefing should explain the primary objective and first action")
	var campaign_tick: int = int(main.simulation.current_tick)
	await process_frame
	if main.simulation.current_tick != campaign_tick:
		failures.append("the objective briefing modal should pause the live simulation")
	main._hide_objective_briefing()

	main._load_skirmish_match("relay_crossroads", {
		"mode": "skirmish",
		"scenario_id": "network_sever",
		"ai_difficulty": "standard",
		"ai_intent": "",
	})
	if not main.objective_briefing_visible:
		failures.append("starting a skirmish should show the scenario objective briefing modal")
	if main.objective_briefing_title_label.text.find("NETWORK SEVER") < 0 or main.objective_briefing_body_label.text.find("OBJECTIVE SITES") < 0 or main.objective_briefing_body_label.text.find("NETWORK SEVERED") < 0:
		failures.append("skirmish briefing should explain the sites and interruption recovery")
	main._hide_objective_briefing()
	main._sync_views()

	if main.objective_target_point_ids != ["central_relay", "network_east"]:
		failures.append("skirmish objective guidance should track every required objective site")
	if main.minimap.objective_target_point_ids != ["central_relay", "network_east"]:
		failures.append("tactical map should receive every objective site")
	if MinimapScript.OBJECTIVE_HIGHLIGHT_RADIUS < 10.0:
		failures.append("tactical map objective highlight should be substantially larger than a unit marker")

	for point_id in main.objective_target_point_ids:
		var objective_marker: Label3D = main.control_views[point_id].get_node_or_null("ObjectiveMarker") as Label3D
		if objective_marker == null or not objective_marker.visible:
			failures.append("main view should show a visible objective marker for %s" % point_id)

	var player_unit_id := _find_player_unit(main)
	if player_unit_id.is_empty():
		failures.append("objective proximity guidance needs a player unit")
	else:
		var central_position: Vector3 = main.simulation.control_points["central_relay"]["position"]
		main.simulation.units[player_unit_id]["position"] = central_position + Vector3(1.0, 0.0, 0.0)
		main.simulation.units[player_unit_id]["target_position"] = main.simulation.units[player_unit_id]["position"]
		main.simulation._visibility_system.invalidate()
		main._sync_views()
		var proximity_marker: Label3D = main.control_views["central_relay"].get_node_or_null("ObjectiveProximityMarker") as Label3D
		if proximity_marker == null or not proximity_marker.visible:
			failures.append("main view should show an OBJECTIVE HERE marker when a player unit is nearby")

	if failures.is_empty():
		print("OBJECTIVE_GUIDANCE_HUD_PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("OBJECTIVE_GUIDANCE_HUD_FAIL")
		quit(1)


func _find_player_unit(main) -> String:
	for entity_id in main.simulation.units:
		var unit: Dictionary = main.simulation.units[entity_id]
		if unit["team"] == "player" and unit["kind"] != "collector":
			return str(entity_id)
	return ""
