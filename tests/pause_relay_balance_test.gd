extends SceneTree

const MainScript = preload("res://src/main.gd")
const SimulationScript = preload("res://src/rts_simulation.gd")


func _initialize() -> void:
	await process_frame
	var failures: Array[String] = []
	var balance_sim = SimulationScript.new()
	root.add_child(balance_sim)
	balance_sim.start_match("relay_crossroads")
	var ranger_definition = balance_sim.unit_definitions["ranger"]
	var bulwark_definition = balance_sim.unit_definitions["bulwark"]
	var warden_definition = balance_sim.unit_definitions["warden"]
	if float(ranger_definition.max_health) >= float(bulwark_definition.max_health) or float(bulwark_definition.max_health) >= float(warden_definition.max_health):
		failures.append("unit durability should progress from Ranger to Bulwark to Warden")
	if float(bulwark_definition.armour) >= float(warden_definition.armour):
		failures.append("Warden should have the strongest baseline armour")

	var ranger_attacker := balance_sim._add_unit("player", "ranger", Vector3.ZERO)
	var warden_attacker := balance_sim._add_unit("player", "warden", Vector3.ZERO)
	var bulwark_attacker := balance_sim._add_unit("player", "bulwark", Vector3.ZERO)
	var ranger_target := balance_sim._add_unit("enemy", "ranger", Vector3(4.0, 0.0, 0.0))
	var bulwark_target_for_ranger := balance_sim._add_unit("enemy", "bulwark", Vector3(4.0, 0.0, 0.0))
	var bulwark_target_for_warden := balance_sim._add_unit("enemy", "bulwark", Vector3(4.0, 0.0, 0.0))
	var warden_target_for_ranger := balance_sim._add_unit("enemy", "warden", Vector3(4.0, 0.0, 0.0))
	var warden_target_for_warden := balance_sim._add_unit("enemy", "warden", Vector3(4.0, 0.0, 0.0))
	var warden_target_for_bulwark := balance_sim._add_unit("enemy", "warden", Vector3(4.0, 0.0, 0.0))
	var ranger_before: float = balance_sim.units[ranger_target]["health"]
	var bulwark_before_ranger: float = balance_sim.units[bulwark_target_for_ranger]["health"]
	var bulwark_before_warden: float = balance_sim.units[bulwark_target_for_warden]["health"]
	var warden_before_ranger: float = balance_sim.units[warden_target_for_ranger]["health"]
	var warden_before_warden: float = balance_sim.units[warden_target_for_warden]["health"]
	var warden_before_bulwark: float = balance_sim.units[warden_target_for_bulwark]["health"]
	balance_sim._apply_damage(ranger_target, 12.0, ranger_attacker)
	balance_sim._apply_damage(bulwark_target_for_ranger, 12.0, ranger_attacker)
	balance_sim._apply_damage(bulwark_target_for_warden, 36.0, warden_attacker)
	balance_sim._apply_damage(warden_target_for_ranger, 12.0, ranger_attacker)
	balance_sim._apply_damage(warden_target_for_warden, 36.0, warden_attacker)
	balance_sim._apply_damage(warden_target_for_bulwark, 58.0, bulwark_attacker)
	var ranger_damage: float = ranger_before - float(balance_sim.units[ranger_target]["health"])
	var ranger_to_bulwark_damage: float = bulwark_before_ranger - float(balance_sim.units[bulwark_target_for_ranger]["health"])
	var warden_to_bulwark_damage: float = bulwark_before_warden - float(balance_sim.units[bulwark_target_for_warden]["health"])
	var ranger_to_warden_damage: float = warden_before_ranger - float(balance_sim.units[warden_target_for_ranger]["health"])
	var warden_to_warden_damage: float = warden_before_warden - float(balance_sim.units[warden_target_for_warden]["health"])
	var bulwark_to_warden_damage: float = warden_before_bulwark - float(balance_sim.units[warden_target_for_bulwark]["health"])
	if ranger_damage <= 0.0 or ranger_to_bulwark_damage <= 0.0:
		failures.append("Ranger should be able to damage both normal targets and Bulwarks")
	if warden_to_bulwark_damage <= ranger_to_bulwark_damage:
		failures.append("Warden should be an efficient direct counter to Bulwark")
	if bulwark_to_warden_damage <= warden_to_warden_damage or warden_to_warden_damage <= ranger_to_warden_damage:
		failures.append("Bulwark should counter Warden while ordinary fire is strongly reduced")

	var main = MainScript.new()
	root.add_child(main)
	await process_frame
	if main.find_child("CombatAlertPanel", true, false) != null:
		failures.append("the removed duplicate combat alert panel must not exist")
	main._load_skirmish_match("relay_crossroads", {
		"mode": "skirmish",
		"scenario_id": "network_hold",
		"ai_difficulty": "standard",
		"ai_intent": "secure_then_assault",
	})
	main._hide_objective_briefing()
	var hub_id := _find_building(main.simulation, "player", "command_hub")
	if hub_id.is_empty():
		failures.append("pause and relay UI fixture needs the player Command Hub")
	else:
		main.selected_ids = [hub_id]
		main._update_hud()
		var relay_slot: int = main.context_actions.find("build:relay")
		if relay_slot < 0 or not main.research_button.visible:
			failures.append("Command Hub should expose the Forward Relay construction card")
		else:
			main._run_context_action(relay_slot)
			if main.build_mode != "relay":
				failures.append("the Forward Relay card should enter relay placement mode")
		main._cancel_build_mode()
		main.build_mode = "relay"
		main._create_build_ghost()
		main._update_build_range_guides()
		if main.build_range_guides.is_empty():
			failures.append("relay placement should show link-radius guides around connected sources")
		else:
			var guide: Node3D = main.build_range_guides.values()[0]
			var link_ring := guide.get_node_or_null("LinkRangeRing") as MeshInstance3D
			var ring_mesh := link_ring.mesh as TorusMesh if link_ring else null
			if ring_mesh == null or abs(ring_mesh.outer_radius - main.simulation.SUPPLY_LINK_RADIUS) > 0.01:
				failures.append("relay placement guide should match the simulation supply-link radius")
		main._cancel_build_mode()
		main.selected_ids = [hub_id]
		main._sync_views()
		var hub_view = main.building_views.get(hub_id)
		if hub_view == null or not hub_view.network_link_zone.visible or not hub_view.network_link_zone_ring.visible:
			failures.append("selecting a Command Hub should show its network link-radius circle")
		var top_stats_row: Node = main.find_child("TopStatsRow", true, false)
		if top_stats_row == null or top_stats_row.get_child_count() < 4 or top_stats_row.get_child(3).name != "SupplyChip":
			failures.append("the Supply chip should sit at the end of the top stats row")

	var tick_before_pause: int = main.simulation.current_tick
	main._unhandled_input(_key_event(KEY_ESCAPE))
	if not main.pause_menu_visible or not main.pause_menu_overlay.visible:
		failures.append("Escape should open the pause menu")
	main._process(1.0)
	if main.simulation.current_tick != tick_before_pause:
		failures.append("the simulation should not advance while the pause menu is open")
	main._on_game_log_toggled(false)
	main._on_play_hints_toggled(false)
	if main.game_log_enabled or main.event_log_label.visible or main.play_hints_enabled or main.status_label.visible:
		failures.append("pause settings should independently hide the event log and gameplay hints")
	main._unhandled_input(_key_event(KEY_ESCAPE))
	if main.pause_menu_visible or main.pause_menu_overlay.visible:
		failures.append("Escape should resume from the pause menu")
	main._process(1.0)
	if main.simulation.current_tick <= tick_before_pause:
		failures.append("the simulation should resume after closing the pause menu")

	if failures.is_empty():
		print("PAUSE_RELAY_BALANCE_PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("PAUSE_RELAY_BALANCE_FAIL")
		quit(1)


func _key_event(keycode: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	return event


func _find_building(simulation, team: String, kind: String) -> String:
	for building_id in simulation.buildings:
		var building: Dictionary = simulation.buildings[building_id]
		if str(building.get("team", "")) == team and str(building.get("kind", "")) == kind:
			return str(building_id)
	return ""
