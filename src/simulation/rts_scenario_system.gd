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
	if str(active_definition.get("objective_type", "")) != "hold_network":
		return
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


func get_result() -> Dictionary:
	if winner.is_empty():
		return {}
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
	var required_points: Array = active_definition.get("player_required_points", [])
	var objective_text := str(active_definition.get("player_objective", ""))
	if str(viewer_team) == "enemy":
		required_points = active_definition.get("enemy_required_points", [])
		objective_text = str(active_definition.get("enemy_objective", ""))
	var hold_ticks: int = max(1, int(active_definition.get("hold_ticks", 900)))
	return {
		"active": true,
		"id": active_scenario_id,
		"display_name": str(active_definition.get("display_name", active_scenario_id.replace("_", " ").capitalize())),
		"description": str(active_definition.get("description", "")),
		"objective_type": str(active_definition.get("objective_type", "")),
		"objective_text": objective_text,
		"required_point_ids": required_points.duplicate(),
		"required_point_names": _point_names(required_points),
		"hold_ticks": hold_ticks,
		"progress_ticks": int(progress.get(str(viewer_team), 0)) if not str(viewer_team).is_empty() else int(progress.get("player", 0)),
		"progress_seconds": float(int(progress.get(str(viewer_team), 0)) if not str(viewer_team).is_empty() else int(progress.get("player", 0))) * simulation.TICK_SECONDS,
		"holding": bool(holding.get(str(viewer_team), false)) if not str(viewer_team).is_empty() else bool(holding.get("player", false)),
		"player_progress_ticks": int(progress.get("player", 0)),
		"enemy_progress_ticks": int(progress.get("enemy", 0)),
		"winner": winner,
		"result_reason": result_reason,
	}


func get_catalog() -> Array:
	return catalog.get("scenarios", []).duplicate(true)


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
