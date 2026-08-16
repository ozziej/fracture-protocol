class_name RtsCampaignMissionSystem
extends RefCounted

## Campaign-only objective phases. Skirmish objectives remain owned by
## RtsScenarioSystem; this service adds authored campaign rules such as
## detection, convoy movement, deployment, extraction, and wave defence.

var simulation
var active := false
var definition: Dictionary = {}
var phases: Array = []
var phase_index := 0
var phase_state: Dictionary = {}
var winner := ""
var result_reason := ""
var detected := false
var alarm_ticks := 0
var detection_source_id := ""
var detection_source_kind := ""
var detection_source_position := Vector3.INF
var wave_index := 0
var next_wave_tick := 0
var patrol_started := false


func _init(owner) -> void:
	simulation = owner


func clear() -> void:
	active = false
	definition = {}
	phases = []
	phase_index = 0
	phase_state = {}
	winner = ""
	result_reason = ""
	detected = false
	alarm_ticks = 0
	detection_source_id = ""
	detection_source_kind = ""
	detection_source_position = Vector3.INF
	wave_index = 0
	next_wave_tick = 0
	patrol_started = false


func configure(level_definition: Dictionary) -> bool:
	clear()
	var authored: Dictionary = level_definition.get("campaign_mission", {})
	if authored.is_empty():
		return false
	definition = authored.duplicate(true)
	phases = definition.get("phases", []).duplicate(true)
	if phases.is_empty():
		return false
	active = true
	phase_index = 0
	phase_state = {}
	return true


func activate_after_spawn() -> void:
	if not active:
		return
	_start_phase()
	_start_scripted_patrols()


func update() -> void:
	if not active or not winner.is_empty():
		return
	_update_detection()
	if not winner.is_empty():
		return
	_update_scripted_patrols()
	var phase := _current_phase()
	if phase.is_empty():
		_complete_mission("Campaign objectives complete.")
		return
	match str(phase.get("type", "")):
		"destroy_targets":
			_update_destroy_targets(phase)
		"collect_items":
			_update_collect_items(phase)
		"reach", "escort":
			_update_reach_or_escort(phase)
		"build_structures":
			_update_build_structures(phase)
		"deploy":
			_update_deploy(phase)
		"defend":
			_update_defend(phase)


func can_deploy_forward_base(unit_id: String) -> Dictionary:
	if not active or not winner.is_empty():
		return {"valid": false, "reason": "The campaign objective is not active."}
	var phase := _current_phase()
	if str(phase.get("type", "")) != "deploy":
		return {"valid": false, "reason": "Reach the marked deployment site first."}
	if not simulation.units.has(unit_id):
		return {"valid": false, "reason": "The Mobile Command Unit is no longer available."}
	var unit: Dictionary = simulation.units[unit_id]
	if unit.get("team", "") != "player" or unit.get("kind", "") != "command_carrier":
		return {"valid": false, "reason": "Select the Mobile Command Unit to deploy the base."}
	var destination: Vector3 = simulation._level_vector3(phase.get("position", {}))
	var radius: float = maxf(1.0, float(phase.get("radius", 5.0)))
	if unit["position"].distance_to(destination) > radius:
		return {"valid": false, "reason": "Move the Mobile Command Unit inside the marked deployment zone."}
	if _find_deployed_forward_base() != "":
		return {"valid": false, "reason": "A Forward Base is already deployed."}
	return {"valid": true, "reason": "Deploy the Forward Base here."}


func route_waypoints_for_current_phase(start: Vector3, destination: Vector3) -> Array:
	# A convoy order to the marked deployment pad must follow the authored pass,
	# not the shortest generic obstacle path. Otherwise a valid diagonal detour
	# can arrive at the pad without ever registering the mission checkpoints.
	var phase := _current_phase()
	if str(phase.get("type", "")) != "escort":
		return []
	var route_points := _phase_route_points(phase)
	if route_points.size() < 2:
		return []
	var final_point: Vector3 = route_points[route_points.size() - 1]
	var destination_radius := maxf(10.0, float(phase.get("radius", 5.0)) * 2.0)
	if destination.distance_to(final_point) > destination_radius:
		return []
	var nearest_index := 0
	var nearest_distance := INF
	for point_index in route_points.size():
		var point_distance := start.distance_squared_to(route_points[point_index])
		if point_distance < nearest_distance:
			nearest_distance = point_distance
			nearest_index = point_index
	var result: Array = []
	for point_index in range(nearest_index + 1, route_points.size()):
		result.append(route_points[point_index])
	if result.is_empty() or result.back().distance_to(destination) > 0.15:
		result.append(destination)
	return result


