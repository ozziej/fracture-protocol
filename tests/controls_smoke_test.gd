extends SceneTree

const MainScript = preload("res://src/main.gd")


func _initialize() -> void:
	await process_frame
	var failures: Array[String] = []
	var main = MainScript.new()
	root.add_child(main)

	if not main.objective_label.text.begins_with("OBJECTIVE"):
		failures.append("HUD should show an actionable first-minute objective")
	if main.collector_button.visible:
		failures.append("Level 1 should hide Collector production until a Resource Processor is selected")
	if main.start_menu_panel == null or not main.start_menu_panel.visible:
		failures.append("campaign deployment should be a start menu before the match begins")
	var visible_help: Node = main.find_child("ControlsHelp", true, false)
	if visible_help != null and visible_help.visible:
		failures.append("on-screen controls text should be removed from the battlefield HUD")
	if main.find_child("OpponentPolicyPanel", true, false) != null:
		failures.append("opponent policy should not obscure the battlefield HUD")
	var minimap_rect: Rect2 = main.minimap.get_global_rect()
	var viewport_rect: Rect2 = main.get_viewport().get_visible_rect()
	if minimap_rect.position.x < 0.0 or minimap_rect.position.y < 0.0 or minimap_rect.end.x > viewport_rect.end.x or minimap_rect.end.y > viewport_rect.end.y:
		failures.append("minimap should be visible inside the tactical HUD")
	var bottom_panel_rect: Rect2 = main.bottom_panel.get_global_rect()
	if bottom_panel_rect.position.x < viewport_rect.position.x or bottom_panel_rect.end.x > viewport_rect.end.x or bottom_panel_rect.end.y > viewport_rect.end.y:
		failures.append("context action panel should stay inside the viewport at the current window size")
	if main.action_card_icons.size() != 7 or main.action_card_titles.size() != 7 or main.action_card_prices.size() != 7:
		failures.append("context actions should expose seven compact icon cards, including overflow repair")
	for action_button in [main.build_button, main.queue_button, main.heavy_queue_button, main.research_button, main.repair_button, main.collector_button]:
		if action_button.text != "":
			failures.append("context action cards should use icon and price content instead of a long button label")
		var hover_style := action_button.get_theme_stylebox("hover") as StyleBoxFlat
		if hover_style == null or hover_style.corner_radius_top_left < 8:
			failures.append("context action cards should retain rounded hover-aware styling")
	if not main._pointer_over_ui():
		failures.append("deployment dialog should block battlefield pointer input")
	main.pointer_inside_viewport = false
	main.pointer_position = Vector2(0.0, 0.0)
	if not main._pointer_over_ui():
		failures.append("pointer outside the window should block camera edge scrolling")
	main.pointer_inside_viewport = true
	if main.minimap.map_bounds != Rect2(-115.0, -75.0, 230.0, 150.0):
		failures.append("minimap should use the authored level bounds")
	if main.simulation.control_points["west_crossing"]["owner"] != "neutral":
		failures.append("West Crossing should begin neutral, outside the opening force")
	var central_reveal_id: String = main.simulation._add_unit("player", "ranger", main.simulation.control_points["central_relay"]["position"])
	main.simulation._visibility_system.invalidate()
	main._sync_views()
	var central_point_label: Label3D = main.control_views["central_relay"].get_node("PointLabel") as Label3D
	if central_point_label == null or central_point_label.text.find("NETWORK HUB") < 0:
		failures.append("control-point presentation should identify the Central Relay network-hub role")

	main.campaign_progress.mark_complete("relay_divide")
	main._load_campaign_level("relay_crossroads")
	if main.start_menu_panel.visible:
		failures.append("starting a mission should close the campaign start menu")
	var level_two_bounds := Rect2(-140.0, -92.0, 280.0, 184.0)
	if main.minimap.map_bounds != level_two_bounds:
		failures.append("switching to Level 2 should rebuild the minimap bounds")
	if main.minimap.mouse_filter != Control.MOUSE_FILTER_STOP:
		failures.append("minimap should capture tactical clicks instead of ignoring input")
	main.dragging = true
	main.drag_start = Vector2(280.0, 280.0)
	main.drag_current = Vector2(440.0, 380.0)
	var hud_release := _mouse_event(Vector2(640.0, 680.0), MOUSE_BUTTON_LEFT, false)
	main._input(hud_release)
	if main.dragging or main.selection_marquee.visible:
		failures.append("drag selection should finish when the release lands over the HUD")
	var camera_before_minimap_click: Vector3 = main.camera_target
	var minimap_click := InputEventMouseButton.new()
	minimap_click.button_index = MOUSE_BUTTON_LEFT
	minimap_click.pressed = true
	minimap_click.position = Vector2(210.0, 100.0)
	main.minimap._gui_input(minimap_click)
	if main.camera_target.distance_to(camera_before_minimap_click) < 8.0:
		failures.append("clicking the minimap should pan the camera to the tactical location")
	var level_two_refinery_id := _find_entity(main.simulation.buildings, "refinery", "player")
	var level_two_hub_id := _find_entity(main.simulation.buildings, "command_hub", "player")
	var level_two_assembly_id := _find_entity(main.simulation.buildings, "assembly_bay", "player")
	var level_two_collector_id: String = main.simulation._add_collector("player", "north_field", level_two_refinery_id, level_two_hub_id, main.simulation.buildings[level_two_refinery_id]["position"])
	if level_two_assembly_id.is_empty():
		failures.append("Level 2 should include a player Assembly Bay for the compact fabrication card")
	else:
		main.selected_ids = [level_two_assembly_id]
		main._update_hud()
		if main.context_actions.has("build:sensor_mast") or main.context_actions.has("build:bastion_turret"):
			failures.append("Assembly Bay should expose vehicle production and upgrades, not defensive construction cards")
		if main.action_card_titles[3].text != "FABRICATION" or str(main.action_card_prices[3].text).find("C") < 0:
			failures.append("Assembly Bay fabrication should be presented as a named icon card with its price below")
		if main.selected_label.text.find("ASSEMBLY BAY") < 0 or main.selected_label.text.find("HP") < 0:
			failures.append("selected building card should show the building name and HP beside its icon")
		if main.selected_icon.get_asset_path() != "res://kenney_space-kit/Side/hangar_largeA.png":
			failures.append("Assembly Bay HUD icon should use its matching Kenney side-view asset")
		var queue_building: Dictionary = main.simulation.buildings[level_two_assembly_id]
		queue_building["queue"] = [{"unit_type": "bulwark", "remaining": 7.0, "total": 12.0, "cost": 210.0}]
		main._update_production_queue_ui()
		var queue_scroll: Node = main.find_child("ProductionQueueScroll", true, false)
		if queue_scroll == null or main.queue_buttons.size() != 5 or not main.queue_buttons[0].visible:
			failures.append("production queue should expose scrollable icon cards")
		else:
			if main.queue_buttons[0].text != "":
				failures.append("production queue cards should use icon and detail labels instead of button text")
			var queue_hover_style := main.queue_buttons[0].get_theme_stylebox("hover") as StyleBoxFlat
			if queue_hover_style == null or queue_hover_style.corner_radius_top_left < 8:
				failures.append("production queue cards should retain rounded hover-aware styling")
			if main.queue_card_icons[0].get_asset_path() != "res://kenney_space-kit/Side/craft_cargoB.png":
				failures.append("Bulwark queue card should use its matching Kenney side-view asset")
			if main.queue_card_titles[0].text.find("BULWARK") < 0 or main.queue_card_refunds[0].text.find("210") < 0:
				failures.append("production queue card should show unit, progress, and refund details")
			queue_building["queue"] = [{"unit_type": "command_carrier", "remaining": 17.0, "total": 24.0, "cost": 260.0}]
			main._update_production_queue_ui()
			if main.queue_card_titles[0].get_theme_font_size("font_size") >= 10:
				failures.append("long production queue titles should use a smaller fitted font")
			queue_building["queue"] = [{"unit_type": "bulwark", "remaining": 7.0, "total": 12.0, "cost": 210.0}]
			main._update_production_queue_ui()
		var top_status_panel: Node = main.find_child("TopStatusPanel", true, false)
		var top_stats_scroll: Node = main.find_child("TopStatsScroll", true, false)
		if top_status_panel == null or top_stats_scroll == null:
			failures.append("top HUD should use a structured status bar with a scrollable stat row")
	main.simulation.event_history.append({"event_type": "ResourceDelivered", "team": "player"})
	main._update_objective()
	main._sync_views()
	if not main.building_views[level_two_hub_id].repair_zone.visible or not main.building_views[level_two_assembly_id].repair_zone.visible:
		failures.append("Command Hub and Assembly Bay should show visible green repair influence circles")
	var west_objective_beam := main.control_views["west_crossing"].get_node_or_null("ObjectiveBeam") as MeshInstance3D
	if main.objective_target_point_id != "west_crossing" or west_objective_beam == null or not west_objective_beam.visible:
		failures.append("level-data staging objective should mark West Crossing in the world")
	if not main.control_views.has("central_relay") or main.control_views["central_relay"].get_node_or_null("RelayCore") == null:
		failures.append("central relay should expose the representative signal core visual")
	var tech_centre_id: String = main.simulation._add_building("player", "tech_centre", Vector3(-96.0, 0.0, 38.0))
	main._sync_views()
	main.selected_ids = [tech_centre_id]
	main._update_context_cards()
	var research_options := ["advanced_targeting", "hardened_chassis", "field_optics", "breach_package"]
	for research_id in research_options:
		if not main.context_actions.has("research:%s" % research_id):
			failures.append("Tech Centre should keep unfinished research card %s visible before research starts" % research_id)
	main.simulation.player_credits = 2000.0
	main.simulation.issue_command("research", "player", {"building_id": tech_centre_id, "technology_id": "advanced_targeting"})
	main.simulation.step_fixed()
	main._update_context_cards()
	for research_id in research_options:
		if not main.context_actions.has("research:%s" % research_id):
			failures.append("Tech Centre should keep unfinished research card %s visible while another research is active" % research_id)
	var target_enemy_id := _find_entity(main.simulation.units, "raider", "enemy")
	var target_player_id := _find_entity(main.simulation.units, "ranger", "player")
	if target_enemy_id.is_empty() or target_player_id.is_empty():
		failures.append("target inspection needs an enemy Raider and player Ranger")
	else:
		main.simulation.units[target_enemy_id]["position"] = main.simulation.units[target_player_id]["position"] + Vector3(3.0, 0.0, 0.0)
		main.simulation.units[target_enemy_id]["target_position"] = main.simulation.units[target_enemy_id]["position"]
		main.simulation._visibility_system.invalidate()
		main._sync_views()
		main._update_camera()
		var target_screen: Vector2 = main.camera.unproject_position(main.simulation.units[target_enemy_id]["position"] + Vector3.UP * 0.7)
		main.pointer_position = target_screen
		main.drag_start = target_screen
		main.drag_current = target_screen
		main._finish_left_click()
		if main.inspected_target_id != target_enemy_id or main.selected_ids.size() != 0:
			failures.append("left-clicking an enemy should inspect it without selecting it as a friendly unit")
		var target_detail := main._target_detail(main.simulation.units[target_enemy_id])
		if target_detail.find("HP") < 0 or target_detail.find("DMG") < 0 or target_detail.find("RANGE") < 0:
			failures.append("enemy inspection should show health, damage, and attack range")
		main.selected_ids = [target_player_id]
		main._issue_context_order(target_screen)
		if not main.unit_views.has(target_enemy_id) or not main.unit_views[target_enemy_id].target_flash_disc.visible:
			failures.append("right-clicking an enemy attack target should show a brief highlight flash")
		main._on_simulation_event("ProjectileLaunched", {
			"attacker_id": target_enemy_id,
			"team": "enemy",
			"launch_position": main.simulation.units[target_enemy_id]["position"],
			"impact_position": main.simulation.units[target_player_id]["position"],
			"travel_time": 0.4,
		})
		var missile_visible := false
		for child in main.get_children():
			if str(child.name).begins_with("MissileProjectile_"):
				missile_visible = true
				break
		if not missile_visible:
			failures.append("launcher fire should create a visible moving projectile")

	main._on_simulation_event("UnitDamaged", {
		"attacker_position": main.simulation.buildings[level_two_hub_id]["position"],
		"target_position": main.simulation.buildings[level_two_hub_id]["position"] + Vector3(2.0, 0.0, 0.0),
		"attacker_team": "player",
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
		var armed_group_ids: Array = []
		for entity_id in player_ids:
			if main.simulation.units.has(entity_id) and main.simulation.units[entity_id]["team"] == "player" and str(main.simulation.units[entity_id].get("kind", "")) != "collector" and float(main.simulation.units[entity_id].get("attack_range", 0.0)) > 0.0:
				armed_group_ids.append(entity_id)
		if armed_group_ids.size() < 2:
			failures.append("group command smoke test needs at least two armed units")
		else:
			main.selected_ids = armed_group_ids.duplicate()
			main._update_context_cards()
			var group_actions: Array = ["unit_guard", "unit_attack_move", "unit_stop"]
			var group_icons: Array = ["guard", "attack_move", "stop"]
			var group_shortcuts: Array = ["[G]", "[T]", "[X]"]
			var action_buttons: Array = [main.build_button, main.queue_button, main.heavy_queue_button, main.research_button, main.repair_button, main.collector_button, main.repair_overflow_button]
			for group_index in range(group_actions.size()):
				var group_slot: int = main.context_actions.find(group_actions[group_index])
				if group_slot < 0:
					failures.append("group selection should expose %s" % group_actions[group_index])
					continue
				if not action_buttons[group_slot].visible or action_buttons[group_slot].disabled:
					failures.append("group command card %s should be enabled and visible" % group_actions[group_index])
				if main.action_card_icons[group_slot].icon_key != group_icons[group_index]:
					failures.append("group command %s should use its purpose-built icon" % group_actions[group_index])
				if main.action_card_prices[group_slot].text != group_shortcuts[group_index]:
					failures.append("group command %s should show its keyboard shortcut" % group_actions[group_index])
			var guard_slot: int = main.context_actions.find("unit_guard")
			if guard_slot >= 0:
				main._run_context_action(guard_slot)
				main.simulation.step_fixed()
				for entity_id in armed_group_ids:
					if str(main.simulation.units[entity_id].get("order", "")) != "guard":
						failures.append("clicking the Guard card should issue Guard to the selected group")
						break
			var attack_move_slot: int = main.context_actions.find("unit_attack_move")
			if attack_move_slot >= 0:
				main._run_context_action(attack_move_slot)
				if not main.attack_move_mode:
					failures.append("clicking the Attack-Move card should enter Attack-Move mode")
			var stop_slot: int = main.context_actions.find("unit_stop")
			if stop_slot >= 0:
				main._run_context_action(stop_slot)
				main.simulation.step_fixed()
				for entity_id in armed_group_ids:
					if str(main.simulation.units[entity_id].get("order", "")) != "idle":
						failures.append("clicking the Stop card should stop the selected group")
						break
			main.selected_ids = player_ids.duplicate()
			main._update_context_cards()
		var selected_before_focus: Array = main.selected_ids.duplicate()
		main.camera_target = Vector3(30.0, 0.0, -15.0)
		main._unhandled_input(_key_event(KEY_H))
		if main.selected_ids != selected_before_focus:
			failures.append("camera focus should not change the selected group")
		var expected_center := Vector3.ZERO
		for entity_id in player_ids:
			expected_center += main.simulation.units[entity_id]["position"]
		expected_center /= float(player_ids.size())
		if main.camera_target.distance_to(expected_center) > 8.0:
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
			if not main.attack_move_mode:
				failures.append("T should enter Attack-Move mode for the selected force")
			main._unhandled_input(_key_event(KEY_ESCAPE))
			if main.attack_move_mode:
				failures.append("Escape should cancel Attack-Move mode")
			main._unhandled_input(_key_event(KEY_G))
			main.simulation.step_fixed()
			var armed_player_ids: Array = main._selected_combat_unit_ids()
			for entity_id in armed_player_ids:
				if str(main.simulation.units[entity_id].get("order", "")) != "guard":
					failures.append("G should issue Guard to every selected armed unit")
					break
			main._unhandled_input(_key_event(KEY_X))
			main.simulation.step_fixed()
			for entity_id in armed_player_ids:
				if str(main.simulation.units[entity_id].get("order", "")) != "idle":
					failures.append("X should stop every selected armed unit")
					break

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
			if bool(main.simulation.units[repair_unit_id].get("repair_active", false)) or main.simulation.units[repair_unit_id]["health"] != 25.0:
				failures.append("repair should not be available as a unit keyboard action")
			main.selected_ids = [hub_id]
			main._update_context_cards()
			var repair_action_slot: int = main.context_actions.find("repair")
			if repair_action_slot < 0:
				failures.append("the selected repair building should expose a repair action card")
			else:
				main._run_context_action(repair_action_slot)
			main.simulation.step_fixed()
			if main.simulation.units[repair_unit_id]["health"] <= 25.0:
				failures.append("the selected building should repair a nearby damaged unit")

	var collector_id: String = level_two_collector_id
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


func _mouse_event(position: Vector2, button: int, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.position = position
	event.button_index = button
	event.pressed = pressed
	return event


func _find_entity(entities: Dictionary, kind: String, team: String) -> String:
	for entity_id in entities:
		if entities[entity_id]["kind"] == kind and entities[entity_id]["team"] == team:
			return entity_id
	return ""
