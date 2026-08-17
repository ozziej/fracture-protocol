extends SceneTree

const SimulationScript = preload("res://src/rts_simulation.gd")
const CampaignProgressScript = preload("res://src/campaign_progress.gd")


func _initialize() -> void:
	await process_frame
	var failures: Array[String] = []
	var fresh_path := "/private/tmp/fracture-protocol-doctrine-fresh-%d.json" % Time.get_ticks_usec()
	_remove_file(fresh_path)
	var progress = CampaignProgressScript.new(fresh_path)
	var summary: Dictionary = progress.get_progress_summary()
	if int(summary.get("schema_version", 0)) != 3:
		failures.append("Fresh campaign progress should use schema version 3")
	if progress.get_doctrines().size() != 3 or progress.is_doctrine_choice_unlocked() or not progress.get_doctrine_id().is_empty():
		failures.append("Fresh campaign should expose three locked doctrine packages without a selection")

	for mission_id in ["relay_divide", "relay_crossroads", "silent_recovery", "long_road", "holdfast", "network_sever"]:
		progress.mark_complete(mission_id)
	if not progress.is_unlocked("counterstroke") or not progress.is_doctrine_choice_unlocked():
		failures.append("Network Sever should unlock Counterstroke and the persistent doctrine reward")
	var selected: Dictionary = progress.choose_doctrine("logistics", "counterstroke")
	if not bool(selected.get("valid", false)) or progress.get_doctrine_id() != "logistics":
		failures.append("A newly unlocked campaign should persist the selected Logistics doctrine")
	var rejected: Dictionary = progress.choose_doctrine("armoured", "counterstroke")
	if bool(rejected.get("valid", false)):
		failures.append("A campaign doctrine should be a one-time choice")
	var restored = CampaignProgressScript.new(fresh_path)
	if restored.get_doctrine_id() != "logistics" or restored.get_doctrine_state().get("history", []).size() != 1:
		failures.append("Doctrine selection and its receipt should survive save reload")

	var migration_path := "/private/tmp/fracture-protocol-doctrine-migration-%d.json" % Time.get_ticks_usec()
	_remove_file(migration_path)
	var legacy := {
		"schema_version": 2,
		"completed": ["relay_divide", "relay_crossroads", "silent_recovery", "long_road", "holdfast", "network_sever"],
		"unlocked": ["relay_divide", "network_sever"],
		"flags": {},
		"results": {},
		"unlocked_content": {"units": ["ranger", "collector"], "buildings": ["refinery", "assembly_bay", "storage_silo"], "technologies": []}
	}
	var legacy_file := FileAccess.open(migration_path, FileAccess.WRITE)
	legacy_file.store_string(JSON.stringify(legacy))
	legacy_file.flush()
	legacy_file.close()
	var migrated = CampaignProgressScript.new(migration_path)
	var migrated_summary: Dictionary = migrated.get_progress_summary()
	if int(migrated_summary.get("schema_version", 0)) != 3 or not migrated.is_unlocked("counterstroke") or not migrated.is_doctrine_choice_unlocked():
		failures.append("Schema-2 saves should migrate their mission chain and doctrine reward without replaying missions")

	var logistics_doctrine: Dictionary = restored.get_doctrine("logistics")
	var logistics_sim: Node = SimulationScript.new()
	root.add_child(logistics_sim)
	logistics_sim.start_match("counterstroke", "", {"mode": "campaign", "campaign_doctrine": logistics_doctrine})
	if logistics_sim.get_campaign_doctrine_id() != "logistics" or int(logistics_sim.player_credits) != 1100:
		failures.append("Logistics doctrine should apply its opening credit package in Counterstroke")
	if _count_kind(logistics_sim.buildings, "player", "storage_silo") != 1 or _count_kind(logistics_sim.units, "player", "collector") != 2:
		failures.append("Logistics doctrine should add a Storage Silo and a second Collector route")
	var counter_state: Dictionary = logistics_sim.get_campaign_state()
	if str(counter_state.get("id", "")) != "counterstroke" or str(counter_state.get("objective_type", "")) != "destroy_targets":
		failures.append("Counterstroke should start with its authored forward-guard breakthrough phase")
	if counter_state.get("target_ids", []).size() != 2:
		failures.append("Counterstroke should expose two forward-guard targets")
	for building_id in logistics_sim.buildings.keys():
		var building: Dictionary = logistics_sim.buildings[building_id]
		if str(building.get("authored_id", "")) in ["counter_enemy_sensor", "counter_enemy_assembly"] or str(building.get("mission_target_id", "")) == "counter_enemy_sensor":
			logistics_sim.buildings.erase(building_id)
	logistics_sim.step_fixed()
	if int(logistics_sim._campaign().phase_index) != 1:
		failures.append("Counterstroke should advance to the relay breach after its forward guard is removed")
	var central_position: Vector3 = logistics_sim.control_points["central_relay"]["position"]
	for unit_id in logistics_sim.units:
		var unit: Dictionary = logistics_sim.units[unit_id]
		if str(unit.get("team", "")) == "player" and str(unit.get("kind", "")) != "collector":
			unit["position"] = central_position
			unit["target_position"] = central_position
			unit["order"] = "idle"
		elif str(unit.get("team", "")) == "enemy":
			unit["position"] = Vector3(96.0, 0.0, -58.0)
	logistics_sim.control_points["central_relay"]["owner"] = "player"
	logistics_sim.control_points["central_relay"]["capture_progress"] = 100.0
	logistics_sim._campaign().phase_state["progress"] = 419.0
	logistics_sim.step_fixed()
	if int(logistics_sim._campaign().phase_index) != 2:
		failures.append("Counterstroke should advance to its final command-hub push after the relay hold")
	for building_id in logistics_sim.buildings.keys():
		var building: Dictionary = logistics_sim.buildings[building_id]
		if str(building.get("authored_id", "")) == "counter_enemy_hq":
			logistics_sim.buildings.erase(building_id)
	logistics_sim.step_fixed()
	if not logistics_sim.match_over or logistics_sim.match_winner != "player":
		failures.append("Counterstroke should resolve as a player win after the final command hub is removed")
	logistics_sim.restart_match()
	if logistics_sim.get_campaign_doctrine_id() != "logistics" or _count_kind(logistics_sim.buildings, "player", "storage_silo") != 1 or logistics_sim.match_over:
		failures.append("Rematching should preserve the selected doctrine package while clearing the previous result")

	var armoured_doctrine: Dictionary = restored.get_doctrine("armoured")
	var armoured_sim: Node = SimulationScript.new()
	root.add_child(armoured_sim)
	armoured_sim.start_match("iron_front", "", {"mode": "campaign", "campaign_doctrine": armoured_doctrine})
	if _count_kind(armoured_sim.units, "player", "warden") != 2 or int(armoured_sim.player_credits) != 950:
		failures.append("Armoured doctrine should add a Warden and its opening credit package in Iron Front")
	var armoured_phase: Dictionary = armoured_sim._campaign().get_current_phase()
	if int(armoured_phase.get("wave_unit_sets", []).size()) != 6:
		failures.append("Armoured doctrine should change the Iron Front assault composition")

	var recon_doctrine: Dictionary = restored.get_doctrine("recon")
	var recon_sim: Node = SimulationScript.new()
	root.add_child(recon_sim)
	recon_sim.start_match("iron_front", "", {"mode": "campaign", "campaign_doctrine": recon_doctrine})
	if _count_kind(recon_sim.buildings, "player", "sensor_mast") != 1:
		failures.append("Recon doctrine should add a forward Sensor Mast in Iron Front")
	var recon_phase: Dictionary = recon_sim._campaign().get_current_phase()
	if int(recon_phase.get("wave_delay_ticks", 0)) != 120 or int(recon_phase.get("wave_interval_ticks", 0)) != 195:
		failures.append("Recon doctrine should delay the Iron Front assault waves")

	if failures.is_empty():
		print("CAMPAIGN_DOCTRINE_PROGRESSION_PASS")
		_remove_file(fresh_path)
		_remove_file(migration_path)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("CAMPAIGN_DOCTRINE_PROGRESSION_FAIL")
	_remove_file(fresh_path)
	_remove_file(migration_path)
	quit(1)


func _count_kind(entities: Dictionary, team: String, kind: String) -> int:
	var count := 0
	for entity_id in entities:
		var entity: Dictionary = entities[entity_id]
		if str(entity.get("team", "")) == team and str(entity.get("kind", "")) == kind:
			count += 1
	return count


func _remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
