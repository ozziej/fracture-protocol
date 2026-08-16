class_name CampaignProgress
extends RefCounted

const DATA_PATH := "res://data/campaign_data.json"
const SAVE_PATH := "user://campaign_progress.json"

var campaign_data: Dictionary = {}
var progress: Dictionary = {"completed": [], "unlocked": ["relay_divide"], "flags": {}, "results": {}}
var save_path := SAVE_PATH


func _init(override_save_path := "") -> void:
	if not str(override_save_path).is_empty():
		save_path = str(override_save_path)
	_load_campaign_data()
	_load_progress()


func is_unlocked(level_id: String) -> bool:
	return level_id in progress.get("unlocked", [])


func mark_complete(level_id: String, outcome: Dictionary = {}) -> String:
	var completed: Array = progress.get("completed", [])
	if not level_id in completed:
		completed.append(level_id)
	progress["completed"] = completed
	var results: Dictionary = progress.get("results", {})
	results[level_id] = outcome.duplicate(true)
	progress["results"] = results
	var flags: Dictionary = progress.get("flags", {})
	for flag in outcome.get("completion_flags", []):
		flags[str(flag)] = true
	progress["flags"] = flags
	var unlocked: Array = progress.get("unlocked", ["relay_divide"])
	for mission in campaign_data.get("missions", []):
		if str(mission.get("id", "")) == level_id:
			var next_id := str(mission.get("unlock_on_complete", ""))
			if not next_id.is_empty() and not next_id in unlocked:
				unlocked.append(next_id)
				progress["unlocked"] = unlocked
				_save_progress()
				return next_id
	_save_progress()
	return ""


func get_missions() -> Array:
	return campaign_data.get("missions", [])


func is_flag_set(flag_id: String) -> bool:
	return bool(progress.get("flags", {}).get(flag_id, false))


func get_result(level_id: String) -> Dictionary:
	return progress.get("results", {}).get(level_id, {}).duplicate(true)


func _load_campaign_data() -> void:
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	if file:
		var parsed = JSON.parse_string(file.get_as_text())
		if parsed is Dictionary:
			campaign_data = parsed


func _load_progress() -> void:
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file:
		var parsed = JSON.parse_string(file.get_as_text())
		if parsed is Dictionary:
			progress = parsed
	if not progress.has("unlocked"):
		progress["unlocked"] = ["relay_divide"]
	if not progress.has("completed"):
		progress["completed"] = []
	if not progress.has("flags"):
		progress["flags"] = {}
	if not progress.has("results"):
		progress["results"] = {}
	if not "relay_divide" in progress["unlocked"]:
		progress["unlocked"].append("relay_divide")


func _save_progress() -> void:
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(progress))
		file.flush()
