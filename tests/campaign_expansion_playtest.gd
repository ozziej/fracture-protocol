extends SceneTree

const SimulationScript = preload("res://src/rts_simulation.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	var silent: Node = SimulationScript.new()
	root.add_child(silent)
	silent.start_match("silent_recovery")
	_playtest_silent_recovery(silent, failures)

	var long_road: Node = SimulationScript.new()
	root.add_child(long_road)
	long_road.start_match("long_road")
	_playtest_long_road(long_road, failures)

	var long_road_runtime: Node = SimulationScript.new()
	root.add_child(long_road_runtime)
	long_road_runtime.start_match("long_road")
	_playtest_long_road_runtime(long_road_runtime, failures)

	var long_road_direct_arrival: Node = SimulationScript.new()
	root.add_child(long_road_direct_arrival)
	long_road_direct_arrival.start_match("long_road")
	_playtest_long_road_direct_arrival(long_road_direct_arrival, failures)

	var holdfast: Node = SimulationScript.new()
	root.add_child(holdfast)
	holdfast.start_match("holdfast")
	_playtest_holdfast(holdfast, failures)

	if failures.is_empty():
		print("CAMPAIGN_PLAYTEST_PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("CAMPAIGN_PLAYTEST_FAIL")
		quit(1)


func _playtest_silent_recovery(simulation: Node, failures: Array[String]) -> void:
	var campaign: Dictionary = simulation.get_campaign_state()
	if not bool(campaign.get("active", false)) or str(campaign.get("id", "")) != "silent_recovery":
		failures.append("Silent Recovery should activate its campaign objective service")
	if simulation.get_level_routes().size() != 3 or simulation.get_level_route("north_pass").get("waypoints", []).size() != 6:
		failures.append("Silent Recovery should expose the authored mountain-pass route")
	if _count_kind(simulation.units, "player", "warden") != 3 or _count_kind(simulation.units, "player", "bulwark") != 1:
		failures.append("Silent Recovery should start with exactly three Wardens and one Bulwark")
	if _count_kind(simulation.units, "enemy", "raider") != 6:
		failures.append("Silent Recovery should field two moving patrols and two relay guards per pass")

	var warden_id: String = _find_authored(simulation.units, "silent_warden_1")
	if warden_id.is_empty():
		failures.append("Silent Recovery should author a recoverable Warden unit")
		return
	# Short interactive slice: move the same Warden onto each sealed case.
	simulation.units[warden_id]["position"] = simulation.mission_items["recovery_case_north"]["position"]
	simulation.step_fixed()
	simulation.units[warden_id]["position"] = simulation.mission_items["recovery_case_south"]["position"]
	simulation.step_fixed()
	var collected_state: Dictionary = simulation.get_campaign_state()
	if str(collected_state.get("phase_id", "")) != "disable_relays":
		failures.append("Silent Recovery should advance after both recovery cases are collected")

	var bulwark_id: String = _find_authored(simulation.units, "silent_bulwark")
	var north_relay_id: String = _find_authored(simulation.buildings, "silent_relay_north")
	var south_relay_id: String = _find_authored(simulation.buildings, "silent_relay_south")
	if bulwark_id.is_empty() or north_relay_id.is_empty() or south_relay_id.is_empty():
		failures.append("Silent Recovery should author both relay targets and its Bulwark")
		return
	simulation._apply_damage(north_relay_id, 9999.0, bulwark_id)
	simulation.step_fixed()
	simulation._apply_damage(south_relay_id, 9999.0, bulwark_id)
	simulation.step_fixed()
	if str(simulation.get_campaign_state().get("phase_id", "")) != "exfiltrate":
		failures.append("Silent Recovery should advance to exfiltration after both relays are destroyed")
	simulation.units[warden_id]["position"] = Vector3(-92.0, 0.0, 0.0)
	simulation.step_fixed()
	if not simulation.match_over or simulation.match_winner != "player":
		failures.append("Silent Recovery should complete when a Warden reaches the extraction zone")
	print("CAMPAIGN_PLAYTEST_SILENT_RECOVERY_PASS ticks=%d" % simulation.current_tick)


func _playtest_long_road(simulation: Node, failures: Array[String]) -> void:
	var carrier_id: String = _find_authored(simulation.units, "long_road_command_carrier")
	if carrier_id.is_empty():
		failures.append("The Long Road should start with a Mobile Command Unit")
		return
	var route: Dictionary = simulation.get_level_route("north_pass")
	if route.get("waypoints", []).size() != 6:
		failures.append("The Long Road should use the full authored North Pass route")
	simulation.issue_command("move", "player", {"entity_ids": [carrier_id], "position": Vector3(90.0, 0.0, 0.0)})
	simulation.step_fixed()
	if simulation.units[carrier_id].get("waypoints", []).size() < 2:
		failures.append("The Long Road convoy order should route around the mountain walls")
	# The long-distance travel is covered by the route/path assertion; visit the
	# authored checkpoints directly so the short test still exercises route
	# enforcement, deployment, and the construction handoff.
	var waypoints: Array = route.get("waypoints", [])
	for checkpoint_index in range(1, waypoints.size()):
		simulation.units[carrier_id]["position"] = simulation._level_vector3(waypoints[checkpoint_index])
		simulation.step_fixed()
	if str(simulation.get_campaign_state().get("phase_id", "")) != "deploy_base":
		failures.append("The Long Road should enter the deploy phase at the eastern pad")
	simulation.issue_command("deploy", "player", {"unit_id": carrier_id})
	simulation.step_fixed()
	var deployed_id: String = _find_kind(simulation.buildings, "player", "forward_base")
	if deployed_id.is_empty():
		failures.append("The Long Road deploy command should create an under-construction Forward Base")
		return
	_run_ticks(simulation, 100)
	if not bool(simulation.buildings.get(deployed_id, {}).get("complete", false)):
		failures.append("The Long Road Forward Base should finish its deployment cycle")
	if not simulation.match_over or simulation.match_winner != "player":
		failures.append("The Long Road should complete after Forward Base deployment")
	print("CAMPAIGN_PLAYTEST_LONG_ROAD_PASS ticks=%d" % simulation.current_tick)


func _playtest_long_road_runtime(simulation: Node, failures: Array[String]) -> void:
	var convoy_ids: Array = []
	for unit_id in simulation.units:
		if str(simulation.units[unit_id].get("team", "")) == "player":
			convoy_ids.append(str(unit_id))
	if convoy_ids.is_empty():
		failures.append("The Long Road runtime convoy should include its carrier and escort units")
		return
	var convoy_escort_ids: Array = []
	var convoy_carrier_id := ""
	for convoy_id in convoy_ids:
		if str(simulation.units[convoy_id].get("kind", "")) == "command_carrier":
			convoy_carrier_id = convoy_id
		else:
			convoy_escort_ids.append(convoy_id)
	if not convoy_carrier_id.is_empty():
		simulation.issue_command("move", "player", {"entity_ids": [convoy_carrier_id], "position": Vector3(85.0, 0.0, 0.0)})
	if not convoy_escort_ids.is_empty():
		simulation.issue_command("attack_move", "player", {"entity_ids": convoy_escort_ids, "position": Vector3(85.0, 0.0, 0.0)})
	_run_ticks(simulation, 1250)
	var campaign: Dictionary = simulation.get_campaign_state()
	if str(campaign.get("phase_id", "")) != "deploy_base" or not bool(campaign.get("deployment_ready", false)):
		failures.append("The Long Road should register a real convoy arrival at the eastern deployment pad")
	if not _has_event(simulation, "CampaignDeploymentReady"):
		failures.append("The eastern deployment pad should provide an explicit deploy-ready receipt")
	var carrier_id := _find_authored(simulation.units, "long_road_command_carrier")
	if carrier_id.is_empty():
		failures.append("The Mobile Command Unit should survive the authored convoy route")
		return
	simulation.issue_command("deploy", "player", {"unit_id": carrier_id})
	simulation.step_fixed()
	var deployed_id: String = _find_kind(simulation.buildings, "player", "forward_base")
	if deployed_id.is_empty():
		failures.append("A registered eastern arrival should accept the Forward Base deployment command")
		return
	_run_ticks(simulation, 100)
	if not simulation.match_over or simulation.match_winner != "player":
		failures.append("The runtime convoy should complete after deploying the Forward Base")
	print("CAMPAIGN_PLAYTEST_LONG_ROAD_RUNTIME_PASS ticks=%d" % simulation.current_tick)


func _playtest_long_road_direct_arrival(simulation: Node, failures: Array[String]) -> void:
	var carrier_id := _find_authored(simulation.units, "long_road_command_carrier")
	var campaign: Dictionary = simulation.get_campaign_state()
	if str(campaign.get("objective_text", "")) != "Move the carrier to the deployment pad.":
		failures.append("The Long Road escort objective should stay concise in the HUD")
	simulation.units[carrier_id]["position"] = Vector3(90.0, 0.0, 0.0)
	simulation.step_fixed()
	campaign = simulation.get_campaign_state()
	if str(campaign.get("phase_id", "")) != "deploy_base" or not bool(campaign.get("deployment_ready", false)):
		failures.append("Physical arrival at the eastern pad should unlock DEPLOY BASE even if a proximity checkpoint was missed")
	print("CAMPAIGN_PLAYTEST_LONG_ROAD_DIRECT_ARRIVAL_PASS ticks=%d" % simulation.current_tick)


func _playtest_holdfast(simulation: Node, failures: Array[String]) -> void:
	var campaign: Dictionary = simulation.get_campaign_state()
	if str(campaign.get("phase_id", "")) != "build_perimeter":
		failures.append("Holdfast should begin with a perimeter-building phase")
	var base_id: String = _find_authored(simulation.buildings, "holdfast_forward_base")
	var tech_id: String = _find_authored(simulation.buildings, "holdfast_tech")
	var refinery_id: String = _find_authored(simulation.buildings, "holdfast_refinery")
	var assembly_id: String = _find_authored(simulation.buildings, "holdfast_assembly")
	var collector_id: String = _find_authored(simulation.units, "holdfast_collector")
	if base_id.is_empty() or tech_id.is_empty() or refinery_id.is_empty() or assembly_id.is_empty() or collector_id.is_empty() or not simulation.resource_nodes.has("holdfast_field"):
		failures.append("Holdfast should start from a defended base with authored income and reinforcement infrastructure")
		return
	var collector: Dictionary = simulation.units[collector_id]
	if str(collector.get("collector_source_id", "")) != "holdfast_field" or str(collector.get("collector_destination_id", "")) != refinery_id:
		failures.append("Holdfast should start with a Collector routed from the local field to the Resource Processor")
	var assembly_turret_status: Dictionary = simulation.get_build_placement_status("player", "bastion_turret", Vector3(70.0, 0.0, 18.0), assembly_id)
	if bool(assembly_turret_status.get("valid", false)):
		failures.append("Holdfast Assembly Bay should not be a Bastion Turret construction source")
	var starting_credits: float = simulation.player_credits
	_run_ticks(simulation, 140)
	if simulation.player_credits <= starting_credits:
		failures.append("Holdfast's authored Collector should deliver income before the first assault")
	simulation.issue_command("produce", "player", {"building_id": assembly_id, "unit_type": "ranger"})
	_run_ticks(simulation, 90)
	if _count_kind(simulation.units, "player", "ranger") < 3:
		failures.append("Holdfast's Assembly Bay should make reinforcements available to purchase")
	simulation.issue_command("build", "player", {"building_type": "sensor_mast", "position": Vector3(86.0, 0.0, -8.0), "source_building_id": base_id})
	simulation.issue_command("build", "player", {"building_type": "bastion_turret", "position": Vector3(94.0, 0.0, -8.0), "source_building_id": base_id})
	simulation.issue_command("research", "player", {"building_id": tech_id, "technology_id": "hardened_chassis"})
	_run_ticks(simulation, 85)
	if _count_kind(simulation.buildings, "player", "sensor_mast") < 1 or _count_kind(simulation.buildings, "player", "bastion_turret") < 1:
		failures.append("Holdfast should allow a Forward Base to construct new perimeter structures")
	if str(simulation.get_campaign_state().get("phase_id", "")) != "hold_base":
		failures.append("Holdfast should advance to the defence phase after two structures complete")
	var defence_phase: Dictionary = simulation._campaign().get_current_phase()
	if int(defence_phase.get("duration_ticks", 0)) < 900 or int(defence_phase.get("wave_count", 0)) < 5 or defence_phase.get("wave_unit_sets", []).size() < 5:
		failures.append("Holdfast should use a longer defence timer with escalating authored waves")
	if not simulation.is_technology_unlocked("player", "hardened_chassis"):
		failures.append("Holdfast should allow the Hardened Chassis unit upgrade package")
	var upgraded_warden_id: String = _find_authored(simulation.units, "holdfast_warden_1")
	if upgraded_warden_id.is_empty() or float(simulation.units[upgraded_warden_id].get("max_health", 0.0)) <= 250.0:
		failures.append("Hardened Chassis should increase Warden durability after research completes")
	var nearby_raider_id: String = simulation._add_unit("enemy", "raider", Vector3(86.0, 0.0, -5.0))
	_run_ticks(simulation, 8)
	if not _has_event(simulation, "StructureWeaponFired"):
		failures.append("Holdfast perimeter turrets should engage a nearby assault unit")
	_run_ticks(simulation, 320)
	if simulation.match_over:
		failures.append("Holdfast should not resolve after the old 30-second defence window")
	if not _has_event(simulation, "CampaignDefenceWaveStarted"):
		failures.append("Holdfast should spawn authored assault waves")
	_run_ticks(simulation, 700)
	if not simulation.match_over or simulation.match_winner != "player":
		failures.append("Holdfast should complete after the Forward Base survives the full defence timer")
	var wave_unit_sets: Array = defence_phase.get("wave_unit_sets", [])
	if simulation._campaign().wave_index < 5 or wave_unit_sets.size() < 5 or wave_unit_sets[4].size() < 6:
		failures.append("Holdfast should deliver all five escalating waves, including a six-unit final push")
	print("CAMPAIGN_PLAYTEST_HOLDFAST_PASS ticks=%d" % simulation.current_tick)


func _run_ticks(simulation: Node, count: int) -> void:
	for _index in range(count):
		simulation.step_fixed()


func _count_kind(entities: Dictionary, team: String, kind: String) -> int:
	var count: int = 0
	for entity_id in entities:
		var entity: Dictionary = entities[entity_id]
		if str(entity.get("team", "")) == team and str(entity.get("kind", "")) == kind:
			count += 1
	return count


func _find_authored(entities: Dictionary, authored_id: String) -> String:
	for entity_id in entities:
		if str(entities[entity_id].get("authored_id", "")) == authored_id:
			return str(entity_id)
	return ""


func _find_kind(entities: Dictionary, team: String, kind: String) -> String:
	for entity_id in entities:
		var entity: Dictionary = entities[entity_id]
		if str(entity.get("team", "")) == team and str(entity.get("kind", "")) == kind:
			return str(entity_id)
	return ""


func _has_event(simulation: Node, event_type: String) -> bool:
	for event in simulation.event_history:
		if str(event.get("event_type", "")) == event_type:
			return true
	return false
