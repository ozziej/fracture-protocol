class_name RtsScenarioSystem
extends RefCounted

## Owns optional, data-driven skirmish objectives. It evaluates objective
## progress from simulation state and reports a result; RtsSimulation remains
## responsible for the authoritative match_over/match_winner transition.

const DATA_PATH := "res://data/skirmish_data.json"

var simulation
var catalog: Dictionary = {}
var active_scenario_id := ""
var active_definition: Dictionary = {}
var progress: Dictionary = {"player": 0, "enemy": 0}
var holding: Dictionary = {"player": false, "enemy": false}
var network_armed: Dictionary = {"player": false, "enemy": false}
var disruption: Dictionary = {"player": 0, "enemy": 0}
var winner := ""
var result_reason := ""


func _init(owner) -> void:
	simulation = owner
	_load_catalog()


func clear() -> void:
	active_scenario_id = ""
	active_definition = {}
	progress = {"player": 0, "enemy": 0}
	holding = {"player": false, "enemy": false}
	network_armed = {"player": false, "enemy": false}
	disruption = {"player": 0, "enemy": 0}
	winner = ""
	result_reason = ""


func configure(scenario_id: String, level_id: String) -> bool:
	clear()
	var requested_id := scenario_id
	if requested_id.is_empty():
		requested_id = str(catalog.get("default_scenario_id", "network_hold"))
	var scenario: Dictionary = _scenario_by_id(requested_id)
	if scenario.is_empty():
		return false
	var available_maps: Array = scenario.get("maps", [])
	if not available_maps.is_empty() and not level_id in available_maps:
		return false
	active_scenario_id = requested_id
	active_definition = scenario.duplicate(true)
	return true


func update() -> void:
	if active_scenario_id.is_empty() or winner != "":
		return
	var objective_type := str(active_definition.get("objective_type", ""))
	if objective_type == "hold_network":
		_update_hold_network()
	elif objective_type == "defend_network":
		_update_defend_network()


func _update_hold_network() -> void:
	var hold_ticks: int = max(1, int(active_definition.get("hold_ticks", 900)))
	var interval: int = max(1, int(active_definition.get("progress_event_interval_ticks", 10)))
	for team in ["player", "enemy"]:
		var is_holding := _team_holds_network(team)
		var previous_holding: bool = bool(holding.get(team, false))
		var previous_progress := int(progress.get(team, 0))
		var next_progress: int = previous_progress + 1 if is_holding else 0
		progress[team] = min(hold_ticks, next_progress)
		holding[team] = is_holding
		if team == "player" and (previous_holding != is_holding or previous_progress != int(progress[team]) and int(progress[team]) % interval == 0):
			_emit_progress_event(team, hold_ticks)
		if is_holding and int(progress[team]) >= hold_ticks:
			winner = team
			result_reason = str(active_definition.get("player_win_message", "Network objective complete.")) if team == "player" else str(active_definition.get("enemy_win_message", "Enemy network objective complete."))
			simulation._emit_event("ScenarioObjectiveCompleted", {
				"scenario_id": active_scenario_id,
				"team": team,
				"progress_ticks": int(progress[team]),
				"hold_ticks": hold_ticks,
				"message": result_reason,
			})
			return


func _update_defend_network() -> void:
	var defend_ticks: int = max(1, int(active_definition.get("defend_ticks", 900)))
	var sever_ticks: int = max(1, int(active_definition.get("sever_ticks", 150)))
	var interval: int = max(1, int(active_definition.get("progress_event_interval_ticks", 10)))
	var is_online := _team_holds_network("player")
	var was_online: bool = bool(holding.get("player", false))
	var was_armed: bool = bool(network_armed.get("player", false))
	var previous_progress := int(progress.get("player", 0))
	var previous_disruption := int(disruption.get("player", 0))
	if is_online:
		network_armed["player"] = true
		progress["player"] = min(defend_ticks, previous_progress + 1)
		disruption["player"] = 0
	else:
		progress["player"] = previous_progress
		if bool(network_armed.get("player", false)):
			disruption["player"] = min(sever_ticks, previous_disruption + 1)
	holding["player"] = is_online

	var current_progress := int(progress.get("player", 0))
	var current_disruption := int(disruption.get("player", 0))
	if was_online != is_online:
		_emit_defend_network_event("ScenarioNetworkStateChanged", defend_ticks, sever_ticks, was_armed and not was_online)
	elif (is_online and current_progress > 0 and current_progress % interval == 0) or (not is_online and current_disruption > 0 and current_disruption % interval == 0):
		_emit_defend_network_event("ScenarioProgressChanged", defend_ticks, sever_ticks)

	if is_online and current_progress >= defend_ticks:
		winner = "player"
		result_reason = str(active_definition.get("victory_message", active_definition.get("player_win_message", "The network defence is complete.")))
		simulation._emit_event("ScenarioObjectiveCompleted", {
			"scenario_id": active_scenario_id,
			"team": winner,
			"objective_type": "defend_network",
			"progress_ticks": current_progress,
			"target_ticks": defend_ticks,
			"network_online": true,
			"network_armed": true,
			"disruption_ticks": 0,
			"sever_ticks": sever_ticks,
			"message": result_reason,
		})
		return
	if bool(network_armed.get("player", false)) and current_disruption >= sever_ticks:
		winner = "enemy"
		result_reason = str(active_definition.get("defeat_message", active_definition.get("enemy_win_message", "The network has been severed.")))
		simulation._emit_event("ScenarioObjectiveCompleted", {
			"scenario_id": active_scenario_id,
			"team": winner,
			"objective_type": "defend_network",
			"progress_ticks": current_progress,
			"target_ticks": defend_ticks,
			"network_online": false,
			"network_armed": true,
			"disruption_ticks": current_disruption,
			"sever_ticks": sever_ticks,
			"message": result_reason,
		})


