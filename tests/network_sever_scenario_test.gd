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
		"scenario_id": "network_sever",
	})

	if simulation.get_scenario_id() != "network_sever":
		failures.append("network sever should be selectable as a skirmish scenario")
	var initial_state: Dictionary = simulation.get_scenario_state("player")
	if str(initial_state.get("objective_type", "")) != "defend_network":
		failures.append("network sever should expose the defend_network objective type")
	if int(initial_state.get("target_ticks", 0)) != 900 or int(initial_state.get("sever_ticks", 0)) != 150:
		failures.append("network sever should expose 90-second defence and 15-second sever targets")
	if bool(initial_state.get("network_online", true)) or bool(initial_state.get("network_armed", true)):
		failures.append("network sever should begin offline and unarmed")
	if int(initial_state.get("disruption_ticks", -1)) != 0:
		failures.append("unarmed network sever should not accumulate a sever timer")
	var ai_summary: Dictionary = simulation.get_ai_summary()
	if str(ai_summary.get("intent", "")) != "sever_network":
		failures.append("network sever should default the AI intent to sever_network")
	if str(ai_summary.get("target_point_id", "")) != "central_relay":
		failures.append("sever_network should target Central Relay")
	if simulation.get_skirmish_scenarios_for_map("relay_divide").size() != 2 or simulation.get_skirmish_scenarios_for_map("relay_crossroads").size() != 2:
		failures.append("network sever should be available on both authored maps")

	var ai_action_simulation = SimulationScript.new()
	root.add_child(ai_action_simulation)
	ai_action_simulation.start_match("relay_crossroads", "", {"mode": "skirmish", "scenario_id": "network_sever"})
	_run_with_ai(ai_action_simulation, 30)
	if not _has_attack_move_to_point(ai_action_simulation, "central_relay"):
		failures.append("sever_network should issue a normal attack-move toward Central Relay")

	_step_without_ai(simulation, 20)
	if simulation.match_over:
		failures.append("an unarmed network should not cause a premature scenario defeat")

	_prepare_network(simulation, "player")
	_step_without_ai(simulation, 5)
	var online_state: Dictionary = simulation.get_scenario_state("player")
	if not bool(online_state.get("network_online", false)) or not bool(online_state.get("network_armed", false)):
		failures.append("network sever should arm after both protected points are connected")
	if int(online_state.get("progress_ticks", 0)) != 5:
		failures.append("network defence progress should increase while the chain is online")
	if not _has_event(simulation, "ScenarioNetworkStateChanged", "network_online", true):
		failures.append("network going online should emit a readable state event")

	simulation.control_points["central_relay"]["owner"] = "neutral"
	simulation.control_points["central_relay"]["capture_progress"] = 0.0
	simulation._update_forward_staging_states()
	_step_without_ai(simulation, 5)
	var offline_state: Dictionary = simulation.get_scenario_state("player")
	if bool(offline_state.get("network_online", true)):
		failures.append("losing Central Relay should sever the protected network")
	if int(offline_state.get("progress_ticks", 0)) != 5:
		failures.append("defence progress should pause instead of resetting while offline")
	if int(offline_state.get("disruption_ticks", 0)) != 5:
		failures.append("the armed network should accumulate a continuous sever timer")
	if not _has_event(simulation, "ScenarioNetworkStateChanged", "network_online", false):
		failures.append("network going offline should emit a readable interruption event")

	_prepare_network(simulation, "player")
	_step_without_ai(simulation, 1)
	var restored_state: Dictionary = simulation.get_scenario_state("player")
	if not bool(restored_state.get("network_online", false)) or int(restored_state.get("disruption_ticks", -1)) != 0:
		failures.append("reconnecting the relay chain should reset the sever timer")
	if int(restored_state.get("progress_ticks", 0)) <= 5:
		failures.append("reconnecting should retain and resume cumulative defence progress")
	if not _has_event_message(simulation, "ScenarioNetworkStateChanged", "restored"):
		failures.append("network reconnection should emit a readable restoration event")

	var defeat_simulation = SimulationScript.new()
	root.add_child(defeat_simulation)
	defeat_simulation.start_match("relay_divide", "", {"mode": "skirmish", "scenario_id": "network_sever"})
	_prepare_network(defeat_simulation, "player")
	_step_without_ai(defeat_simulation, 1)
	defeat_simulation.control_points["central_relay"]["owner"] = "neutral"
	defeat_simulation.control_points["central_relay"]["capture_progress"] = 0.0
	defeat_simulation._update_forward_staging_states()
	_step_without_ai(defeat_simulation, 149)
	if defeat_simulation.match_over:
		failures.append("network sever should allow recovery before the full 15-second timer")
	_step_without_ai(defeat_simulation, 1)
	if not defeat_simulation.match_over or defeat_simulation.match_winner != "enemy":
		failures.append("an armed network should be defeated after 15 continuous severed seconds")
	if not _has_event(defeat_simulation, "MatchLost", "result_type", "scenario"):
		failures.append("network sever defeat should emit a scenario MatchLost result")
	if not _has_event(defeat_simulation, "MatchLost", "message", "NETWORK LOST — the relay chain remained severed too long."):
		failures.append("network sever defeat should use the authored result message")

	var victory_simulation = SimulationScript.new()
	root.add_child(victory_simulation)
	victory_simulation.start_match("relay_divide", "", {"mode": "skirmish", "scenario_id": "network_sever"})
	_prepare_network(victory_simulation, "player")
	_step_without_ai(victory_simulation, 900)
	if not victory_simulation.match_over or victory_simulation.match_winner != "player":
		failures.append("network sever should award victory after 90 cumulative online seconds")
	if not _has_event(victory_simulation, "MatchWon", "result_type", "scenario"):
		failures.append("network sever victory should emit a scenario MatchWon result")

	var hq_simulation = SimulationScript.new()
	root.add_child(hq_simulation)
	hq_simulation.start_match("relay_divide", "", {"mode": "skirmish", "scenario_id": "network_sever"})
	var player_hq_id: String = hq_simulation._first_building_for_team("player", "command_hub")
	if player_hq_id.is_empty():
		failures.append("network sever HQ regression needs a player Command Hub")
	else:
		hq_simulation.buildings.erase(player_hq_id)
		_step_without_ai(hq_simulation, 1)
		if not hq_simulation.match_over or hq_simulation.match_winner != "enemy":
			failures.append("HQ destruction should remain an immediate alternate defeat")

	await process_frame
	var main = MainScript.new()
	root.add_child(main)
	await process_frame
	main.campaign_progress = CampaignProgressScript.new("/private/tmp/fracture-protocol-network-sever-progress.json")
	var campaign_before: Dictionary = main.campaign_progress.progress.duplicate(true)
	main._load_skirmish_match("relay_divide", {
		"mode": "skirmish",
		"scenario_id": "network_sever",
		"ai_difficulty": "standard",
		"ai_intent": "",
	})
	main._update_hud()
	if main.objective_target_point_ids != ["central_relay", "network_east"]:
		failures.append("network sever HUD should keep both protected relay markers visible")
	if main.scenario_progress_label == null or main.scenario_progress_label.text.find("NETWORK SEVERED") < 0 or main.scenario_progress_label.text.find("SEVER TIMER") < 0:
		failures.append("network sever HUD should show the live sever timer while offline")
	_prepare_network(main.simulation, "player")
	_step_without_ai(main.simulation, 1)
	main._update_hud()
	if main.scenario_progress_label.text.find("NETWORK ONLINE") < 0 or main.scenario_progress_label.text.find("DEFENCE") < 0:
		failures.append("network sever HUD should show cumulative defence progress while online")

	var scenario_index := _find_option_metadata(main.skirmish_scenario_option, "network_sever")
	if scenario_index < 0:
		failures.append("skirmish deployment should list network sever")
	else:
		main.skirmish_scenario_option.select(scenario_index)
		main._on_skirmish_scenario_selected(scenario_index)
		if str(main.skirmish_intent_option.get_item_metadata(main.skirmish_intent_option.get_selected())) != "sever_network":
			failures.append("selecting network sever should default the AI intent selector to sever_network")

	main.simulation.control_points["central_relay"]["owner"] = "neutral"
	main.simulation.control_points["central_relay"]["capture_progress"] = 0.0
	main.simulation._update_forward_staging_states()
	_step_without_ai(main.simulation, 1)
	main._show_match_result("MatchLost", {"message": "Central Relay remained severed for 15 seconds. The Coalition network has fractured."})
	if main.result_detail_label.text.find("NETWORK DEFENCE") < 0 or main.result_detail_label.text.find("SEVER TIMER") < 0:
		failures.append("network sever result detail should distinguish defence progress and sever timer")
	if main.result_summary_label.text.find("NETWORK DEFENCE") < 0 or main.result_summary_label.text.find("SEVER TIMER") < 0:
		failures.append("network sever match summary should distinguish defence progress and sever timer")
	if main.campaign_progress.progress != campaign_before:
		failures.append("network sever skirmish results should not alter campaign progress")
	main._restart_match()
	if main.simulation.get_scenario_id() != "network_sever" or str(main.simulation.get_ai_summary().get("intent", "")) != "sever_network":
		failures.append("network sever rematch should preserve scenario and its default AI intent")

	if failures.is_empty():
		print("NETWORK_SEVER_SCENARIO_PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("NETWORK_SEVER_SCENARIO_FAIL")
		quit(1)


func _prepare_network(simulation, team: String) -> void:
	var hub_id: String = simulation._first_building_for_team(team, "command_hub")
	var hub_position: Vector3 = simulation.buildings[hub_id]["position"]
	for point_id in ["central_relay", "network_east"]:
		var point: Dictionary = simulation.control_points[point_id]
		point["owner"] = team
		point["capture_progress"] = 100.0 if team == "player" else -100.0
		point["position"] = hub_position
	simulation._update_forward_staging_states()


func _step_without_ai(simulation, count: int) -> void:
	for _index in range(count):
		simulation._ai_timer = 0.0
		simulation.step_fixed()


func _run_with_ai(simulation, count: int) -> void:
	for _index in range(count):
		simulation.step_fixed()


func _has_event(simulation, event_type: String, field_name: String, expected_value: Variant) -> bool:
	for event in simulation.event_history:
		if str(event.get("event_type", "")) == event_type and event.get(field_name, null) == expected_value:
			return true
	return false


func _has_event_message(simulation, event_type: String, text: String) -> bool:
	for event in simulation.event_history:
		if str(event.get("event_type", "")) == event_type and str(event.get("message", "")).to_lower().find(text.to_lower()) >= 0:
			return true
	return false


func _find_option_metadata(option: OptionButton, expected: String) -> int:
	if option == null:
		return -1
	for index in range(option.item_count):
		if str(option.get_item_metadata(index)) == expected:
			return index
	return -1


func _has_attack_move_to_point(simulation, point_id: String) -> bool:
	if not simulation.control_points.has(point_id):
		return false
	var target_position: Vector3 = simulation.control_points[point_id]["position"]
	for event in simulation.event_history:
		if str(event.get("event_type", "")) != "OrderIssued" or str(event.get("order", "")) != "attack_move" or str(event.get("team", "")) != "enemy":
			continue
		var issued_position: Vector3 = event.get("position", Vector3.INF)
		if issued_position.distance_to(target_position) < 0.1:
			return true
	return false
