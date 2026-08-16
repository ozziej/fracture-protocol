extends SceneTree

const SimulationScript = preload("res://src/rts_simulation.gd")
const CampaignProgressScript = preload("res://src/campaign_progress.gd")


func _initialize() -> void:
	await process_frame
	var failures: Array[String] = []
	var progress_path := "/private/tmp/fracture-protocol-campaign-expansion-progress-%d.json" % Time.get_ticks_usec()
	var progress = CampaignProgressScript.new(progress_path)
	var initial_content: Dictionary = progress.get_progress_summary().get("unlocked_content", {})
	if not progress.is_content_unlocked("units", "ranger") or not progress.is_content_unlocked("units", "collector"):
		failures.append("A fresh campaign should grant only the foundation units")
	if progress.is_content_unlocked("units", "warden") or progress.is_content_unlocked("buildings", "tech_centre"):
		failures.append("A fresh campaign should not grant later-tier content")
	progress.mark_complete("relay_divide")
	if not progress.is_unlocked("relay_crossroads") or not progress.is_content_unlocked("units", "warden") or not progress.is_content_unlocked("buildings", "relay"):
		failures.append("Level 1 completion should unlock Level 2 and its Warden/Relay rewards")
	progress.mark_complete("relay_crossroads")
	if not progress.is_content_unlocked("units", "bulwark") or not progress.is_content_unlocked("technologies", "advanced_targeting"):
		failures.append("Level 2 completion should persist Bulwark and Advanced Targeting rewards")
	progress.mark_complete("silent_recovery")
	progress.mark_complete("long_road")
	progress.mark_complete("holdfast")
	if not progress.is_unlocked("network_sever") or not progress.is_content_unlocked("buildings", "fire_support_battery"):
		failures.append("Holdfast completion should unlock Network Sever and Fire Support Battery")
	var restored = CampaignProgressScript.new(progress_path)
	if not restored.is_content_unlocked("units", "bulwark") or not restored.is_content_unlocked("buildings", "fire_support_battery"):
		failures.append("Campaign rewards should survive a save reload")
	if initial_content.get("technologies", []).size() != 0:
		failures.append("The foundation campaign should start without research technologies")

	var foundation: Node = SimulationScript.new()
	root.add_child(foundation)
	foundation.start_match("relay_divide")
	if foundation.get_faction_id("player") != "coalition" or foundation.get_faction_id("enemy") != "frontier":
		failures.append("Campaign missions should expose the authored Coalition versus Frontier identity")
	if str(foundation.get_faction_profile("player").get("doctrine", "")) != "Fortified network":
		failures.append("The Coalition doctrine should be visible through simulation state")
	if "tech_centre" in foundation.get_level_catalog("allowed_player_buildings"):
		failures.append("Level 1 should keep Tech Centre construction gated")
	if "bulwark" in foundation.get_level_catalog("allowed_player_units"):
		failures.append("Level 1 should keep Bulwark production gated")
	var coalition_sensor_id: String = foundation._add_building("player", "sensor_mast", Vector3(-40.0, 0.0, 20.0))
	var frontier_raider_id: String = foundation._add_unit("enemy", "raider", Vector3(40.0, 0.0, -20.0))
	if float(foundation.buildings[coalition_sensor_id].get("vision_range", 0.0)) <= float(foundation.building_definitions["sensor_mast"].vision_range):
		failures.append("Coalition Sensor Masts should receive their authored vision bonus")
	if float(foundation.units[frontier_raider_id].get("speed", 0.0)) <= float(foundation.unit_definitions["raider"].speed):
		failures.append("Frontier Raiders should receive their authored mobility bonus")

	var gate_expectations: Array[Dictionary] = [
		{"id": "relay_divide", "required_units": ["ranger", "collector"], "required_buildings": ["refinery", "assembly_bay", "storage_silo"], "blocked_units": ["warden", "bulwark"], "blocked_buildings": ["tech_centre", "relay", "sensor_mast", "bastion_turret", "fire_support_battery"]},
		{"id": "relay_crossroads", "required_units": ["ranger", "warden", "bulwark", "collector"], "required_buildings": ["refinery", "assembly_bay", "tech_centre", "storage_silo", "relay"], "blocked_units": [], "blocked_buildings": ["sensor_mast", "bastion_turret", "fire_support_battery"]},
		{"id": "silent_recovery", "required_units": ["warden", "bulwark"], "required_buildings": ["field_repair_station"], "blocked_units": ["ranger", "collector"], "blocked_buildings": ["sensor_mast", "bastion_turret", "fire_support_battery"]},
		{"id": "long_road", "required_units": ["command_carrier", "warden", "ranger"], "required_buildings": ["forward_base", "field_repair_station", "sensor_mast", "bastion_turret"], "blocked_units": ["bulwark"], "blocked_buildings": ["fire_support_battery"]},
		{"id": "holdfast", "required_units": ["ranger", "warden", "bulwark", "collector"], "required_buildings": ["forward_base", "field_repair_station", "sensor_mast", "bastion_turret", "fire_support_battery", "tech_centre", "refinery", "assembly_bay", "storage_silo"], "blocked_units": [], "blocked_buildings": []},
	]
	for expectation_value in gate_expectations:
		var expectation: Dictionary = expectation_value
		var gate_simulation: Node = SimulationScript.new()
		root.add_child(gate_simulation)
		gate_simulation.start_match(str(expectation.get("id", "")))
		var allowed_units: Array = gate_simulation.get_level_catalog("allowed_player_units")
		if allowed_units.is_empty():
			allowed_units = gate_simulation.get_level_catalog("allowed_units")
		var allowed_buildings: Array = gate_simulation.get_level_catalog("allowed_player_buildings")
		if allowed_buildings.is_empty():
			allowed_buildings = gate_simulation.get_level_catalog("allowed_buildings")
		for required_unit in expectation.get("required_units", []):
			if not str(required_unit) in allowed_units:
				failures.append("%s should expose %s as an authored unit option" % [expectation.get("id", ""), required_unit])
		for required_building in expectation.get("required_buildings", []):
			if not str(required_building) in allowed_buildings:
				failures.append("%s should expose %s as an authored building option" % [expectation.get("id", ""), required_building])
		for blocked_unit in expectation.get("blocked_units", []):
			if str(blocked_unit) in allowed_units:
				failures.append("%s should keep %s gated until a later campaign tier" % [expectation.get("id", ""), blocked_unit])
		for blocked_building in expectation.get("blocked_buildings", []):
			if str(blocked_building) in allowed_buildings:
				failures.append("%s should keep %s gated until a later campaign tier" % [expectation.get("id", ""), blocked_building])

	var network: Node = SimulationScript.new()
	root.add_child(network)
	network.start_match("network_sever")
	var initial_network: Dictionary = network.get_campaign_state()
	if str(initial_network.get("objective_type", "")) != "network_hold" or initial_network.get("required_point_ids", []).size() != 1:
		failures.append("Network Sever should expose its connected network-hold objective")
	if network.get_faction_summary().get("enemy", {}).get("display_name", "") != "Frontier":
		failures.append("Network Sever should expose the Frontier counter-offensive faction")
	var network_phase: Dictionary = network._campaign().get_current_phase()
	if int(network_phase.get("wave_count", 0)) != 5 or network_phase.get("wave_unit_sets", []).size() != 5 or int(network_phase.get("wave_interval_ticks", 0)) != 150:
		failures.append("Network Sever should use five authored counter-offensive waves on its fixed-tick interval")
	var wave_network: Node = SimulationScript.new()
	root.add_child(wave_network)
	wave_network.start_match("network_sever")
	for _index in range(90):
		wave_network.step_fixed()
	if not _has_event(wave_network, "CampaignNetworkWaveStarted"):
		failures.append("Network Sever should launch its first scripted counter-offensive wave")

	# Network Sever starts with an authored western relay chain. The test covers
	# the real logistics path without forcing staging_active or paying an
	# artificial relay-entry tax before the objective can begin.
	var central_position: Vector3 = network.control_points["central_relay"]["position"]
	for unit_id in network.units:
		var unit: Dictionary = network.units[unit_id]
		if str(unit.get("team", "")) == "player" and str(unit.get("kind", "")) != "collector":
			unit["position"] = central_position
			unit["target_position"] = central_position
			unit["order"] = "idle"
		elif str(unit.get("team", "")) == "enemy":
			unit["position"] = Vector3(96.0, 0.0, -58.0)
			unit["target_position"] = unit["position"]
			unit["order"] = "idle"
	for _index in range(26):
		network.step_fixed()
	var online_state: Dictionary = network.get_campaign_state()
	if str(network.control_points["central_relay"].get("owner", "")) != "player":
		failures.append("Network Sever should allow the Coalition to capture Central Relay")
	if not bool(online_state.get("network_online", false)) or float(online_state.get("progress", 0.0)) <= 0.0:
		failures.append("A captured and connected Central Relay should advance the hold timer")

	var progress_before_offline := float(network._campaign().phase_state.get("progress", 0.0))
	network.control_points["central_relay"]["owner"] = "neutral"
	network.control_points["central_relay"]["capture_progress"] = 0.0
	network.step_fixed()
	var offline_state: Dictionary = network.get_campaign_state()
	if bool(offline_state.get("network_online", false)) or float(offline_state.get("progress", 0.0)) >= progress_before_offline:
		failures.append("Network Sever should visibly drain progress while the relay link is offline")

	network.control_points["central_relay"]["owner"] = "player"
	network.control_points["central_relay"]["capture_progress"] = 100.0
	network._campaign().phase_state["progress"] = 899.0
	network.step_fixed()
	if not network.match_over or network.match_winner != "player":
		failures.append("Network Sever should resolve as a player win when the connected hold timer completes")

	if failures.is_empty():
		print("CAMPAIGN_PROGRESSION_EXPANSION_PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("CAMPAIGN_PROGRESSION_EXPANSION_FAIL")
	quit(1)


func _has_event(simulation: Node, event_type: String) -> bool:
	for event in simulation.event_history:
		if str(event.get("event_type", "")) == event_type:
			return true
	return false