func get_result() -> Dictionary:
	if winner.is_empty():
		return {}
	var objective_type := str(active_definition.get("objective_type", ""))
	if objective_type == "defend_network":
		return {
			"winner": winner,
			"reason": result_reason,
			"scenario_id": active_scenario_id,
			"objective_type": objective_type,
			"progress_ticks": int(progress.get("player", 0)),
			"target_ticks": int(active_definition.get("defend_ticks", 900)),
			"hold_ticks": int(active_definition.get("defend_ticks", 900)),
			"network_online": bool(holding.get("player", false)),
			"network_armed": bool(network_armed.get("player", false)),
			"disruption_ticks": int(disruption.get("player", 0)),
			"sever_ticks": int(active_definition.get("sever_ticks", 150)),
		}
	return {
		"winner": winner,
		"reason": result_reason,
		"scenario_id": active_scenario_id,
		"progress_ticks": int(progress.get(winner, 0)),
		"hold_ticks": int(active_definition.get("hold_ticks", 900)),
	}


func get_state(viewer_team := "") -> Dictionary:
	if active_scenario_id.is_empty():
		return {"active": false}
	var objective_type := str(active_definition.get("objective_type", ""))
	var is_defend_network := objective_type == "defend_network"
	var required_points: Array = active_definition.get("player_required_points", [])
	var objective_text := str(active_definition.get("player_objective", ""))
	if str(viewer_team) == "enemy":
		if not is_defend_network:
			required_points = active_definition.get("enemy_required_points", [])
		objective_text = str(active_definition.get("enemy_objective", ""))
	var target_ticks: int = max(1, int(active_definition.get("defend_ticks", active_definition.get("hold_ticks", 900))))
	var hold_ticks: int = max(1, int(active_definition.get("hold_ticks", target_ticks)))
	var state_team := str(viewer_team)
	if is_defend_network:
		state_team = "player"
	var state_progress := int(progress.get(state_team, 0))
	var state_holding := bool(holding.get(state_team, false))
	var key_point_id := str(active_definition.get("key_point_id", ""))
	var key_point_name := ""
	if not key_point_id.is_empty() and simulation.control_points.has(key_point_id):
		key_point_name = str(simulation.control_points[key_point_id].get("display_name", key_point_id))
	return {
		"active": true,
		"id": active_scenario_id,
		"display_name": str(active_definition.get("display_name", active_scenario_id.replace("_", " ").capitalize())),
		"description": str(active_definition.get("description", "")),
		"briefing_message": str(active_definition.get("briefing_message", active_definition.get("description", ""))),
		"objective_type": objective_type,
		"objective_text": objective_text,
		"interruption_message": str(active_definition.get("interruption_message", "Restore the required network points.")),
		"victory_message": str(active_definition.get("victory_message", active_definition.get("player_win_message", "Scenario complete."))),
		"defeat_message": str(active_definition.get("defeat_message", active_definition.get("enemy_win_message", "The scenario has been lost."))),
		"required_point_ids": required_points.duplicate(),
		"required_point_names": _point_names(required_points),
		"hold_ticks": hold_ticks,
		"target_ticks": target_ticks,
		"target_seconds": float(target_ticks) * simulation.TICK_SECONDS,
		"progress_ticks": state_progress,
		"progress_seconds": float(state_progress) * simulation.TICK_SECONDS,
		"holding": state_holding,
		"network_online": state_holding if is_defend_network else bool(holding.get(state_team, false)),
		"network_armed": bool(network_armed.get("player", false)) if is_defend_network else bool(network_armed.get(state_team, false)),
		"disruption_ticks": int(disruption.get("player", 0)) if is_defend_network else int(disruption.get(state_team, 0)),
		"disruption_seconds": float(int(disruption.get("player", 0)) if is_defend_network else int(disruption.get(state_team, 0))) * simulation.TICK_SECONDS,
		"sever_ticks": max(1, int(active_definition.get("sever_ticks", 150))),
		"sever_seconds": float(max(1, int(active_definition.get("sever_ticks", 150)))) * simulation.TICK_SECONDS,
		"key_point_id": key_point_id,
		"key_point_name": key_point_name,
		"player_progress_ticks": int(progress.get("player", 0)),
		"enemy_progress_ticks": int(progress.get("enemy", 0)),
		"winner": winner,
		"result_reason": result_reason,
	}