func get_result() -> Dictionary:
	if winner.is_empty():
		return {}
	return {
		"winner": winner,
		"reason": result_reason,
		"mission_id": str(definition.get("id", simulation.get_level_id())),
		"result_type": "campaign",
		"phase_index": phase_index,
		"detected": detected,
		"alarm_ticks": alarm_ticks,
		"completion_flags": definition.get("completion_flags", []).duplicate(),
		"forward_base_established": _find_deployed_forward_base() != "",
	}


func get_state() -> Dictionary:
	if not active:
		return {"active": false}
	var phase := _current_phase()
	var target_ids: Array = phase.get("target_ids", []) if not phase.is_empty() else []
	var target_positions: Array = []
	for target_id in target_ids:
		var position := _mission_target_position(str(target_id))
		if position != Vector3.INF:
			target_positions.append(position)
	var target_position: Vector3 = simulation._level_vector3(phase.get("position", {})) if not phase.is_empty() else Vector3.INF
	var target_count := _target_count(phase)
	var completed_count := _completed_target_count(phase)
	var route_checkpoint: int = 0
	var route_progress: Dictionary = phase_state.get("route_progress", {})
	for checkpoint_value in route_progress.values():
		route_checkpoint = maxi(route_checkpoint, int(checkpoint_value))
	var mission_item_ids := _mission_item_ids()
	var final_destination_phase := _final_destination_phase()
	var final_destination_position: Vector3 = Vector3.INF
	var final_destination_index := -1
	if not final_destination_phase.is_empty():
		final_destination_position = simulation._level_vector3(final_destination_phase.get("position", {}), Vector3.INF)
		final_destination_index = int(final_destination_phase.get("_phase_index", -1))
	var final_destination_revealed := _final_destination_revealed(mission_item_ids, final_destination_index)
	return {
		"active": true,
		"id": str(definition.get("id", simulation.get_level_id())),
		"display_name": str(definition.get("display_name", simulation.get_level_display_name())),
		"briefing": str(definition.get("briefing", simulation.get_level_briefing())),
		"objective_type": str(phase.get("type", "")),
		"phase_index": phase_index,
		"phase_count": phases.size(),
		"phase_id": str(phase.get("id", "phase_%d" % phase_index)),
		"phase_display_name": str(phase.get("display_name", str(phase.get("id", "OBJECTIVE")).replace("_", " ").to_upper())),
		"objective_text": str(phase.get("description", "Complete the current campaign objective.")),
		"target_ids": target_ids.duplicate(),
		"target_positions": target_positions,
		"target_position": target_position,
		"item_ids": phase.get("item_ids", []).duplicate(),
		"mission_item_ids": mission_item_ids,
		"final_destination_position": final_destination_position,
		"final_destination_revealed": final_destination_revealed,
		"route_id": str(phase.get("route_id", "")),
		"route_checkpoint": route_checkpoint,
		"route_checkpoint_count": int(phase_state.get("route_checkpoint_count", 0)),
		"progress": float(phase_state.get("progress", completed_count)),
		"target": float(phase_state.get("target", target_count)),
		"completed_targets": completed_count,
		"target_count": target_count,
		"detected": detected,
		"alarm_ticks": alarm_ticks,
		"detection_source_id": detection_source_id,
		"detection_source_kind": detection_source_kind,
		"detection_source_position": detection_source_position,
		"alarm_seconds": float(alarm_ticks) * simulation.TICK_SECONDS,
		"alarm_limit_seconds": float(definition.get("detection", {}).get("alarm_limit_ticks", 0)) * simulation.TICK_SECONDS,
		"deployment_ready": _deployment_ready(phase),
		"forward_base_id": _find_deployed_forward_base(),
		"winner": winner,
		"result_reason": result_reason,
	}


func uses_hq_victory() -> bool:
	return not active or not bool(definition.get("ignore_hq_victory", false))


