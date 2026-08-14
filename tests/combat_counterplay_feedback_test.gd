extends SceneTree

const MainScript = preload("res://src/main.gd")
const SimulationScript = preload("res://src/rts_simulation.gd")
const UnitViewScript = preload("res://src/rts_unit_view.gd")


func _initialize() -> void:
	await process_frame
	var failures: Array[String] = []
	var simulation = SimulationScript.new()
	root.add_child(simulation)
	simulation.start_match("relay_crossroads")

	var enemy_launcher_id := _find_unit(simulation, "bulwark", "enemy")
	var player_ranger_id := _find_unit(simulation, "ranger", "player")
	var player_bulwark_id := _find_unit(simulation, "bulwark", "player")
	if enemy_launcher_id.is_empty() or player_ranger_id.is_empty():
		failures.append("counterplay fixture needs an enemy Bulwark and player Ranger")
	else:
		var enemy_launcher: Dictionary = simulation.units[enemy_launcher_id]
		var player_ranger: Dictionary = simulation.units[player_ranger_id]
		if float(enemy_launcher.get("attack_range", 0.0)) <= 0.0 or float(enemy_launcher.get("minimum_attack_range", 0.0)) <= 0.0:
			failures.append("combat units should expose effective and minimum attack range telemetry")
		player_ranger["position"] = enemy_launcher["position"] + Vector3(-10.0, 0.0, 0.0)
		simulation._fire_weapon(enemy_launcher, player_ranger_id, 1.0)
		if not _has_event(simulation, "LauncherThreatWarning"):
			failures.append("enemy launcher fire should emit a readable threat warning")
		else:
			var warning := _latest_event(simulation, "LauncherThreatWarning")
			if str(warning.get("attacker_display_name", "")) != "Bulwark" or str(warning.get("target_display_name", "")) != "Ranger":
				failures.append("launcher warning should identify attacker and target")
		simulation._apply_damage(player_ranger_id, 18.0, enemy_launcher_id, true)
		if not bool(simulation.units[player_ranger_id].get("under_fire", false)):
			failures.append("damaged player units should enter the under-fire state")
		var damage_event := _latest_event(simulation, "UnitDamaged")
		if str(damage_event.get("attacker_display_name", "")) != "Bulwark" or not bool(damage_event.get("is_splash", false)):
			failures.append("damage events should identify the source and splash damage")

	var ranger_view = UnitViewScript.new()
	root.add_child(ranger_view)
	if not player_ranger_id.is_empty():
		ranger_view.setup(simulation.units[player_ranger_id])
		ranger_view.sync(simulation.units[player_ranger_id], true)
		if ranger_view.attack_range_ring == null or not ranger_view.attack_range_ring.visible:
			failures.append("selected combat units should show their attack range")
		if ranger_view.minimum_range_ring == null or ranger_view.minimum_range_ring.visible:
			failures.append("direct-fire Rangers should not show a minimum attack dead-zone ring")
		if ranger_view.under_fire_ring == null or not ranger_view.under_fire_ring.visible or ranger_view.under_fire_marker == null or not ranger_view.under_fire_marker.visible:
			failures.append("under-fire units should show a world-space warning")

	if not player_bulwark_id.is_empty():
		var bulwark_view = UnitViewScript.new()
		root.add_child(bulwark_view)
		bulwark_view.setup(simulation.units[player_bulwark_id])
		bulwark_view.sync(simulation.units[player_bulwark_id], true)
		if bulwark_view.minimum_range_ring == null or not bulwark_view.minimum_range_ring.visible:
			failures.append("selected Bulwarks should show their minimum attack dead zone")

	var main = MainScript.new()
	root.add_child(main)
	await process_frame
	main._load_skirmish_match("relay_crossroads", {
		"mode": "skirmish",
		"scenario_id": "network_hold",
		"ai_difficulty": "standard",
		"ai_intent": "secure_then_assault",
	})
	main._hide_objective_briefing()
	main._on_simulation_event("LauncherThreatWarning", {
		"tick": 5,
		"message": "Bulwark launched a missile at Ranger — spread out, flank, or break its range.",
	})
	if main.find_child("CombatAlertPanel", true, false) != null:
		failures.append("HUD should not create a duplicate top-right combat alert panel")
	if main.event_log_label.text.find("spread out") < 0:
		failures.append("event log should record launcher counterplay guidance")
	main._on_simulation_event("UnitDamaged", {
		"tick": 8,
		"target_id": "player_ranger",
		"team": "player",
		"target_team": "player",
		"target_display_name": "Ranger",
		"attacker_team": "enemy",
		"attacker_display_name": "Bulwark",
		"damage": 24.0,
		"health": 40.0,
		"max_health": 100.0,
		"is_splash": true,
	})
	if main.event_log_label.text.find("Bulwark") < 0 or main.event_log_label.text.find("UNDER FIRE") < 0 or main.event_log_label.text.find("RETREAT / REPAIR") < 0:
		failures.append("event log should identify incoming damage and the response")
	if main._target_detail({"kind": "bulwark", "team": "enemy", "display_name": "Bulwark", "health": 100.0, "max_health": 210.0, "minimum_attack_range": 8.0}).find("COUNTERPLAY") < 0:
		failures.append("inspected launcher stats should include counterplay guidance")

	if failures.is_empty():
		print("COMBAT_COUNTERPLAY_FEEDBACK_PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("COMBAT_COUNTERPLAY_FEEDBACK_FAIL")
		quit(1)


func _find_unit(simulation, kind: String, team: String) -> String:
	for entity_id in simulation.units:
		var unit: Dictionary = simulation.units[entity_id]
		if str(unit.get("kind", "")) == kind and str(unit.get("team", "")) == team:
			return str(entity_id)
	return ""


func _has_event(simulation, event_type: String) -> bool:
	return not _latest_event(simulation, event_type).is_empty()


func _latest_event(simulation, event_type: String) -> Dictionary:
	for index in range(simulation.event_history.size() - 1, -1, -1):
		var event: Dictionary = simulation.event_history[index]
		if str(event.get("event_type", "")) == event_type:
			return event
	return {}