func get_catalog() -> Array:
	return catalog.get("scenarios", []).duplicate(true)


func get_default_ai_intent() -> String:
	if active_scenario_id.is_empty():
		return ""
	return str(active_definition.get("default_ai_intent", ""))


func get_map_catalog() -> Array:
	return catalog.get("maps", []).duplicate(true)


func get_scenarios_for_map(level_id: String) -> Array:
	var result: Array = []
	for scenario in catalog.get("scenarios", []):
		var definition: Dictionary = scenario
		var maps: Array = definition.get("maps", [])
		if maps.is_empty() or level_id in maps:
			result.append(definition.duplicate(true))
	return result


func get_control_point_overrides(level_id: String) -> Array:
	if active_scenario_id.is_empty():
		return []
	var map_overrides: Dictionary = active_definition.get("map_overrides", {})
	var level_override: Dictionary = map_overrides.get(level_id, {})
	return level_override.get("control_points", []).duplicate(true)


func _team_holds_network(team: String) -> bool:
	var points_key := "%s_required_points" % team
	var required_points: Array = active_definition.get(points_key, [])
	if required_points.is_empty():
		return false
	for point_id in required_points:
		if not simulation.control_points.has(point_id) or not simulation._is_forward_staging_active(team, str(point_id)):
			return false
	return true


func _emit_progress_event(team: String, hold_ticks: int) -> void:
	var progress_ticks := int(progress.get(team, 0))
	var is_holding := bool(holding.get(team, false))
	var message := ""
	if is_holding:
		message = "%s online — network hold %ds / %ds." % [str(active_definition.get("display_name", "Scenario")), int(progress_ticks * simulation.TICK_SECONDS), int(hold_ticks * simulation.TICK_SECONDS)]
	else:
		message = "%s interrupted — reclaim the required network points." % str(active_definition.get("display_name", "Scenario"))
	simulation._emit_event("ScenarioProgressChanged", {
		"scenario_id": active_scenario_id,
		"team": team,
		"progress_ticks": progress_ticks,
		"hold_ticks": hold_ticks,
		"holding": is_holding,
		"required_point_ids": active_definition.get("%s_required_points" % team, []).duplicate(),
		"message": message,
	})


func _emit_defend_network_event(event_type: String, defend_ticks: int, sever_ticks: int, reconnected := false) -> void:
	var progress_ticks := int(progress.get("player", 0))
	var disruption_ticks := int(disruption.get("player", 0))
	var is_online := bool(holding.get("player", false))
	var key_point_name := str(active_definition.get("key_point_id", "Central Relay")).replace("_", " ").capitalize()
	if simulation.control_points.has(str(active_definition.get("key_point_id", ""))):
		key_point_name = str(simulation.control_points[str(active_definition.get("key_point_id", ""))].get("display_name", key_point_name))
	var message := ""
	if is_online:
		if event_type == "ScenarioNetworkStateChanged":
			if reconnected:
				message = "Network restored — sever timer reset. Defence progress retained at %s / %s." % [_format_ticks(progress_ticks), _format_ticks(defend_ticks)]
			else:
				message = "Network online — %s + East Network connected. Defence %s / %s." % [key_point_name, _format_ticks(progress_ticks), _format_ticks(defend_ticks)]
		else:
			message = "Network defence %s / %s — chain online." % [_format_ticks(progress_ticks), _format_ticks(defend_ticks)]
	else:
		if event_type == "ScenarioNetworkStateChanged" and bool(network_armed.get("player", false)):
			message = str(active_definition.get("interruption_message", "NETWORK SEVERED — restore the relay chain before the timer expires."))
		else:
			message = "Network defence interrupted — restore the relay chain. Sever timer %s / %s." % [_format_ticks(disruption_ticks), _format_ticks(sever_ticks)]
	simulation._emit_event(event_type, {
		"scenario_id": active_scenario_id,
		"team": "player",
		"objective_type": "defend_network",
		"progress_ticks": progress_ticks,
		"target_ticks": defend_ticks,
		"network_online": is_online,
		"network_armed": bool(network_armed.get("player", false)),
		"disruption_ticks": disruption_ticks,
		"sever_ticks": sever_ticks,
		"required_point_ids": active_definition.get("player_required_points", []).duplicate(),
		"message": message,
	})


func _format_ticks(ticks: int) -> String:
	var total_seconds := int(float(ticks) * simulation.TICK_SECONDS)
	return "%02d:%02d" % [total_seconds / 60, total_seconds % 60]


func _point_names(point_ids: Array) -> Array:
	var names: Array = []
	for point_id in point_ids:
		if simulation.control_points.has(point_id):
			names.append(str(simulation.control_points[point_id].get("display_name", point_id)))
		else:
			names.append(str(point_id))
	return names


func _scenario_by_id(scenario_id: String) -> Dictionary:
	for scenario in catalog.get("scenarios", []):
		var definition: Dictionary = scenario
		if str(definition.get("id", "")) == scenario_id:
			return definition
	return {}


func _load_catalog() -> void:
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null:
		push_warning("Skirmish data could not be opened: %s" % DATA_PATH)
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		catalog = parsed
