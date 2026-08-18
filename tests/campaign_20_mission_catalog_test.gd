extends SceneTree

const SimulationScript = preload("res://src/rts_simulation.gd")
const CampaignProgressScript = preload("res://src/campaign_progress.gd")

const MISSION_IDS := [
	"relay_divide", "relay_crossroads", "silent_recovery", "long_road", "holdfast",
	"network_sever", "counterstroke", "iron_front", "ash_relay", "deep_current",
	"ghost_signal", "redline_crossing", "counterbattery", "split_front", "last_convoy",
	"blackout", "iron_gate", "deep_strike", "final_push", "secure_grid"
]
const SUPPORTED_PHASE_TYPES := ["destroy_targets", "collect_items", "reach", "escort", "build_structures", "deploy", "defend", "network_hold"]
const FLOWERY_OR_OBSCURE_WORDS := ["wherein", "myriad", "unfathomable", "resonance", "obscured", "therein", "henceforth"]


func _initialize() -> void:
	var failures: Array[String] = []
	var progress_path := "/private/tmp/fracture-protocol-campaign-20-progress.json"
	_remove_file(progress_path)
	var progress = CampaignProgressScript.new(progress_path)
	var missions: Array = progress.get_missions()
	if missions.size() != MISSION_IDS.size():
		failures.append("campaign should expose exactly 20 authored missions")
	for index in min(missions.size(), MISSION_IDS.size()):
		var mission: Dictionary = missions[index]
		var mission_id := str(mission.get("id", ""))
		if mission_id != MISSION_IDS[index]:
			failures.append("mission %d should be %s, got %s" % [index + 1, MISSION_IDS[index], mission_id])
		var expected_next: String = MISSION_IDS[index + 1] if index + 1 < MISSION_IDS.size() else ""
		if str(mission.get("unlock_on_complete", "")) != expected_next:
			failures.append("%s should unlock %s" % [mission_id, expected_next if not expected_next.is_empty() else "nothing"])
	if not progress.is_unlocked("relay_divide"):
		failures.append("a fresh campaign should unlock Relay Divide")
	if progress.is_unlocked("ash_relay"):
		failures.append("a fresh campaign should keep Mission 9 locked")

	var simulation = SimulationScript.new()
	root.add_child(simulation)
	for mission_id in MISSION_IDS:
		var preview: Dictionary = simulation.get_campaign_level_preview(mission_id)
		if preview.is_empty():
			failures.append("campaign preview is missing for %s" % mission_id)
			continue
		var briefing := str(preview.get("briefing", ""))
		if briefing.is_empty() or briefing.length() > 130:
			failures.append("%s briefing should be short and present" % mission_id)
		_check_copy(failures, mission_id, briefing)
		var authored: Dictionary = preview.get("campaign_mission", {})
		if mission_id in ["relay_divide", "relay_crossroads"]:
			continue
		if str(authored.get("id", "")) != mission_id:
			failures.append("%s campaign objective should carry its mission ID" % mission_id)
		var authored_briefing := str(authored.get("briefing", ""))
		if authored_briefing.is_empty() or authored_briefing.length() > 130:
			failures.append("%s authored briefing should be short and present" % mission_id)
		_check_copy(failures, "%s briefing" % mission_id, authored_briefing)
		var phases: Array = authored.get("phases", [])
		if phases.is_empty():
			failures.append("%s should have authored campaign phases" % mission_id)
		for phase_value in phases:
			var phase: Dictionary = phase_value
			var phase_type := str(phase.get("type", ""))
			if not phase_type in SUPPORTED_PHASE_TYPES:
				failures.append("%s uses unsupported phase type %s" % [mission_id, phase_type])
				var description := str(phase.get("description", ""))
				if description.is_empty() or description.length() > 140:
					failures.append("%s phase %s should have concise instructions" % [mission_id, str(phase.get("id", ""))])
				_check_copy(failures, "%s/%s" % [mission_id, str(phase.get("id", ""))], description)
				var completion_message := str(phase.get("completion_message", ""))
				if completion_message.is_empty() or completion_message.length() > 140:
					failures.append("%s phase %s should have concise completion feedback" % [mission_id, str(phase.get("id", ""))])
				_check_copy(failures, "%s/%s completion" % [mission_id, str(phase.get("id", ""))], completion_message)
				if phase_type == "escort":
					var route_id := str(phase.get("route_id", ""))
					if route_id.is_empty() or simulation.get_level_route(route_id).get("waypoints", []).size() < 2:
						failures.append("%s escort phase %s should resolve an authored route" % [mission_id, str(phase.get("id", ""))])

		simulation.start_match(mission_id)
		if simulation.get_level_id() != mission_id or simulation.get_match_mode() != "campaign":
			failures.append("%s should load as a campaign match" % mission_id)
		if not simulation.get_campaign_state().get("active", false):
			failures.append("%s should start with an active campaign objective" % mission_id)
		_validate_phase_targets(failures, simulation, mission_id, authored.get("phases", []))
		simulation.step_fixed()

	simulation.queue_free()
	_remove_file(progress_path)
	if failures.is_empty():
		print("CAMPAIGN_20_MISSION_CATALOG_PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("CAMPAIGN_20_MISSION_CATALOG_FAIL")
		quit(1)


func _validate_phase_targets(failures: Array[String], simulation, mission_id: String, phases: Array) -> void:
	for phase_value in phases:
		var phase: Dictionary = phase_value
		var phase_type := str(phase.get("type", ""))
		if phase_type == "destroy_targets":
			for target_id_value in phase.get("target_ids", []):
				var target_id := str(target_id_value)
				if simulation._campaign()._mission_target_position(target_id) == Vector3.INF:
					failures.append("%s target %s should resolve to an authored entity" % [mission_id, target_id])
		elif phase_type == "network_hold":
			for target_id_value in phase.get("target_ids", []):
				if not simulation.control_points.has(str(target_id_value)):
					failures.append("%s network target %s should resolve to a control point" % [mission_id, str(target_id_value)])
		elif phase_type == "collect_items":
			for item_id_value in phase.get("item_ids", []):
				if not simulation.mission_items.has(str(item_id_value)):
					failures.append("%s item %s should resolve to an authored mission item" % [mission_id, str(item_id_value)])


func _check_copy(failures: Array[String], source: String, text: String) -> void:
	var normalized := text.to_lower()
	for word in FLOWERY_OR_OBSCURE_WORDS:
		if normalized.find(word) >= 0:
			failures.append("%s uses avoidable obscure wording: %s" % [source, word])


func _remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