func scripted_ai_enabled() -> bool:
	return active and bool(definition.get("scripted_ai", false))


func _mission_item_ids() -> Array:
	var result: Array = []
	for phase_value in phases:
		var phase: Dictionary = phase_value
		if str(phase.get("type", "")) != "collect_items":
			continue
		for item_id_value in phase.get("item_ids", []):
			var item_id := str(item_id_value)
			if not result.has(item_id):
				result.append(item_id)
	return result


func _final_destination_phase() -> Dictionary:
	var result: Dictionary = {}
	for phase_index_value in phases.size():
		var phase: Dictionary = phases[phase_index_value]
		if str(phase.get("type", "")) != "reach":
			continue
		result = phase.duplicate(true)
		result["_phase_index"] = phase_index_value
	return result


func _final_destination_revealed(item_ids: Array, destination_index: int) -> bool:
	if destination_index < 0:
		return false
	if phase_index >= destination_index:
		return true
	for item_id in item_ids:
		if simulation.mission_items.has(str(item_id)) and bool(simulation.mission_items[str(item_id)].get("collected", false)):
			return true
	return false


func _current_phase() -> Dictionary:
	if phase_index < 0 or phase_index >= phases.size():
		return {}
	return phases[phase_index]


func get_current_phase() -> Dictionary:
	return _current_phase().duplicate(true)


func _start_phase() -> void:
	var phase: Dictionary = _current_phase()
	phase_state = {"progress": 0.0, "target": _target_count(phase)}
	phase_state["deployment_ready_announced"] = false
	var route_points: Array = _phase_route_points(phase)
	if str(phase.get("type", "")) == "escort" and route_points.size() >= 2:
		phase_state["route_progress"] = {}
		phase_state["route_checkpoint_count"] = route_points.size()
	wave_index = 0
	next_wave_tick = simulation.current_tick + maxi(1, int(phase.get("wave_delay_ticks", 30)))
	simulation._emit_event("CampaignPhaseStarted", {
		"mission_id": str(definition.get("id", simulation.get_level_id())),
		"phase_id": str(phase.get("id", "phase_%d" % phase_index)),
		"phase_index": phase_index,
		"message": str(phase.get("description", "Campaign objective started.")),
	})


func _complete_phase(message: String) -> void:
	var phase := _current_phase()
	simulation._emit_event("CampaignPhaseCompleted", {
		"mission_id": str(definition.get("id", simulation.get_level_id())),
		"phase_id": str(phase.get("id", "phase_%d" % phase_index)),
		"phase_index": phase_index,
		"message": message,
	})
	phase_index += 1
	if phase_index >= phases.size():
		_complete_mission(message)
		return
	_start_phase()


func _complete_mission(message: String) -> void:
	winner = "player"
	result_reason = message
	simulation._emit_event("CampaignMissionCompleted", {
		"mission_id": str(definition.get("id", simulation.get_level_id())),
		"team": "player",
		"message": message,
		"completion_flags": definition.get("completion_flags", []).duplicate(),
		"forward_base_established": _find_deployed_forward_base() != "",
		"detected": detected,
	})


func _fail_mission(message: String) -> void:
	if not winner.is_empty():
		return
	winner = "enemy"
	result_reason = message
	simulation._emit_event("CampaignMissionFailed", {
		"mission_id": str(definition.get("id", simulation.get_level_id())),
		"team": "enemy",
		"message": message,
	})


func _update_detection() -> void:
	var detection: Dictionary = definition.get("detection", {})
	if not bool(detection.get("enabled", false)):
		return
	var source := _find_detection_source()
	var detected_now := not source.is_empty()
	if detected_now:
		detection_source_id = str(source.get("id", ""))
		detection_source_kind = str(source.get("kind", "observer"))
		detection_source_position = source.get("position", Vector3.INF)
		if not detected:
			detected = true
			var breach_label := "SENSOR GRID BREACHED" if detection_source_kind == "sensor_mast" else "CONTACT"
			simulation._emit_event("MissionAlarmRaised", {
				"team": "player",
				"source_id": detection_source_id,
				"source_kind": detection_source_kind,
				"source_position": detection_source_position,
				"message": "%s — break line of sight or finish before the alarm peaks." % breach_label,
			})
		alarm_ticks += 1
	else:
		alarm_ticks = max(0, alarm_ticks - max(1, int(detection.get("recovery_ticks", 3))))
	var alarm_limit := int(detection.get("alarm_limit_ticks", 0))
	if alarm_limit > 0 and alarm_ticks >= alarm_limit:
		_fail_mission(str(detection.get("failure_message", "The operation stayed exposed too long.")))


