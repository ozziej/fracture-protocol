extends SceneTree

const MainScript = preload("res://src/main.gd")
const SimulationScript = preload("res://src/rts_simulation.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	_test_match_summary(failures)
	await _test_hud_and_result_panel(failures)
	if failures.is_empty():
		print("MATCH_SUMMARY_HUD_PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("MATCH_SUMMARY_HUD_FAIL")
		quit(1)


func _test_match_summary(failures: Array[String]) -> void:
	var simulation = SimulationScript.new()
	root.add_child(simulation)
	simulation.start_match("relay_divide")
	simulation.current_tick = 125
	simulation._emit_event("ResourceDelivered", {"team": "player", "amount": 125.0})
	simulation._emit_event("ResourceChanged", {"team": "player", "amount": 20.0})
	simulation._emit_event("ProductionCompleted", {"team": "player", "unit_type": "ranger"})
	simulation._emit_event("ProductionCompleted", {"team": "enemy", "unit_type": "raider"})
	simulation._emit_event("UnitDamaged", {"attacker_team": "player", "damage": 45.0})
	simulation._emit_event("UnitDestroyed", {"team": "player"})
	simulation._emit_event("UnitDestroyed", {"team": "enemy"})
	simulation._emit_event("BuildingDestroyed", {"team": "player"})
	simulation._emit_event("TerritoryCaptured", {"team": "player"})
	var summary: Dictionary = simulation.get_match_summary()
	if int(summary.get("duration_seconds", 0.0)) != 12:
		failures.append("match summary should report fixed-tick duration")
	if int(summary.get("player_credits_from_collectors", 0.0)) != 125 or int(summary.get("player_credits_from_territory", 0.0)) != 20:
		failures.append("match summary should retain player income sources")
	if int(summary.get("player_units_lost", 0)) != 1 or int(summary.get("enemy_units_lost", 0)) != 1:
		failures.append("match summary should retain unit losses for both teams")
	if int(summary.get("player_buildings_lost", 0)) != 1 or int(summary.get("player_damage_dealt", 0.0)) != 45:
		failures.append("match summary should retain building losses and damage dealt")


func _test_hud_and_result_panel(failures: Array[String]) -> void:
	var main = MainScript.new()
	root.add_child(main)
	await process_frame
	main._load_skirmish_match("relay_divide", {
		"mode": "skirmish",
		"scenario_id": "network_hold",
		"ai_difficulty": "standard",
		"ai_intent": "secure_then_assault",
	})
	main._update_hud()
	if main.find_child("CreditsChipIcon", true, false) == null or main.find_child("TerritoryChipIcon", true, false) == null:
		failures.append("top HUD status chips should expose semantic icons")
	if main.match_context_label == null or main.match_context_label.text.find("SKIRMISH") < 0:
		failures.append("top HUD should identify the active deployment")
	if main.match_time_label == null or main.match_time_label.text.find("TIME") < 0:
		failures.append("top HUD should show the live match timer")
	main._show_match_result("MatchWon", {"message": "Network held for 90 seconds."})
	if main.result_summary_label == null or main.result_summary_label.text.find("MATCH TIME") < 0 or main.result_summary_label.text.find("FORCE LOST") < 0:
		failures.append("match result should show a compact statistical summary")

