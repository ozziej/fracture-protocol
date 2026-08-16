extends SceneTree

const SimulationScript = preload("res://src/rts_simulation.gd")


func _initialize() -> void:
	var failures: Array[String] = []

	var policy_sim = SimulationScript.new()
	root.add_child(policy_sim)
	policy_sim.start_match("relay_crossroads")
	var initial_summary: Dictionary = policy_sim.get_ai_summary()
	if str(initial_summary.get("difficulty", "")) != "standard":
		failures.append("authored missions should start with the Standard AI profile")
	if str(initial_summary.get("intent", "")) != "secure_then_assault":
		failures.append("Relay Crossroads should author the secure-then-assault intent")
	if not _has_event(policy_sim, "AIIntentDeclared"):
		failures.append("AI intent should be announced as a player-readable event")
	var standard_profile: Dictionary = policy_sim._ai_controller.profile
	var credits_before: float = policy_sim.enemy_credits
	policy_sim.set_ai_difficulty("aggressive")
	var aggressive_summary: Dictionary = policy_sim.get_ai_summary()
	var aggressive_profile: Dictionary = policy_sim._ai_controller.profile
	if str(aggressive_summary.get("difficulty", "")) != "aggressive" or float(aggressive_profile.get("decision_interval_seconds", 0.0)) >= float(standard_profile.get("decision_interval_seconds", 0.0)):
		failures.append("Aggressive difficulty should use a faster authored decision profile")
	if int(aggressive_profile.get("minimum_attack_group_size_delta", 0)) >= int(standard_profile.get("minimum_attack_group_size_delta", 0)):
		failures.append("Aggressive difficulty should lower the authored attack-group threshold")
	if policy_sim.enemy_credits != credits_before:
		failures.append("changing AI difficulty must not grant hidden credits")
	policy_sim.set_ai_difficulty("defensive")
	var defensive_profile: Dictionary = policy_sim._ai_controller.profile
	if float(defensive_profile.get("decision_interval_seconds", 0.0)) <= float(aggressive_profile.get("decision_interval_seconds", 0.0)) or int(defensive_profile.get("capture_group_size", 0)) <= int(aggressive_profile.get("capture_group_size", 0)):
		failures.append("Defensive difficulty should be slower and require a larger staging group")

	var collector_id := _find_entity(policy_sim.units, "collector", "player")
	var player_refinery_id := _find_entity(policy_sim.buildings, "refinery", "player")
	var player_hq_id := _find_entity(policy_sim.buildings, "command_hub", "player")
	var enemy_hq_id := _find_entity(policy_sim.buildings, "command_hub", "enemy")
	if collector_id.is_empty() and not player_refinery_id.is_empty() and not player_hq_id.is_empty():
		collector_id = policy_sim._add_collector("player", "north_field", player_refinery_id, player_hq_id, policy_sim.buildings[player_refinery_id]["position"])
	if not collector_id.is_empty() and not enemy_hq_id.is_empty():
		policy_sim.units[collector_id]["position"] = policy_sim.buildings[enemy_hq_id]["position"] + Vector3(8.0, 0.0, 0.0)
		policy_sim.units[collector_id]["target_position"] = policy_sim.units[collector_id]["position"]
		policy_sim._visibility_system.invalidate()
	policy_sim.set_ai_intent("raid_economy")
	var raid_summary: Dictionary = policy_sim.get_ai_summary()
	var raid_target: String = policy_sim._ai_controller._select_attack_target(player_hq_id, enemy_hq_id)
	if str(raid_summary.get("intent", "")) != "raid_economy" or raid_target != collector_id:
		failures.append("Raid Economy intent should select a player Collector as its first economic target")
	if str(raid_summary.get("intent_message", "")).find("Collectors") < 0:
		failures.append("AI intent feedback should explain the economic target")

	var phase_sim = SimulationScript.new()
	root.add_child(phase_sim)
	phase_sim.start_match("relay_crossroads")
	_run_ticks(phase_sim, 20)
	var phase_summary: Dictionary = phase_sim.get_ai_summary()
	if str(phase_summary.get("phase", "")) != "securing":
		failures.append("the standard opening AI phase should report that it is securing territory")
	if not _has_event(phase_sim, "AIPhaseChanged"):
		failures.append("AI phase changes should be visible in the event stream")

	var territory_sim = SimulationScript.new()
	root.add_child(territory_sim)
	territory_sim.start_match("relay_crossroads")
	var central: Dictionary = territory_sim.control_points["central_relay"]
	var west: Dictionary = territory_sim.control_points["west_crossing"]
	if str(central.get("strategic_role", "")) != "network_hub" or float(central.get("income_per_second", 0.0)) != 15.0 or float(central.get("supply_link_bonus", 0.0)) != 10.0:
		failures.append("Central Relay should expose its authored network-hub payoff")
	if str(west.get("strategic_role", "")) != "forward_staging":
		failures.append("West Crossing should expose its authored forward-staging role")
	central["owner"] = "player"
	central["capture_progress"] = 100.0
	var territory_summary: Dictionary = territory_sim.get_territory_summary()
	if float(territory_summary.get("player_income_per_second", 0.0)) != 15.0 or float(territory_summary.get("player_supply_link_bonus", 0.0)) != 10.0:
		failures.append("captured Central Relay should report its income and supply payoffs")

	var hub_id := _find_entity(territory_sim.buildings, "command_hub", "player")
	var hub_position: Vector3 = territory_sim.buildings[hub_id]["position"]
	var bridge_id := territory_sim._add_building("player", "relay", hub_position + Vector3(18.0, 0.0, 0.0))
	central["position"] = hub_position + Vector3(47.0, 0.0, 0.0)
	var connected_sources: Array = territory_sim._get_connected_supply_source_ids("player")
	if not connected_sources.has(bridge_id) or not connected_sources.has("central_relay"):
		failures.append("Central Relay should extend the supply link far enough to connect the next relay segment")

	var ranger_id := _find_entity(territory_sim.units, "ranger", "player")
	west["owner"] = "player"
	west["capture_progress"] = 100.0
	west["position"] = hub_position
	territory_sim.units[ranger_id]["position"] = hub_position
	territory_sim.units[ranger_id]["target_position"] = hub_position
	territory_sim.units[ranger_id]["health"] = 20.0
	territory_sim._update_forward_staging_states()
	territory_sim.issue_command("repair", "player", {"building_id": hub_id})
	_step_without_ai(territory_sim, 1)
	if not bool(west.get("staging_active", false)) or territory_sim.get_repair_station_id("player", hub_position).is_empty() or float(territory_sim.units[ranger_id]["health"]) != 60.0:
		failures.append("a Command Hub repair circle should apply the standard repair pulse")

	if failures.is_empty():
		print("AI_TERRITORY_DEPTH_PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("AI_TERRITORY_DEPTH_FAIL")
		quit(1)


func _run_ticks(simulation, count: int) -> void:
	for _index in range(count):
		simulation.step_fixed()


func _step_without_ai(simulation, count: int) -> void:
	for _index in range(count):
		simulation._ai_timer = 0.0
		simulation.step_fixed()


func _find_entity(entities: Dictionary, kind: String, team: String) -> String:
	for entity_id in entities:
		if entities[entity_id]["kind"] == kind and entities[entity_id]["team"] == team:
			return entity_id
	return ""


func _has_event(simulation, event_type: String) -> bool:
	for event in simulation.event_history:
		if str(event.get("event_type", "")) == event_type:
			return true
	return false