func _find_detection_source() -> Dictionary:
	# Prefer a Sensor Mast in the receipt so the player knows when the authored
	# sensor grid, rather than a passing raider, is what exposed the operation.
	for building_id in simulation.buildings:
		var building: Dictionary = simulation.buildings[building_id]
		if str(building.get("team", "")) != "enemy" or str(building.get("kind", "")) != "sensor_mast":
			continue
		if not bool(building.get("complete", false)) or float(building.get("health", 0.0)) <= 0.0:
			continue
		var radius := float(building.get("vision_range", 0.0))
		for unit_id in simulation.units:
			var unit: Dictionary = simulation.units[unit_id]
			if str(unit.get("team", "")) == "player" and float(unit.get("health", 0.0)) > 0.0 and unit["position"].distance_to(building["position"]) <= radius:
				return {"id": str(building_id), "kind": "sensor_mast", "position": building["position"]}
	for unit_id in simulation.units:
		var observer: Dictionary = simulation.units[unit_id]
		if str(observer.get("team", "")) != "enemy" or float(observer.get("health", 0.0)) <= 0.0:
			continue
		var radius := float(observer.get("vision_range", 0.0))
		for player_id in simulation.units:
			var player_unit: Dictionary = simulation.units[player_id]
			if str(player_unit.get("team", "")) == "player" and float(player_unit.get("health", 0.0)) > 0.0 and player_unit["position"].distance_to(observer["position"]) <= radius:
				return {"id": str(unit_id), "kind": str(observer.get("kind", "observer")), "position": observer["position"]}
	return {}


func _update_destroy_targets(phase: Dictionary) -> void:
	var total := _target_count(phase)
	var completed := _completed_target_count(phase)
	phase_state["progress"] = completed
	phase_state["target"] = total
	if completed >= total and total > 0:
		_complete_phase(str(phase.get("completion_message", "The marked targets are destroyed.")))


func _update_collect_items(phase: Dictionary) -> void:
	var required_ids: Array = phase.get("item_ids", [])
	var collected := 0
	for item_id in required_ids:
		if not simulation.mission_items.has(str(item_id)):
			collected += 1
			continue
		var item: Dictionary = simulation.mission_items[str(item_id)]
		if bool(item.get("collected", false)):
			collected += 1
			continue
		for unit_id in simulation.units:
			var unit: Dictionary = simulation.units[unit_id]
			if unit.get("team", "") == "player" and unit["position"].distance_to(item["position"]) <= float(item.get("pickup_radius", 2.5)):
				item["collected"] = true
				simulation._emit_event("MissionItemCollected", {"item_id": item_id, "team": "player", "message": "%s recovered." % item.get("display_name", item_id)})
				collected += 1
				break
	phase_state["progress"] = collected
	phase_state["target"] = required_ids.size()
	if collected >= required_ids.size() and not required_ids.is_empty():
		_complete_phase(str(phase.get("completion_message", "All mission items recovered.")))


func _update_reach_or_escort(phase: Dictionary) -> void:
	var destination: Vector3 = simulation._level_vector3(phase.get("position", {}))
	var radius: float = maxf(1.0, float(phase.get("radius", 5.0)))
	var candidates := _matching_player_units(phase)
	var arrived := 0
	for unit in candidates:
		if unit["position"].distance_to(destination) <= radius:
			arrived += 1
	var required := int(phase.get("required_count", candidates.size()))
	if required <= 0:
		required = candidates.size()
	var route_points: Array = _phase_route_points(phase)
	if str(phase.get("type", "")) == "escort" and route_points.size() >= 2:
		var route_progress: Dictionary = phase_state.get("route_progress", {})
		for unit in candidates:
			var unit_id: String = str(unit.get("id", ""))
			var next_checkpoint: int = int(route_progress.get(unit_id, 1))
			while next_checkpoint < route_points.size() and unit["position"].distance_to(route_points[next_checkpoint]) <= float(phase.get("route_tolerance", 7.0)):
				next_checkpoint += 1
			route_progress[unit_id] = next_checkpoint
		phase_state["route_progress"] = route_progress
		phase_state["route_checkpoint_count"] = route_points.size()
	phase_state["progress"] = arrived
	phase_state["target"] = required
	# The mountain collision owns route enforcement. If the carrier is physically
	# inside the destination pad, do not strand the player in ESCORT because an
	# intermediate proximity checkpoint was missed during steering or combat.
	if arrived >= required and required > 0:
		_complete_phase(str(phase.get("completion_message", "The convoy reached the marked route point.")))


