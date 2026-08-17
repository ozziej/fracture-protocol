extends SceneTree

const MainScene = preload("res://main.tscn")


func _initialize() -> void:
	await process_frame
	var failures: Array[String] = []
	var main_node = MainScene.instantiate()
	root.add_child(main_node)
	await process_frame
	if str(main_node.start_menu_briefing_label.text) != "SELECT A MISSION":
		failures.append("Campaign deployment should use a concise mission-selection prompt")
	var mission_scroll: Node = main_node.find_child("CampaignMissionScroll", true, false)
	if mission_scroll == null:
		failures.append("Campaign deployment should provide a scrollable mission list")
	if main_node.campaign_start_button == null or main_node.campaign_start_button.text != "START CAMPAIGN":
		failures.append("Campaign deployment should expose a Start Campaign button")
	if main_node.campaign_doctrine_option == null or main_node.campaign_doctrine_option.item_count != 4:
		failures.append("Campaign deployment should expose the three doctrine packages plus its selection placeholder")
	if str(main_node.campaign_mission_detail_label.text).find("UNITS AVAILABLE") < 0 or str(main_node.campaign_mission_detail_label.text).find("TIER") >= 0:
		failures.append("Campaign selection should show a concise brief and units without tier duplication")
	if str(main_node.campaign_mission_detail_label.text).find("DOCTRINE") < 0:
		failures.append("Campaign selection should show the persistent doctrine reward state")
	for level_id in ["counterstroke", "iron_front"]:
		if not main_node.campaign_mission_buttons.has(level_id):
			failures.append("Campaign deployment should expose the authored %s follow-on mission" % level_id)
	for level_id in ["silent_recovery", "long_road", "holdfast"]:
		main_node.simulation.start_match(level_id, "", {"mode": "campaign"})
		main_node._clear_match_views()
		main_node._build_world_shell()
		main_node._sync_views()
		await process_frame
		if main_node.world_shell.find_child("AuthoredRoute_*", true, false) == null:
			failures.append("%s should build at least one authored campaign route" % level_id)
		if main_node.minimap.snapshot.get("campaign", {}).get("active", false) != true:
			failures.append("%s should publish campaign state to the minimap" % level_id)
		if main_node.campaign_marker_views.is_empty():
			failures.append("%s should create visible campaign objective markers" % level_id)
		if level_id == "long_road":
			var carrier_id := _find_unit_kind(main_node.simulation.units, "command_carrier")
			var carrier_view: Node3D = main_node.unit_views.get(carrier_id)
			if carrier_view == null:
				failures.append("The Long Road should create a visible Mobile Command Unit")
			else:
				var rear_screen: Vector2 = main_node.camera.unproject_position(carrier_view.global_transform * Vector3(0.0, 0.7, 3.0))
				if main_node._entity_at_screen(rear_screen, false) != carrier_id:
					failures.append("Clicking the rendered end of the Mobile Command Unit should select the carrier")
			main_node.simulation.units[carrier_id]["position"] = Vector3(90.0, 0.0, 0.0)
			main_node.simulation.step_fixed()
			main_node.selected_ids = [carrier_id]
			main_node._sync_views()
			main_node._update_context_cards()
			if str(main_node.context_actions[0]) != "deploy" or main_node.build_button.disabled:
				failures.append("Arrival at the eastern pad should expose an enabled DEPLOY BASE action")
	var campaign: Dictionary = main_node.simulation.get_campaign_state()
	if str(campaign.get("id", "")) != "holdfast":
		failures.append("presentation smoke should finish on the requested Holdfast mission")
	if failures.is_empty():
		print("CAMPAIGN_PRESENTATION_SMOKE_PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("CAMPAIGN_PRESENTATION_SMOKE_FAIL")
	quit(1)


func _find_unit_kind(units: Dictionary, kind: String) -> String:
	for unit_id in units:
		if str(units[unit_id].get("kind", "")) == kind:
			return str(unit_id)
	return ""
