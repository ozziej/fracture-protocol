extends SceneTree

const SimulationScript = preload("res://src/rts_simulation.gd")
const CampaignProgressScript = preload("res://src/campaign_progress.gd")
const MainScript = preload("res://src/main.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	var simulation = SimulationScript.new()
	root.add_child(simulation)
	simulation.start_match("relay_divide")
	if _count_buildings(simulation, "player") != 1 or _find_building(simulation, "player", "command_hub").is_empty():
		failures.append("Level 1 should begin with only the Command Hub")
	if simulation.get_level_bounds() != Vector2(115.0, 75.0):
		failures.append("Relay Divide should use the expanded opening map")
	var opening_sim = SimulationScript.new()
	root.add_child(opening_sim)
	opening_sim.start_match("relay_divide")
	_step(opening_sim, 1799)
	if _has_enemy_attack_order(opening_sim):
		failures.append("The enemy must not launch its HQ attack before the opening staging window")

	var hub_id := _find_building(simulation, "player", "command_hub")
	simulation.issue_command("build", "player", {"building_type": "assembly_bay", "position": Vector3(-82.0, 0.0, 24.0), "source_building_id": hub_id})
	_step(simulation, 1)
	if not _has_rejection(simulation, "Build Resource Processor"):
		failures.append("Assembly Bay should require the Resource Processor")
	simulation.issue_command("build", "player", {"building_type": "refinery", "position": Vector3(-75.0, 0.0, 32.0), "source_building_id": hub_id})
	_step(simulation, 100)
	var refinery_id := _find_building(simulation, "player", "refinery")
	if refinery_id.is_empty() or not simulation.buildings[refinery_id]["complete"]:
		failures.append("Command Hub should construct a completed Resource Processor")
	else:
		simulation.issue_command("produce", "player", {"building_id": refinery_id, "unit_type": "collector"})
		_step(simulation, 1)
		simulation.issue_command("produce", "player", {"building_id": refinery_id, "unit_type": "collector"})
		_step(simulation, 1)
		if not _has_rejection(simulation, "Storage Silo"):
			failures.append("A Processor should allow only one active or queued Collector without a Silo")
	simulation.issue_command("build", "player", {"building_type": "assembly_bay", "position": Vector3(-82.0, 0.0, 24.0), "source_building_id": hub_id})
	_step(simulation, 100)
	var assembly_id := _find_building(simulation, "player", "assembly_bay")
	if assembly_id.is_empty():
		failures.append("Assembly Bay should become available after the Processor")
	else:
		simulation.issue_command("produce", "player", {"building_id": assembly_id, "unit_type": "warden"})
		_step(simulation, 1)
		if not _has_rejection(simulation, "not available in this level"):
			failures.append("Warden must remain Level 2 locked")

	var projectile_sim = SimulationScript.new()
	root.add_child(projectile_sim)
	projectile_sim.start_match("relay_crossroads")
	var bulwark_id := projectile_sim._add_unit("player", "bulwark", Vector3(0.0, 0.0, 0.0))
	var enemy_one := projectile_sim._add_unit("enemy", "raider", Vector3(8.0, 0.0, 0.0))
	var friendly_id := projectile_sim._add_unit("player", "ranger", Vector3(8.5, 0.0, 0.0))
	var enemy_health: float = projectile_sim.units[enemy_one]["health"]
	var friendly_health: float = projectile_sim.units[friendly_id]["health"]
	projectile_sim.issue_command("attack", "player", {"entity_ids": [bulwark_id], "target_id": enemy_one})
	_step(projectile_sim, 1)
	projectile_sim.units[enemy_one]["cooldown"] = 999.0
	if not _has_event(projectile_sim, "ProjectileLaunched") or projectile_sim.units[enemy_one]["health"] != enemy_health:
		failures.append("Bulwark should launch a delayed missile rather than apply instant damage")
	_step(projectile_sim, 30)
	if projectile_sim.units.has(enemy_one) and projectile_sim.units[enemy_one]["health"] >= enemy_health:
		failures.append("Bulwark missile should damage its target on impact")
	if projectile_sim.units.has(friendly_id) and projectile_sim.units[friendly_id]["health"] != friendly_health:
		failures.append("Bulwark splash must not damage friendly units")
	var cancel_sim = SimulationScript.new()
	root.add_child(cancel_sim)
	cancel_sim.start_match("relay_crossroads")
	var cancel_assembly_id := _find_building(cancel_sim, "player", "assembly_bay")
	var warden_cost: float = cancel_sim.unit_definitions["warden"].cost
	var credits_after_start: float = cancel_sim.player_credits
	cancel_sim.issue_command("produce", "player", {"building_id": cancel_assembly_id, "unit_type": "warden"})
	_step(cancel_sim, 1)
	if cancel_sim.buildings[cancel_assembly_id]["queue"].size() != 1:
		failures.append("A Level 2 Warden should enter the Assembly Bay queue")
	var credits_after_queue: float = cancel_sim.player_credits
	cancel_sim.issue_command("cancel_production", "player", {"building_id": cancel_assembly_id, "queue_index": 0})
	_step(cancel_sim, 1)
	if not cancel_sim.buildings[cancel_assembly_id]["queue"].is_empty():
		failures.append("Cancelling a queued unit should remove it from the queue")
	if abs(cancel_sim.player_credits - credits_after_queue - warden_cost) > 0.1:
		failures.append("Cancelling a queued unit should refund its full cost")
	if not _has_event(cancel_sim, "ProductionCancelled"):
		failures.append("Cancelling production should emit a visible cancellation event")
	if credits_after_start <= credits_after_queue:
		failures.append("Queueing a Warden should reserve its cost before cancellation")

	var game = MainScript.new()
	root.add_child(game)
	await process_frame
	var game_hub_id := _find_building(game.simulation, "player", "command_hub")
	game.selected_ids = [game_hub_id]
	game._update_hud()
	if game.queue_button.visible or game.heavy_queue_button.visible:
		failures.append("Level 1 should hide Assembly and Tech Centre until their prerequisites are complete")
	var game_refinery_position := Vector3(-75.0, 0.0, 32.0)
	game.simulation.issue_command("build", "player", {"building_type": "refinery", "position": game_refinery_position, "source_building_id": game_hub_id})
	_step(game.simulation, 100)
	game.selected_ids = [game_hub_id]
	game._update_hud()
	if not game.queue_button.visible or game.queue_button.disabled:
		failures.append("Completing a Processor should reveal the Assembly card")
	if game.heavy_queue_button.visible:
		failures.append("Tech Centre should remain hidden until an Assembly Bay is complete")
	game.queue_button.pressed.emit()
	if game.build_mode != "assembly_bay" or game.build_ghost == null:
		failures.append("Clicking the visible Assembly card should show its placement preview")
	game._cancel_build_mode()
	game.simulation.issue_command("build", "player", {"building_type": "assembly_bay", "position": Vector3(-82.0, 0.0, 24.0), "source_building_id": game_hub_id})
	_step(game.simulation, 100)
	var game_assembly_id := _find_building(game.simulation, "player", "assembly_bay")
	game.selected_ids = [game_hub_id]
	game._update_hud()
	if not game.heavy_queue_button.visible or game.heavy_queue_button.disabled:
		failures.append("Completing an Assembly Bay should reveal the Tech Centre card")
	game.heavy_queue_button.pressed.emit()
	if game.build_mode != "tech_centre" or game.build_ghost == null:
		failures.append("Clicking the visible Tech Centre card should show its placement preview")
	game._cancel_build_mode()
	game.selected_ids = [game_assembly_id]
	game._update_hud()
	if game.heavy_queue_button.visible:
		failures.append("Warden should be hidden from the Level 1 Assembly Bay")
	if not game.queue_button.visible or not game.queue_button.disabled or game.queue_button.tooltip_text.find("Requires Advanced Targeting") < 0:
		failures.append("Level 1 Bulwark should be visible but disabled until Advanced Targeting")
	var credits_before_ui_queue: float = game.simulation.player_credits
	game.simulation.issue_command("produce", "player", {"building_id": game_assembly_id, "unit_type": "ranger"})
	_step(game.simulation, 1)
	game._update_hud()
	if not game.queue_panel.visible or game.queue_buttons.is_empty() or not game.queue_buttons[0].visible:
		failures.append("A queued unit should appear in the visible production queue panel")
	else:
		game.queue_buttons[0].pressed.emit()
		_step(game.simulation, 1)
		if not game.simulation.buildings[game_assembly_id]["queue"].is_empty():
			failures.append("The queue panel cancel control should remove its queued item")
		if abs(game.simulation.player_credits - credits_before_ui_queue) > 0.1:
			failures.append("The queue panel cancel control should refund the queued item")
	game.queue_free()


	var progress_path := "user://progression_combat_test.json"
	if FileAccess.file_exists(progress_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(progress_path))
	var progress = CampaignProgressScript.new(progress_path)
	if not progress.is_unlocked("relay_divide") or progress.is_unlocked("relay_crossroads"):
		failures.append("Campaign progress should start with only Level 1 unlocked")
	progress.mark_complete("relay_divide")
	var restored = CampaignProgressScript.new(progress_path)
	if not restored.is_unlocked("relay_crossroads"):
		failures.append("Winning Level 1 should persist the Level 2 unlock")
	if FileAccess.file_exists(progress_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(progress_path))

	if failures.is_empty():
		print("PROGRESSION_COMBAT_PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("PROGRESSION_COMBAT_FAIL")
		quit(1)


func _step(simulation, count: int) -> void:
	for index in range(count):
		simulation._ai_timer = 999.0
		simulation.step_fixed()


func _find_building(simulation, team: String, kind: String) -> String:
	for building_id in simulation.buildings:
		var building: Dictionary = simulation.buildings[building_id]
		if building["team"] == team and building["kind"] == kind:
			return building_id
	return ""


func _count_buildings(simulation, team: String) -> int:
	var total := 0
	for building_id in simulation.buildings:
		if simulation.buildings[building_id]["team"] == team:
			total += 1
	return total


func _has_rejection(simulation, snippet: String) -> bool:
	for event in simulation.event_history:
		if str(event.get("event_type", "")) == "OrderRejected" and str(event.get("reason", "")).find(snippet) >= 0:
			return true
	return false


func _has_enemy_attack_order(simulation) -> bool:
	for event in simulation.event_history:
		if str(event.get("event_type", "")) == "OrderIssued" and str(event.get("team", "")) == "enemy" and str(event.get("order", "")) == "attack":
			return true
	return false


func _has_event(simulation, event_type: String) -> bool:
	for event in simulation.event_history:
		if str(event.get("event_type", "")) == event_type:
			return true
	return false