func _update_build_structures(phase: Dictionary) -> void:
	var building_kinds: Array = phase.get("building_kinds", [])
	var completed: int = 0
	for building_id in simulation.buildings:
		var building: Dictionary = simulation.buildings[building_id]
		if str(building.get("team", "")) != "player" or not bool(building.get("complete", false)):
			continue
		if not building_kinds.is_empty() and not str(building.get("kind", "")) in building_kinds:
			continue
		completed += 1
	var required: int = maxi(1, int(phase.get("required_count", 1)))
	phase_state["progress"] = completed
	phase_state["target"] = required
	if completed >= required:
		_complete_phase(str(phase.get("completion_message", "The defensive perimeter is ready.")))


func _update_deploy(phase: Dictionary) -> void:
	var carrier_id := _find_player_unit_kind("command_carrier")
	var destination: Vector3 = simulation._level_vector3(phase.get("position", {}))
	var radius: float = maxf(1.0, float(phase.get("radius", 5.0)))
	var ready: bool = not carrier_id.is_empty() and simulation.units[carrier_id]["position"].distance_to(destination) <= radius
	phase_state["progress"] = 1.0 if ready else 0.0
	phase_state["target"] = 1.0
	if ready:
		if not bool(phase_state.get("deployment_ready_announced", false)):
			phase_state["deployment_ready_announced"] = true
			simulation._emit_event("CampaignDeploymentReady", {
				"team": "player",
				"message": "Eastern deployment pad reached — select the Mobile Command Unit and press DEPLOY BASE.",
			})
		var base_id := _find_deployed_forward_base()
		if not base_id.is_empty() and bool(simulation.buildings[base_id].get("complete", false)):
			_complete_phase(str(phase.get("completion_message", "Forward Base deployed. The next operation will begin from this position.")))


func _update_defend(phase: Dictionary) -> void:
	var base_id := _find_deployed_forward_base()
	if base_id.is_empty() or not simulation.buildings.has(base_id):
		_fail_mission(str(phase.get("failure_message", "The Forward Base has been lost.")))
		return
	if float(simulation.buildings[base_id].get("health", 0.0)) <= 0.0:
		_fail_mission(str(phase.get("failure_message", "The Forward Base has been lost.")))
		return
	var duration: int = maxi(1, int(phase.get("duration_ticks", 900)))
	var elapsed := int(phase_state.get("progress", 0.0)) + 1
	phase_state["progress"] = min(duration, elapsed)
	phase_state["target"] = duration
	if bool(definition.get("scripted_ai", false)) and wave_index < int(phase.get("wave_count", 0)) and simulation.current_tick >= next_wave_tick:
		_spawn_defence_wave(phase, base_id)
	if elapsed >= duration:
		_complete_phase(str(phase.get("completion_message", "The Forward Base held through the assault.")))


func _spawn_defence_wave(phase: Dictionary, base_id: String) -> void:
	var spawn_position: Vector3 = simulation._level_vector3(phase.get("wave_spawn_position", {}))
	var target_position: Vector3 = simulation.buildings[base_id]["position"]
	var kinds: Array = phase.get("wave_units", ["raider", "raider"])
	var spawned: Array = []
	for kind_value in kinds:
		var kind := str(kind_value)
		if not simulation.unit_definitions.has(kind):
			continue
		var unit_id: String = simulation._add_unit("enemy", kind, spawn_position + Vector3(float(spawned.size()) * 1.8, 0.0, float(spawned.size() % 2) * 1.6))
		spawned.append(unit_id)
	if not spawned.is_empty():
		simulation.issue_command("attack_move", "enemy", {"entity_ids": spawned, "position": target_position})
		simulation._emit_event("CampaignDefenceWaveStarted", {"team": "enemy", "wave": wave_index + 1, "message": "ASSAULT WAVE %d — protect the Forward Base." % (wave_index + 1)})
	wave_index += 1
	next_wave_tick = simulation.current_tick + max(1, int(phase.get("wave_interval_ticks", 180)))


