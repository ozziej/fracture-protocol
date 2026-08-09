extends SceneTree

const SimulationScript = preload("res://src/rts_simulation.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	var simulation = SimulationScript.new()
	root.add_child(simulation)
	simulation.start_match()

	var initial_supply: Dictionary = simulation.get_supply_summary("player")
	if int(initial_supply["unsupplied_units"]) != 0:
		failures.append("starting force should be connected to the Command Hub")
	if int(initial_supply["connected_sources"]) != 1:
		failures.append("starting network should have one connected source")

	var economy_sim = SimulationScript.new()
	root.add_child(economy_sim)
	economy_sim.start_match()
	var collector_id := _find_entity(economy_sim.units, "collector", "player")
	if collector_id.is_empty():
		failures.append("match should start with a player collector")
	else:
		var collector: Dictionary = economy_sim.units[collector_id]
		if collector["collector_source_id"] != "north_field":
			failures.append("collector should have a specific resource source")
		if not economy_sim.buildings.has(collector["collector_destination_id"]):
			failures.append("collector should have a specific refinery destination")
		var credits_before_delivery: float = economy_sim.player_credits
		_run_ticks(economy_sim, 105)
		if economy_sim.player_credits <= credits_before_delivery:
			failures.append("collector delivery should increase player credits")
		if not _has_event(economy_sim, "ResourceDelivered", "unit_id", collector_id):
			failures.append("collector delivery should emit a ResourceDelivered event")
		if float(economy_sim.resource_nodes["north_field"]["remaining"]) >= 5000.0:
			failures.append("collector delivery should consume source resources")

	var defense_sim = SimulationScript.new()
	root.add_child(defense_sim)
	defense_sim.start_match()
	var defense_collector_id := _find_entity(defense_sim.units, "collector", "player")
	var defense_attacker_id := _find_entity(defense_sim.units, "raider", "enemy")
	if defense_collector_id.is_empty() or defense_attacker_id.is_empty():
		failures.append("collector defense playtest needs a collector and an enemy raider")
	else:
		defense_sim.units[defense_collector_id]["position"] = Vector3(-8.0, 0.0, -1.0)
		defense_sim.units[defense_collector_id]["target_position"] = defense_sim.units[defense_collector_id]["position"]
		defense_sim.units[defense_attacker_id]["position"] = Vector3(-2.0, 0.0, -1.0)
		defense_sim.issue_command("attack", "enemy", {
			"entity_ids": [defense_attacker_id],
			"target_id": defense_collector_id,
		})
		_run_ticks(defense_sim, 3)
		if defense_sim.units[defense_collector_id]["collector_state"] != "retreating":
			failures.append("damaged collector should switch to retreating")
		if not _has_event(defense_sim, "UnitDamaged", "attacker_id", defense_collector_id):
			failures.append("collector should defend itself while retreating")
		var home_id: String = defense_sim.units[defense_collector_id]["collector_home_id"]
		var home_position: Vector3 = defense_sim.buildings[home_id]["position"]
		_run_ticks(defense_sim, 45)
		if defense_sim.units[defense_collector_id]["position"].distance_to(home_position) > 12.0:
			failures.append("retreating collector should move back toward its base")

	var technology_sim = SimulationScript.new()
	root.add_child(technology_sim)
	technology_sim.start_match()
	var technology_assembly_id := _find_entity(technology_sim.buildings, "assembly_bay", "player")
	var units_before_gate: int = technology_sim.units.size()
	if technology_assembly_id.is_empty():
		failures.append("technology playtest needs a player Assembly Bay")
	else:
		technology_sim.issue_command("produce", "player", {"building_id": technology_assembly_id, "unit_type": "bulwark"})
		_run_ticks(technology_sim, 1)
		if technology_sim.units.size() != units_before_gate:
			failures.append("Bulwark production should be gated before research")
		if not _has_event(technology_sim, "OrderRejected", "order", "produce"):
			failures.append("gated production should explain its rejection")
		technology_sim.issue_command("research", "player", {"building_id": technology_assembly_id, "technology_id": "advanced_targeting"})
		_run_ticks(technology_sim, 1)
		if str(technology_sim.get_research_status("player")["active_id"]) != "advanced_targeting":
			failures.append("Assembly Bay should start Advanced Targeting research")
		_run_ticks(technology_sim, 85)
		if not technology_sim.is_technology_unlocked("player", "advanced_targeting"):
			failures.append("research should unlock Advanced Targeting")
		if not _has_event(technology_sim, "TechnologyUnlocked", "technology_id", "advanced_targeting"):
			failures.append("research completion should emit TechnologyUnlocked")

		var repair_unit_id := _find_entity(technology_sim.units, "ranger", "player")
		var repair_hub_id := _find_entity(technology_sim.buildings, "command_hub", "player")
		if repair_unit_id.is_empty() or repair_hub_id.is_empty():
			failures.append("repair playtest needs a player unit and Command Hub")
		else:
			technology_sim.units[repair_unit_id]["position"] = technology_sim.buildings[repair_hub_id]["position"]
			technology_sim.units[repair_unit_id]["target_position"] = technology_sim.units[repair_unit_id]["position"]
			technology_sim.units[repair_unit_id]["health"] = 40.0
			var credits_before_repair: float = technology_sim.player_credits
			technology_sim.issue_command("repair", "player", {"entity_ids": [repair_unit_id]})
			_run_ticks(technology_sim, 1)
			if technology_sim.units[repair_unit_id]["health"] <= 40.0:
				failures.append("a damaged unit near base should be repairable")
			if technology_sim.player_credits >= credits_before_repair:
				failures.append("unit repair should spend credits")
			if not _has_event(technology_sim, "UnitRepaired", "unit_id", repair_unit_id):
				failures.append("unit repair should emit UnitRepaired")

		var repair_building_id := _find_entity(technology_sim.buildings, "refinery", "player")
		if repair_building_id.is_empty():
			failures.append("repair playtest needs a player refinery")
		else:
			technology_sim.buildings[repair_building_id]["health"] = 250.0
			technology_sim.issue_command("repair", "player", {"entity_ids": [repair_building_id]})
			_run_ticks(technology_sim, 1)
			if technology_sim.buildings[repair_building_id]["health"] <= 250.0:
				failures.append("a damaged structure should be repairable")
			if not _has_event(technology_sim, "BuildingRepaired", "building_id", repair_building_id):
				failures.append("building repair should emit BuildingRepaired")

		var units_before_bulwark: int = technology_sim.units.size()
		technology_sim.issue_command("produce", "player", {"building_id": technology_assembly_id, "unit_type": "bulwark"})
		_run_ticks(technology_sim, 46)
		if technology_sim.units.size() <= units_before_bulwark or _find_entity(technology_sim.units, "bulwark", "player").is_empty():
			failures.append("research should unlock Bulwark production")

	var navigation_sim = SimulationScript.new()
	root.add_child(navigation_sim)
	navigation_sim.start_match()
	var navigation_unit_ids: Array = navigation_sim.get_player_unit_ids()
	var navigation_unit_id: String = str(navigation_unit_ids[0]) if not navigation_unit_ids.is_empty() else ""
	if navigation_unit_id.is_empty():
		failures.append("navigation playtest needs a player unit")
	else:
		navigation_sim.issue_command("move", "player", {
			"entity_ids": [navigation_unit_id],
			"position": Vector3(0.0, 0.0, 17.0),
		})
		_run_ticks(navigation_sim, 1)
		var planned_waypoints: Array = navigation_sim.units[navigation_unit_id].get("waypoints", [])
		if planned_waypoints.size() < 2:
			failures.append("movement through an obstacle should create a detour path")
		_run_ticks(navigation_sim, 180)
		if navigation_sim.units[navigation_unit_id]["position"].distance_to(Vector3(0.0, 0.0, 17.0)) > 1.0:
			failures.append("a detoured move order should reach its destination")
		navigation_sim.issue_command("move", "player", {
			"entity_ids": [navigation_unit_id],
			"position": Vector3(25.0, 0.0, 20.0),
		})
		_run_ticks(navigation_sim, 6)
		navigation_sim.issue_command("stop", "player", {"entity_ids": [navigation_unit_id]})
		_run_ticks(navigation_sim, 1)
		var stopped_position: Vector3 = navigation_sim.units[navigation_unit_id]["position"]
		_run_ticks(navigation_sim, 20)
		if navigation_sim.units[navigation_unit_id]["position"].distance_to(stopped_position) > 0.2:
			failures.append("stop order should halt a unit and clear its route")

	var player_unit_ids: Array = simulation.get_player_unit_ids()
	var scout_id: String = str(player_unit_ids[0]) if not player_unit_ids.is_empty() else ""
	if scout_id.is_empty():
		failures.append("playtest needs a player unit")
	else:
		simulation.issue_command("move", "player", {
			"entity_ids": [scout_id],
			"position": Vector3(-1.0, 0.0, 28.0),
		})
		_run_ticks(simulation, 90)
		var remote_supply: Dictionary = simulation.get_supply_summary("player")
		if int(remote_supply["unsupplied_units"]) < 1:
			failures.append("a unit beyond the relay network should become unsupplied")
		if not _has_event(simulation, "SupplyStateChanged", "unit_id", scout_id):
			failures.append("supply loss should emit a SupplyStateChanged event")

	var credits_before_build: float = simulation.player_credits
	simulation.issue_command("build", "player", {
		"building_type": "relay",
		"position": Vector3(-18.0, 0.0, 12.0),
	})
	_run_ticks(simulation, 1)
	var relay_id := _find_entity(simulation.buildings, "relay", "player")
	if relay_id.is_empty():
		failures.append("relay placement should work near a connected Command Hub")
	elif simulation.player_credits >= credits_before_build:
		failures.append("relay placement should spend credits")
	_run_ticks(simulation, 45)
	if relay_id.is_empty() or not simulation.buildings.has(relay_id) or not simulation.buildings[relay_id]["complete"]:
		failures.append("relay should finish construction")
	else:
		var network_supply: Dictionary = simulation.get_supply_summary("player")
		if int(network_supply["connected_sources"]) < 2:
			failures.append("a completed relay should extend the connected network")

	if not scout_id.is_empty() and not relay_id.is_empty() and simulation.buildings.has(relay_id):
		simulation.issue_command("move", "player", {
			"entity_ids": [scout_id],
			"position": simulation.buildings[relay_id]["position"],
		})
		_run_ticks(simulation, 70)
		var recovered_supply: Dictionary = simulation.get_supply_summary("player")
		if int(recovered_supply["unsupplied_units"]) != 0:
			failures.append("a unit returning to a relay should recover supply")

	var west_position: Vector3 = simulation.control_points["west_crossing"]["position"]
	simulation.issue_command("move", "player", {
		"entity_ids": simulation.get_player_unit_ids(),
		"position": west_position,
	})
	_run_ticks(simulation, 70)
	if simulation.control_points["west_crossing"]["owner"] != "player":
		failures.append("a player force should capture the nearby West Crossing")

	var assembly_id := _find_entity(simulation.buildings, "assembly_bay", "player")
	var unit_count_before_production: int = simulation.units.size()
	if assembly_id.is_empty():
		failures.append("playtest needs a player Assembly Bay")
	else:
		simulation.issue_command("produce", "player", {
			"building_id": assembly_id,
			"unit_type": "raider",
		})
		_run_ticks(simulation, 35)
		if simulation.units.size() <= unit_count_before_production:
			failures.append("production queue should spawn a raider")

	var combat_sim = SimulationScript.new()
	root.add_child(combat_sim)
	combat_sim.start_match()
	var attacker_id := _find_entity(combat_sim.units, "warden", "player")
	var target_id := _find_entity(combat_sim.units, "raider", "enemy")
	if attacker_id.is_empty() or target_id.is_empty():
		failures.append("combat playtest needs a Warden and a Raider")
	else:
		combat_sim.units[attacker_id]["position"] = Vector3(-6.0, 0.0, -1.0)
		combat_sim.units[attacker_id]["target_position"] = combat_sim.units[attacker_id]["position"]
		combat_sim.units[target_id]["position"] = Vector3(0.0, 0.0, -1.0)
		combat_sim.units[target_id]["target_position"] = combat_sim.units[target_id]["position"]
		combat_sim.units[target_id]["health"] = 1.0
		combat_sim.issue_command("attack_move", "player", {
			"entity_ids": [attacker_id],
			"position": Vector3(2.0, 0.0, -1.0),
		})
		_run_ticks(combat_sim, 3)
		if not _has_event(combat_sim, "UnitDamaged", "attacker_id", attacker_id):
			failures.append("an attack-move order should produce combat damage")
		if combat_sim.units.has(target_id):
			failures.append("an attack-move unit should be able to destroy its target")
		_run_ticks(combat_sim, 30)
		if combat_sim.units.has(attacker_id) and combat_sim.units[attacker_id]["position"].distance_to(Vector3(2.0, 0.0, -1.0)) > 0.75:
			failures.append("an attack-move unit should resume its route after combat")

	if failures.is_empty():
		print("SKIRMISH_PLAYTEST_PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("SKIRMISH_PLAYTEST_FAIL")
		quit(1)


func _run_ticks(simulation, count: int) -> void:
	for _index in range(count):
		# Keep this harness focused on player orders; the AI has its own runtime coverage.
		simulation._ai_timer = 0.0
		simulation.step_fixed()


func _has_event(simulation, event_type: String, field_name: String, expected_value: String) -> bool:
	for event in simulation.event_history:
		if event.get("event_type", "") == event_type and str(event.get(field_name, "")) == expected_value:
			return true
	return false


func _find_entity(entities: Dictionary, kind: String, team: String) -> String:
	for entity_id in entities:
		if entities[entity_id]["kind"] == kind and entities[entity_id]["team"] == team:
			return entity_id
	return ""
