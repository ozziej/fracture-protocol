extends SceneTree

const SimulationScript = preload("res://src/rts_simulation.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	var pursuit_sim = SimulationScript.new()
	root.add_child(pursuit_sim)
	pursuit_sim.start_match("relay_crossroads")
	var pursuit_unit_id := _find_entity(pursuit_sim.units, "ranger", "player")
	var pursuit_target_id := _find_entity(pursuit_sim.units, "raider", "enemy")
	if pursuit_unit_id.is_empty() or pursuit_target_id.is_empty():
		failures.append("pursuit regression needs a player Ranger and enemy Raider")
	else:
		var pursuit_unit: Dictionary = pursuit_sim.units[pursuit_unit_id]
		var pursuit_target: Dictionary = pursuit_sim.units[pursuit_target_id]
		pursuit_unit["position"] = Vector3(-20.0, 0.0, 0.0)
		pursuit_unit["target_position"] = pursuit_unit["position"]
		pursuit_unit["order"] = "idle"
		pursuit_target["position"] = pursuit_unit["position"] + Vector3(3.0, 0.0, 0.0)
		pursuit_target["target_position"] = pursuit_target["position"]
		var target_origin: Vector3 = pursuit_target["position"]
		if not pursuit_sim._set_opportunistic_attack_target(pursuit_unit, pursuit_target_id):
			failures.append("player units should be able to start opportunistic pursuit")
		pursuit_unit["position"] += Vector3(4.0, 0.0, 0.0)
		pursuit_target["position"] = target_origin + Vector3(9.0, 0.0, 0.0)
		pursuit_target["target_position"] = pursuit_target["position"]
		_step_units(pursuit_sim, 1)
		if str(pursuit_unit.get("order", "")) != "auto_return":
			failures.append("a target moving beyond the contact leash should start a return order")
		var cooldown_until: int = int(pursuit_unit.get("auto_pursuit_cooldown_until_tick", 0))
		if cooldown_until < pursuit_sim.current_tick + 50:
			failures.append("returning from pursuit should enforce a five-second cooldown")
		var second_contact_id := pursuit_sim._add_unit("enemy", "raider", pursuit_unit["position"] + Vector3(2.0, 0.0, 0.0))
		for _index in range(30):
			if str(pursuit_unit.get("order", "")) == "auto_hold":
				break
			_step_units(pursuit_sim, 1)
		if str(pursuit_unit.get("order", "")) != "auto_hold":
			failures.append("a returned unit should hold position during its pursuit cooldown")
		_step_units(pursuit_sim, 10)
		if not str(pursuit_unit.get("attack_target", "")).is_empty() or str(pursuit_unit.get("order", "")) != "auto_hold":
			failures.append("a returned unit should not acquire a different contact during the five-second hold")
		pursuit_sim.units[second_contact_id]["position"] = pursuit_unit["position"] + Vector3(2.0, 0.0, 0.0)
		pursuit_sim.units[second_contact_id]["target_position"] = pursuit_sim.units[second_contact_id]["position"]

	var death_sim = SimulationScript.new()
	root.add_child(death_sim)
	death_sim.start_match("relay_crossroads")
	var death_unit_id := _find_entity(death_sim.units, "ranger", "player")
	var death_target_id := _find_entity(death_sim.units, "raider", "enemy")
	if death_unit_id.is_empty() or death_target_id.is_empty():
		failures.append("death pursuit regression needs a player Ranger and enemy Raider")
	else:
		var death_unit: Dictionary = death_sim.units[death_unit_id]
		var death_target: Dictionary = death_sim.units[death_target_id]
		death_unit["position"] = Vector3(-30.0, 0.0, 0.0)
		death_unit["target_position"] = death_unit["position"]
		death_target["position"] = death_unit["position"] + Vector3(3.0, 0.0, 0.0)
		death_target["target_position"] = death_target["position"]
		death_sim._set_opportunistic_attack_target(death_unit, death_target_id)
		death_unit["position"] += Vector3(4.0, 0.0, 0.0)
		death_sim.units.erase(death_target_id)
		_step_units(death_sim, 1)
		if str(death_unit.get("order", "")) != "auto_return":
			failures.append("a dead opportunistic target should return the player unit to its original position")

	var guard_sim = SimulationScript.new()
	root.add_child(guard_sim)
	guard_sim.start_match("relay_crossroads")
	var guard_unit_id := _find_entity(guard_sim.units, "ranger", "player")
	var guard_target_id := _find_entity(guard_sim.units, "raider", "enemy")
	if guard_unit_id.is_empty() or guard_target_id.is_empty():
		failures.append("guard regression needs a player Ranger and enemy Raider")
	else:
		var guard_unit: Dictionary = guard_sim.units[guard_unit_id]
		var guard_target: Dictionary = guard_sim.units[guard_target_id]
		guard_unit["position"] = Vector3(-20.0, 0.0, 0.0)
		guard_unit["target_position"] = guard_unit["position"]
		guard_target["position"] = guard_unit["position"] + Vector3(4.0, 0.0, 0.0)
		guard_target["target_position"] = guard_target["position"]
		guard_sim._apply_guard_command("player", {"entity_ids": [guard_unit_id]})
		_step_units(guard_sim, 1)
		guard_target["position"] = guard_unit["position"] + Vector3(14.0, 0.0, 0.0)
		guard_target["target_position"] = guard_target["position"]
		_step_units(guard_sim, 1)
		if str(guard_unit.get("order", "")) != "guard" or not str(guard_unit.get("attack_target", "")).is_empty():
			failures.append("Guard should drop contacts outside its guard radius without pursuing")
		if guard_unit["position"].distance_to(guard_unit["guard_position"]) > 9.1:
			failures.append("Guard should keep the unit near its assigned position")

	var repair_sim = SimulationScript.new()
	root.add_child(repair_sim)
	repair_sim.start_match("relay_crossroads")
	var repair_building_id := _find_entity(repair_sim.buildings, "command_hub", "player")
	var repair_unit_ids: Array = repair_sim.get_player_unit_ids()
	if repair_building_id.is_empty() or repair_unit_ids.is_empty():
		failures.append("repair regression needs a player Command Hub and unit")
	else:
		var repair_unit_id: String = str(repair_unit_ids[0])
		var repair_building_position: Vector3 = repair_sim.buildings[repair_building_id]["position"]
		var repair_unit: Dictionary = repair_sim.units[repair_unit_id]
		repair_unit["position"] = repair_building_position + Vector3(2.0, 0.0, 0.0)
		repair_unit["target_position"] = repair_unit["position"]
		repair_unit["health"] = 20.0
		repair_sim._apply_repair_command("player", {"entity_ids": [repair_unit_id]})
		if bool(repair_unit.get("repair_active", false)):
			failures.append("units must not be able to initiate their own repair")
		repair_sim._apply_repair_command("player", {"building_id": repair_building_id})
		_step_repairs(repair_sim, 1)
		if float(repair_unit["health"]) <= 20.0:
			failures.append("a repair building should repair nearby damaged units")
		if not _has_event(repair_sim, "OrderRejected", "order", "repair"):
			failures.append("unit-originated repair should emit a clear rejection")

	if failures.is_empty():
		print("UNIT_ORDERS_REPAIR_REGRESSION_PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("UNIT_ORDERS_REPAIR_REGRESSION_FAIL")
		quit(1)


func _step_units(simulation, count: int) -> void:
	for _index in range(count):
		simulation.current_tick += 1
		simulation._update_units()


func _step_repairs(simulation, count: int) -> void:
	for _index in range(count):
		simulation.current_tick += 1
		simulation._update_repairs()


func _find_entity(entities: Dictionary, kind: String, team: String) -> String:
	for entity_id in entities:
		if str(entities[entity_id].get("kind", "")) == kind and str(entities[entity_id].get("team", "")) == team:
			return str(entity_id)
	return ""


func _has_event(simulation, event_type: String, field_name: String, expected_value: String) -> bool:
	for event in simulation.event_history:
		if str(event.get("event_type", "")) == event_type and str(event.get(field_name, "")) == expected_value:
			return true
	return false
