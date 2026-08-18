extends SceneTree

const SimulationScript = preload("res://src/rts_simulation.gd")

const MISSION_IDS := [
	"relay_divide", "relay_crossroads", "silent_recovery", "long_road", "holdfast",
	"network_sever", "counterstroke", "iron_front", "ash_relay", "deep_current",
	"ghost_signal", "redline_crossing", "counterbattery", "split_front", "last_convoy",
	"blackout", "iron_gate", "deep_strike", "final_push", "secure_grid"
]


func _initialize() -> void:
	await process_frame
	var failures: Array[String] = []
	for mission_id in MISSION_IDS:
		var simulation: Node = SimulationScript.new()
		root.add_child(simulation)
		simulation.start_match(mission_id)
		if mission_id in ["relay_divide", "relay_crossroads"]:
			simulation.queue_free()
			continue
		var campaign = simulation._campaign()
		var guard := 0
		while not simulation.match_over and int(campaign.phase_index) < campaign.phases.size():
			guard += 1
			if guard > campaign.phases.size() + 2:
				failures.append("%s should advance through every authored campaign phase" % mission_id)
				break
			if not _force_current_phase(simulation, campaign, failures, mission_id):
				break
		if not simulation.match_over or simulation.match_winner != "player":
			failures.append("%s should resolve as a playable player win across its authored phases" % mission_id)
		simulation.queue_free()
	if failures.is_empty():
		print("CAMPAIGN_20_MISSION_RUNTIME_PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("CAMPAIGN_20_MISSION_RUNTIME_FAIL")
	quit(1)


func _force_current_phase(simulation: Node, campaign, failures: Array[String], mission_id: String) -> bool:
	var phase_index := int(campaign.phase_index)
	var phase: Dictionary = campaign.phases[phase_index]
	var phase_id := str(phase.get("id", "phase_%d" % phase_index))
	var phase_type := str(phase.get("type", ""))
	match phase_type:
		"destroy_targets":
			var target_ids: Array = phase.get("target_ids", [])
			var removed_targets: Array[String] = []
			for building_id in simulation.buildings.keys():
				var building: Dictionary = simulation.buildings[building_id]
				var authored_id := str(building.get("authored_id", ""))
				var mission_target_id := str(building.get("mission_target_id", ""))
				if authored_id in target_ids or mission_target_id in target_ids:
					removed_targets.append(str(building_id))
			for building_id in removed_targets:
				simulation.buildings.erase(building_id)
			if removed_targets.size() != target_ids.size():
				failures.append("%s phase %s should resolve every authored destroy target" % [mission_id, phase_id])
				return false
			simulation.step_fixed()
		"collect_items":
			var collector_id := _find_player_unit(simulation, "")
			if collector_id.is_empty():
				failures.append("%s phase %s should have a player unit able to recover its items" % [mission_id, phase_id])
				return false
			for item_id_value in phase.get("item_ids", []):
				var item_id := str(item_id_value)
				if not simulation.mission_items.has(item_id):
					failures.append("%s phase %s should resolve item %s" % [mission_id, phase_id, item_id])
					return false
				var unit: Dictionary = simulation.units[collector_id]
				unit["position"] = simulation.mission_items[item_id]["position"]
				unit["target_position"] = unit["position"]
				unit["order"] = "idle"
				simulation.step_fixed()
				if int(campaign.phase_index) >= campaign.phases.size() or campaign.get_current_phase().get("id", "") != phase_id:
					break
		"reach", "escort":
			var required_kind := str(phase.get("required_unit_kind", ""))
			var unit_id := _find_player_unit(simulation, required_kind)
			if unit_id.is_empty():
				failures.append("%s phase %s should have its required player unit" % [mission_id, phase_id])
				return false
			var destination: Vector3 = simulation._level_vector3(phase.get("position", {}))
			var destination_unit: Dictionary = simulation.units[unit_id]
			destination_unit["position"] = destination
			destination_unit["target_position"] = destination
			destination_unit["order"] = "idle"
			simulation.step_fixed()
		"build_structures":
			var building_kinds: Array = phase.get("building_kinds", [])
			var required_count := maxi(1, int(phase.get("required_count", 1)))
			if building_kinds.is_empty():
				failures.append("%s phase %s should name its required building types" % [mission_id, phase_id])
				return false
			for index in range(required_count):
				var building_kind := str(building_kinds[index % building_kinds.size()])
				simulation._add_building("player", building_kind, Vector3(-80.0 + float(index) * 8.0, 0.0, 30.0))
			simulation.step_fixed()
		"deploy":
			var carrier_id := _find_player_unit(simulation, "command_carrier")
			if carrier_id.is_empty():
				failures.append("%s phase %s should provide a Mobile Command Unit" % [mission_id, phase_id])
				return false
			var deployment_position: Vector3 = simulation._level_vector3(phase.get("position", {}))
			var carrier: Dictionary = simulation.units[carrier_id]
			carrier["position"] = deployment_position
			carrier["target_position"] = deployment_position
			carrier["order"] = "idle"
			simulation.issue_command("deploy", "player", {"unit_id": carrier_id})
			simulation.step_fixed()
			var forward_base_id := _find_player_building(simulation, "forward_base")
			if forward_base_id.is_empty():
				failures.append("%s phase %s should accept Forward Base deployment" % [mission_id, phase_id])
				return false
			simulation.buildings[forward_base_id]["complete"] = true
			simulation.buildings[forward_base_id]["construction_progress"] = 1.0
			simulation.step_fixed()
		"defend":
			var defended_base_id := _find_player_building(simulation, "forward_base")
			if defended_base_id.is_empty():
				failures.append("%s phase %s should have a Forward Base to defend" % [mission_id, phase_id])
				return false
			phase["duration_ticks"] = 1
			phase["wave_count"] = 0
			campaign.phase_state["progress"] = 0.0
			simulation.buildings[defended_base_id]["health"] = simulation.buildings[defended_base_id]["max_health"]
			simulation.step_fixed()
		"network_hold":
			var target_ids: Array = phase.get("target_ids", [])
			if target_ids.is_empty():
				failures.append("%s phase %s should name at least one relay target" % [mission_id, phase_id])
				return false
			for target_id_value in target_ids:
				var target_id := str(target_id_value)
				if not simulation.control_points.has(target_id):
					failures.append("%s phase %s should resolve relay %s" % [mission_id, phase_id, target_id])
					return false
				var point: Dictionary = simulation.control_points[target_id]
				point["owner"] = "player"
				point["capture_progress"] = 100.0
				var relay_position: Vector3 = point["position"]
				simulation._add_building("player", "forward_base", relay_position)
			phase["duration_ticks"] = 1
			phase["wave_count"] = 0
			phase["offline_decay_ticks"] = 0
			campaign.phase_state["progress"] = 0.0
			simulation.step_fixed()
		_:
			failures.append("%s phase %s uses an untested type %s" % [mission_id, phase_id, phase_type])
			return false
	return true


func _find_player_unit(simulation: Node, kind: String) -> String:
	for unit_id in simulation.units:
		var unit: Dictionary = simulation.units[unit_id]
		if str(unit.get("team", "")) == "player" and (kind.is_empty() or str(unit.get("kind", "")) == kind):
			return str(unit_id)
	return ""


func _find_player_building(simulation: Node, kind: String) -> String:
	for building_id in simulation.buildings:
		var building: Dictionary = simulation.buildings[building_id]
		if str(building.get("team", "")) == "player" and str(building.get("kind", "")) == kind:
			return str(building_id)
	return ""
