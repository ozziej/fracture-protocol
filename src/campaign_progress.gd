class_name CampaignProgress
extends RefCounted

const DATA_PATH := "res://data/campaign_data.json"
const SAVE_PATH := "user://campaign_progress.json"

var campaign_data: Dictionary = {}
var progress: Dictionary = {
	"schema_version": 2,
	"completed": [],
	"unlocked": ["relay_divide"],
	"flags": {},
	"results": {},
	"unlocked_content": {"units": ["ranger", "collector"], "buildings": ["refinery", "assembly_bay", "storage_silo"], "technologies": []},
}
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
	var first_completion := not level_id in completed
	if first_completion:
		completed.append(level_id)
	progress["completed"] = completed
	var results: Dictionary = progress.get("results", {})
	var stored_outcome := outcome.duplicate(true)
	if first_completion:
		stored_outcome["rewards_granted"] = _grant_rewards(level_id)
	results[level_id] = stored_outcome
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
				break
	progress["unlocked"] = unlocked
	_save_progress()
	for mission in campaign_data.get("missions", []):
		if str(mission.get("id", "")) == level_id:
			var next_id := str(mission.get("unlock_on_complete", ""))
			return next_id if next_id in unlocked else ""
	return ""


func get_missions() -> Array:
	return campaign_data.get("missions", []).duplicate(true)


func get_mission(level_id: String) -> Dictionary:
	for mission_value in campaign_data.get("missions", []):
		var mission: Dictionary = mission_value
		if str(mission.get("id", "")) == level_id:
			return mission.duplicate(true)
	return {}


func get_mission_rewards(level_id: String) -> Dictionary:
	return get_mission(level_id).get("rewards", {"units": [], "buildings": [], "technologies": []}).duplicate(true)


func get_mission_reward_text(level_id: String) -> String:
	return str(get_mission(level_id).get("reward_text", ""))


func get_unlocked_content(category: String) -> Array:
	return progress.get("unlocked_content", {}).get(category, []).duplicate()


func is_content_unlocked(category: String, content_id: String) -> bool:
	return content_id in get_unlocked_content(category)


func get_progress_summary() -> Dictionary:
	return {
		"completed": progress.get("completed", []).duplicate(),
		"unlocked": progress.get("unlocked", []).duplicate(),
		"unlocked_content": progress.get("unlocked_content", {}).duplicate(true),
	}


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
	if not progress.has("unlocked_content"):
		progress["unlocked_content"] = campaign_data.get("initial_content", {"units": ["ranger", "collector"], "buildings": ["refinery", "assembly_bay", "storage_silo"], "technologies": []}).duplicate(true)
	for category in ["units", "buildings", "technologies"]:
		if not progress["unlocked_content"].has(category):
			progress["unlocked_content"][category] = []
	for mission_value in campaign_data.get("missions", []):
		var mission: Dictionary = mission_value
		var mission_id := str(mission.get("id", ""))
		if bool(mission.get("initially_unlocked", false)) and not mission_id in progress["unlocked"]:
			progress["unlocked"].append(mission_id)
	if not "relay_divide" in progress["unlocked"]:
		progress["unlocked"].append("relay_divide")
	# Migrate a pre-reward save without changing its completed mission history.
	for completed_id in progress.get("completed", []):
		_grant_rewards(str(completed_id))
	progress["schema_version"] = 2


func _save_progress() -> void:
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(progress))
		file.flush()


func _grant_rewards(level_id: String) -> Dictionary:
	var granted := {"units": [], "buildings": [], "technologies": []}
	var rewards: Dictionary = get_mission_rewards(level_id)
	var unlocked_content: Dictionary = progress.get("unlocked_content", {})
	for category in ["units", "buildings", "technologies"]:
		var owned: Array = unlocked_content.get(category, [])
		for content_value in rewards.get(category, []):
			var content_id := str(content_value)
			if content_id.is_empty() or content_id in owned:
				continue
			owned.append(content_id)
			granted[category].append(content_id)
		unlocked_content[category] = owned
	progress["unlocked_content"] = unlocked_content
	return granted