func _start_scripted_patrols() -> void:
	if patrol_started:
		return
	patrol_started = true
	for unit_id in simulation.units:
		var unit: Dictionary = simulation.units[unit_id]
		var route_id := str(unit.get("patrol_route_id", ""))
		if route_id.is_empty() or unit.get("team", "") != "enemy":
			continue
		var route: Dictionary = simulation.get_level_route(route_id)
		var points: Array = route.get("waypoints", [])
		if points.size() >= 2:
			simulation.issue_command("patrol", "enemy", {"entity_ids": [unit_id], "position": simulation._level_vector3(points[1]), "patrol_points": points})


func _update_scripted_patrols() -> void:
	for unit_id in simulation.units:
		var unit: Dictionary = simulation.units[unit_id]
		var route_id := str(unit.get("patrol_route_id", ""))
		if route_id.is_empty() or unit.get("team", "") != "enemy":
			continue
		if str(unit.get("order", "")) == "idle":
			var route: Dictionary = simulation.get_level_route(route_id)
			var points: Array = route.get("waypoints", [])
			if points.size() >= 2:
				simulation.issue_command("patrol", "enemy", {"entity_ids": [unit_id], "position": simulation._level_vector3(points[1]), "patrol_points": points})


func _matching_player_units(phase: Dictionary) -> Array:
	var result: Array = []
	var required_ids: Array = phase.get("required_unit_ids", [])
	for unit_id in simulation.units:
		var unit: Dictionary = simulation.units[unit_id]
		if unit.get("team", "") != "player":
			continue
		if not required_ids.is_empty() and not str(unit.get("authored_id", "")) in required_ids:
			continue
		var required_kind := str(phase.get("required_unit_kind", ""))
		if not required_kind.is_empty() and str(unit.get("kind", "")) != required_kind:
			continue
		result.append(unit)
	return result


func _find_player_unit_kind(kind: String) -> String:
	for unit_id in simulation.units:
		var unit: Dictionary = simulation.units[unit_id]
		if unit.get("team", "") == "player" and unit.get("kind", "") == kind:
			return str(unit_id)
	return ""


func _target_count(phase: Dictionary) -> int:
	var ids: Array = phase.get("target_ids", [])
	if not ids.is_empty():
		return ids.size()
	return int(phase.get("required_count", 0))


func _completed_target_count(phase: Dictionary) -> int:
	var completed := 0
	for target_id in phase.get("target_ids", []):
		if _mission_target_position(str(target_id)) == Vector3.INF:
			completed += 1
	return completed


func _mission_target_position(target_id: String) -> Vector3:
	for building_id in simulation.buildings:
		var building: Dictionary = simulation.buildings[building_id]
		if str(building.get("authored_id", "")) == target_id or str(building.get("mission_target_id", "")) == target_id:
			return building["position"]
	return Vector3.INF


func _deployment_ready(phase: Dictionary) -> bool:
	if str(phase.get("type", "")) != "deploy":
		return false
	var carrier_id := _find_player_unit_kind("command_carrier")
	if carrier_id.is_empty():
		return false
	return simulation.units[carrier_id]["position"].distance_to(simulation._level_vector3(phase.get("position", {}))) <= max(1.0, float(phase.get("radius", 5.0)))


func _phase_route_points(phase: Dictionary) -> Array:
	var route_id := str(phase.get("route_id", ""))
	if route_id.is_empty():
		return []
	var route: Dictionary = simulation.get_level_route(route_id)
	var points: Array = []
	for point_data in route.get("waypoints", []):
		points.append(simulation._level_vector3(point_data))
	return points


func _find_deployed_forward_base() -> String:
	for building_id in simulation.buildings:
		var building: Dictionary = simulation.buildings[building_id]
		if building.get("team", "") == "player" and building.get("kind", "") == "forward_base" and bool(building.get("mission_deployed", false)):
			return str(building_id)
	return ""
