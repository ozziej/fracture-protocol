extends SceneTree

const SimulationScript = preload("res://src/rts_simulation.gd")
const MainScript = preload("res://src/main.gd")
const CampaignProgressScript = preload("res://src/campaign_progress.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	var simulation = SimulationScript.new()
	root.add_child(simulation)
	simulation.start_match("relay_crossroads", "", {
		"mode": "skirmish",
		"scenario_id": "network_hold",
		"ai_difficulty": "aggressive",
		"ai_intent": "hold_network",
	})

	if simulation.get_match_mode() != "skirmish":
		failures.append("skirmish settings should select skirmish match mode")
	if simulation.get_scenario_id() != "network_hold":
		failures.append("skirmish settings should select the requested scenario")
	var ai_summary: Dictionary = simulation.get_ai_summary()
	if str(ai_summary.get("difficulty", "")) != "aggressive":
		failures.append("skirmish settings should apply the requested AI difficulty")
	if str(ai_summary.get("intent", "")) != "hold_network":
		failures.append("skirmish settings should apply the requested AI intent")
	if simulation.get_skirmish_map_catalog().size() != 2:
		failures.append("skirmish catalog should expose both authored maps")
	if simulation.get_skirmish_scenarios_for_map("relay_crossroads").size() != 2:
		failures.append("both authored network scenarios should be available on Relay Crossroads")
	var initial_scenario: Dictionary = simulation.get_scenario_state("player")
	if not bool(initial_scenario.get("active", false)) or int(initial_scenario.get("hold_ticks", 0)) != 900:
		failures.append("network hold should expose its active 90-second objective")

	_prepare_network_hold(simulation, "player", ["central_relay", "network_east"])
	_step_without_ai(simulation, 5)
	var holding_scenario: Dictionary = simulation.get_scenario_state("player")
	if int(holding_scenario.get("progress_ticks", 0)) != 5 or not bool(holding_scenario.get("holding", false)):
		failures.append("network hold should accumulate only while both required sites are active")

	simulation.control_points["network_east"]["owner"] = "neutral"
	simulation._update_forward_staging_states()
	simulation._ai_timer = 0.0
	simulation.step_fixed()
	var interrupted_scenario: Dictionary = simulation.get_scenario_state("player")
	if int(interrupted_scenario.get("progress_ticks", 0)) != 0 or bool(interrupted_scenario.get("holding", true)):
		failures.append("network hold should reset progress when a required site is lost")
	if not _has_event(simulation, "ScenarioProgressChanged", "holding", false):
		failures.append("network hold interruption should emit a player-facing progress event")

	simulation.restart_match()
	if simulation.get_match_mode() != "skirmish" or simulation.get_scenario_id() != "network_hold" or simulation.current_tick != 0:
		failures.append("skirmish rematch should preserve the selected deployment settings")

	var win_simulation = SimulationScript.new()
	root.add_child(win_simulation)
	win_simulation.start_match("relay_divide", "", {"mode": "skirmish", "scenario_id": "network_hold"})
	_prepare_network_hold(win_simulation, "player", ["central_relay", "network_east"])
	_step_without_ai(win_simulation, 900)
	if not win_simulation.match_over or win_simulation.match_winner != "player":
		failures.append("completing network hold should win a skirmish match")
	if not _has_event(win_simulation, "MatchWon", "result_type", "scenario"):
		failures.append("scenario completion should emit a scenario MatchWon result")

	var enemy_simulation = SimulationScript.new()
	root.add_child(enemy_simulation)
	enemy_simulation.start_match("relay_divide", "", {"mode": "skirmish", "scenario_id": "network_hold"})
	_prepare_network_hold(enemy_simulation, "enemy", ["central_relay", "network_west"])
	_step_without_ai(enemy_simulation, 900)
	if not enemy_simulation.match_over or enemy_simulation.match_winner != "enemy":
		failures.append("enemy network hold completion should defeat the player")

	await process_frame
	var main = MainScript.new()
	root.add_child(main)
	await process_frame
	main.campaign_progress = CampaignProgressScript.new("/private/tmp/fracture-protocol-skirmish-progress.json")
	var campaign_before: Dictionary = main.campaign_progress.progress.duplicate(true)
	main._load_skirmish_match("relay_divide", {
		"mode": "skirmish",
		"scenario_id": "network_hold",
		"ai_difficulty": "standard",
		"ai_intent": "secure_then_assault",
	})
	if main.start_menu_panel.visible or main.deployment_mode != "skirmish":
		failures.append("deploying a skirmish should close the deployment menu")
	if main.objective_target_point_ids != ["central_relay", "network_east"]:
		failures.append("skirmish HUD should highlight all required network points")
	main._show_match_result("MatchWon", {"message": "Network held for 90 seconds."})
	if not main.result_visible or not main.result_overlay.visible:
		failures.append("skirmish completion should show the match result panel")
	if main.campaign_progress.progress != campaign_before:
		failures.append("skirmish results should not change campaign progress")
	main._restart_match()
	if main.simulation.get_match_mode() != "skirmish" or main.result_visible:
		failures.append("rematch should hide the result panel and preserve skirmish mode")
	main._return_to_deployment()
	if not main.start_menu_panel.visible or not main.skirmish_menu_container.visible:
		failures.append("return to deployment should reopen the skirmish setup tab")

	if failures.is_empty():
		print("SKIRMISH_SCENARIO_PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("SKIRMISH_SCENARIO_FAIL")
		quit(1)


func _prepare_network_hold(simulation, team: String, point_ids: Array) -> void:
	var hub_id: String = simulation._first_building_for_team(team, "command_hub")
	var hub_position: Vector3 = simulation.buildings[hub_id]["position"]
	for point_id in point_ids:
		var point: Dictionary = simulation.control_points[point_id]
		point["owner"] = team
		point["capture_progress"] = 100.0 if team == "player" else -100.0
		point["position"] = hub_position
	simulation._update_forward_staging_states()


func _step_without_ai(simulation, count: int) -> void:
	for _index in range(count):
		simulation._ai_timer = 0.0
		simulation.step_fixed()


func _has_event(simulation, event_type: String, field_name: String, expected_value: Variant) -> bool:
	for event in simulation.event_history:
		if str(event.get("event_type", "")) == event_type and event.get(field_name, null) == expected_value:
			return true
	return false
