extends SceneTree

const SimulationScript = preload("res://src/rts_simulation.gd")


func _initialize() -> void:
	var failures: Array[String] = []

	var balance_sim = SimulationScript.new()
	root.add_child(balance_sim)
	balance_sim.start_match("relay_crossroads")
	var ranger = balance_sim.unit_definitions["ranger"]
	var raider = balance_sim.unit_definitions["raider"]
	if float(ranger.max_health) != float(raider.max_health):
		failures.append("Ranger and Raider should have equal health in the first-pass matchup")
	if float(ranger.armour) != float(raider.armour):
		failures.append("Ranger and Raider should have equal armour in the first-pass matchup")
	if float(ranger.attack_damage) != float(raider.attack_damage) or float(ranger.attack_cooldown) != float(raider.attack_cooldown) or float(ranger.attack_range) != float(raider.attack_range):
		failures.append("Ranger and Raider should have equal direct-fire capability in the first-pass matchup")

	var duel_sim = SimulationScript.new()
	root.add_child(duel_sim)
	duel_sim.start_match("relay_crossroads")
	var duel_ranger_id := duel_sim._add_unit("player", "ranger", Vector3(-4.0, 0.0, 0.0))
	var duel_raider_id := duel_sim._add_unit("enemy", "raider", Vector3(4.0, 0.0, 0.0))
	duel_sim.issue_command("attack", "player", {"entity_ids": [duel_ranger_id], "target_id": duel_raider_id})
	duel_sim.issue_command("attack", "enemy", {"entity_ids": [duel_raider_id], "target_id": duel_ranger_id})
	_step(duel_sim, 8)
	if not duel_sim.units.has(duel_ranger_id) or not duel_sim.units.has(duel_raider_id):
		failures.append("an equal Ranger/Raider duel should not produce an immediate one-sided destruction")
	else:
		var ranger_health := float(duel_sim.units[duel_ranger_id]["health"])
		var raider_health := float(duel_sim.units[duel_raider_id]["health"])
		if ranger_health >= float(ranger.max_health) or raider_health >= float(raider.max_health):
			failures.append("the Ranger/Raider duel should apply damage to both units")
		if abs(ranger_health - raider_health) > 0.01:
			failures.append("equal Ranger/Raider attacks should produce equal first-pass damage")

	var mass_sim = SimulationScript.new()
	root.add_child(mass_sim)
	mass_sim.start_match("relay_crossroads")
	var mass_ranger_ids: Array = []
	for index in range(12):
		mass_ranger_ids.append(mass_sim._add_unit("player", "ranger", Vector3(-3.0, 0.0, 0.0)))
	var mass_raider_a := mass_sim._add_unit("enemy", "raider", Vector3(3.0, 0.0, 0.0))
	var mass_raider_b := mass_sim._add_unit("enemy", "raider", Vector3(3.0, 0.0, 1.0))
	mass_sim.issue_command("attack", "player", {"entity_ids": mass_ranger_ids, "target_id": mass_raider_a})
	mass_sim.issue_command("attack", "enemy", {"entity_ids": [mass_raider_a, mass_raider_b], "target_id": mass_ranger_ids[0]})
	_step(mass_sim, 30)
	if mass_sim.units.has(mass_raider_a) or mass_sim.units.has(mass_raider_b):
		failures.append("twelve Rangers should be able to stop two Raiders at equal first-pass combat values")


	var opening_sim = SimulationScript.new()
	root.add_child(opening_sim)
	opening_sim.start_match("relay_divide")
	if not _find_entity(opening_sim.units, "bulwark", "enemy").is_empty():
		failures.append("Level 1 should not begin with an enemy Bulwark before the player can research it")
	var minimum_attack_group_size: int = int(opening_sim.level_definition.get("ai", {}).get("minimum_attack_group_size", 0))
	if minimum_attack_group_size < 3:
		failures.append("authored AI openings should not launch a two-unit attack group")

	var queue_sim = SimulationScript.new()
	root.add_child(queue_sim)
	queue_sim.start_match("relay_crossroads")
	var queue_unit_id := _find_entity(queue_sim.units, "ranger", "player")
	if queue_unit_id.is_empty():
		failures.append("queued waypoint test needs a player Ranger")
	else:
		var queue_start: Vector3 = queue_sim.units[queue_unit_id]["position"]
		var first_destination := queue_start + Vector3(18.0, 0.0, -6.0)
		var second_destination := first_destination + Vector3(12.0, 0.0, 0.0)
		queue_sim.issue_command("move", "player", {"entity_ids": [queue_unit_id], "position": first_destination})
		_step(queue_sim, 1)
		queue_sim.issue_command("queue_move", "player", {"entity_ids": [queue_unit_id], "position": second_destination})
		_step(queue_sim, 1)
		if queue_sim.units[queue_unit_id].get("command_waypoints", []).size() != 1:
			failures.append("Shift-queued movement should reserve one waypoint behind the active route")
		if not _has_order_event(queue_sim, "queue_move", "player"):
			failures.append("queued movement should emit a readable order event")
		_step(queue_sim, 100)
		if queue_sim.units[queue_unit_id]["position"].distance_to(second_destination) > 0.8 or queue_sim.units[queue_unit_id]["order"] != "idle":
			failures.append("queued movement should complete the active and queued destinations")

	var override_sim = SimulationScript.new()
	root.add_child(override_sim)
	override_sim.start_match("relay_crossroads")
	var override_unit_id := _find_entity(override_sim.units, "ranger", "player")
	if override_unit_id.is_empty():
		failures.append("queue override test needs a player Ranger")
	else:
		var override_start: Vector3 = override_sim.units[override_unit_id]["position"]
		override_sim.issue_command("move", "player", {"entity_ids": [override_unit_id], "position": override_start + Vector3(18.0, 0.0, -6.0)})
		_step(override_sim, 1)
		override_sim.issue_command("queue_move", "player", {"entity_ids": [override_unit_id], "position": override_start + Vector3(30.0, 0.0, -6.0)})
		_step(override_sim, 1)
		override_sim.issue_command("move", "player", {"entity_ids": [override_unit_id], "position": override_start + Vector3(6.0, 0.0, 6.0)})
		_step(override_sim, 1)
		if not override_sim.units[override_unit_id].get("command_waypoints", []).is_empty():
			failures.append("a direct Move order should cancel stale queued waypoints")

	var patrol_sim = SimulationScript.new()
	root.add_child(patrol_sim)
	patrol_sim.start_match("relay_crossroads")
	var patrol_unit_id := _find_entity(patrol_sim.units, "ranger", "player")
	if patrol_unit_id.is_empty():
		failures.append("patrol test needs a player Ranger")
	else:
		var patrol_start: Vector3 = patrol_sim.units[patrol_unit_id]["position"]
		var patrol_destination := patrol_start + Vector3(18.0, 0.0, -6.0)
		patrol_sim.issue_command("patrol", "player", {"entity_ids": [patrol_unit_id], "position": patrol_destination})
		_step(patrol_sim, 55)
		var patrol_unit: Dictionary = patrol_sim.units[patrol_unit_id]
		if patrol_unit["order"] != "patrol" or patrol_unit.get("patrol_points", []).size() != 2:
			failures.append("patrol should remain active after reaching its first destination")
		var position_at_turn: Vector3 = patrol_unit["position"]
		_step(patrol_sim, 55)
		patrol_unit = patrol_sim.units[patrol_unit_id]
		if patrol_unit["order"] != "patrol" or patrol_unit["position"].distance_to(position_at_turn) < 0.5:
			failures.append("patrol should return along its route instead of stopping")

	if failures.is_empty():
		print("OPENING_ORDERS_PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("OPENING_ORDERS_FAIL")
		quit(1)


func _step(simulation, count: int) -> void:
	for _index in range(count):
		simulation._ai_timer = 0.0
		simulation.step_fixed()


func _find_entity(entities: Dictionary, kind: String, team: String) -> String:
	for entity_id in entities:
		if entities[entity_id]["kind"] == kind and entities[entity_id]["team"] == team:
			return entity_id
	return ""


func _has_order_event(simulation, order: String, team: String) -> bool:
	for event in simulation.event_history:
		if event.get("event_type", "") == "OrderIssued" and event.get("order", "") == order and event.get("team", "") == team:
			return true
	return false
