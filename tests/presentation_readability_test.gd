extends SceneTree

const MainScript = preload("res://src/main.gd")
const CampaignProgressScript = preload("res://src/campaign_progress.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	var main = MainScript.new()
	root.add_child(main)
	await process_frame

	if main.game_log_enabled or main.event_log_label.visible:
		failures.append("the optional event log should be hidden in the default tactical presentation")
	if main.find_child("ObjectiveStatusPanel", true, false) == null:
		failures.append("objective, progress, and tactical status should share one information band")
	else:
		var viewport_rect: Rect2 = main.get_viewport().get_visible_rect()
		var objective_rect: Rect2 = main.find_child("ObjectiveStatusPanel", true, false).get_global_rect()
		if objective_rect.position.y < viewport_rect.position.y or objective_rect.end.y > viewport_rect.end.y:
			failures.append("objective information band should remain inside the tactical viewport")
	if main.find_child("ResultOutcomeHeading", true, false) == null or main.find_child("ResultReportHeading", true, false) == null:
		failures.append("the result screen should expose distinct outcome and battle-report sections")
	if main.result_receipt_label == null or main.result_mission_label == null:
		failures.append("the result screen should expose separate mission and campaign-receipt labels")

	var ranger_id := _find_unit(main, "ranger", "player")
	if ranger_id.is_empty() or not main.unit_views.has(ranger_id):
		failures.append("readability fixture needs a rendered player Ranger")
	else:
		var ranger_view = main.unit_views[ranger_id]
		if ranger_view.name_label.visible:
			failures.append("unselected units should not render persistent world name labels")
		main.selected_ids = [ranger_id]
		main._sync_views()
		if ranger_view.name_label.visible:
			failures.append("selected unit labels should remain hidden; identity belongs in the selected card")
		main.selected_ids.clear()
		main._sync_views()
		if ranger_view.name_label.visible:
			failures.append("clearing selection should keep the unit identity label hidden")

	var building_id := _find_building(main, "command_hub", "player")
	if not building_id.is_empty() and main.building_views.has(building_id):
		var building_view = main.building_views[building_id]
		if building_view.name_label.visible:
			failures.append("completed unselected buildings should not render persistent name labels")

	var progress_path := "/private/tmp/fracture-protocol-presentation-progress.json"
	_remove_file(progress_path)
	main.campaign_progress = CampaignProgressScript.new(progress_path)
	main._show_match_result("MatchWon", {"message": "Foundation network secured."})
	var result_rect: Rect2 = main.result_panel.get_global_rect()
	var result_viewport_rect: Rect2 = main.get_viewport().get_visible_rect()
	if result_rect.position.x < result_viewport_rect.position.x or result_rect.end.x > result_viewport_rect.end.x or result_rect.position.y < result_viewport_rect.position.y or result_rect.end.y > result_viewport_rect.end.y:
		failures.append("structured result panel should remain inside the tactical viewport")
	if main.result_title_label.text != "VICTORY" or main.result_mission_label.text.find("CAMPAIGN") < 0:
		failures.append("result screen should lead with a clear outcome and mission context")
	if main.result_detail_label.text.find("Foundation network secured.") < 0:
		failures.append("result screen should keep the completion reason in the outcome section")
	main._on_simulation_event("MatchWon", {"message": "Foundation network secured."})
	if not main.result_receipt_label.visible or main.result_receipt_label.text.find("CAMPAIGN RECEIPT") < 0:
		failures.append("campaign completion should place rewards in the dedicated receipt section")
	_remove_file(progress_path)

	main.queue_free()
	await process_frame
	if failures.is_empty():
		print("PRESENTATION_READABILITY_PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("PRESENTATION_READABILITY_FAIL")
		quit(1)


func _find_unit(main, kind: String, team: String) -> String:
	for entity_id in main.simulation.units:
		var unit: Dictionary = main.simulation.units[entity_id]
		if str(unit.get("kind", "")) == kind and str(unit.get("team", "")) == team:
			return str(entity_id)
	return ""


func _find_building(main, kind: String, team: String) -> String:
	for entity_id in main.simulation.buildings:
		var building: Dictionary = main.simulation.buildings[entity_id]
		if str(building.get("kind", "")) == kind and str(building.get("team", "")) == team:
			return str(entity_id)
	return ""


func _remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
