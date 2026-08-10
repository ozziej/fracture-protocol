extends SceneTree

const SimulationScript = preload("res://src/rts_simulation.gd")
const UnitViewScript = preload("res://src/rts_unit_view.gd")
const BuildingViewScript = preload("res://src/rts_building_view.gd")


func _initialize() -> void:
	await process_frame
	var failures: Array[String] = []

	var authored_sim = SimulationScript.new()
	root.add_child(authored_sim)
	authored_sim.start_match("relay_crossroads")
	if authored_sim.get_level_id() != "relay_divide":
		failures.append("the skirmish should load its authored relay_divide level")
	if authored_sim.get_level_bounds() != Vector2(80.0, 55.0):
		failures.append("authored level bounds should be applied to the simulation")
	if authored_sim.get_level_terrain().get("roads", []).size() < 3 or authored_sim.get_level_terrain().get("obstacles", []).size() < 3:
		failures.append("authored level terrain should expose roads and obstacles")

	var move_sim = SimulationScript.new()
	root.add_child(move_sim)
	move_sim.start_match("relay_crossroads")
	var warden_id := _find_entity(move_sim.units, "warden", "player")
	var enemy_hq_id := _find_entity(move_sim.buildings, "command_hub", "enemy")
	if warden_id.is_empty() or enemy_hq_id.is_empty():
		failures.append("move-priority regression needs a Warden and enemy Command Hub")
	else:
		var enemy_hq_position: Vector3 = move_sim.buildings[enemy_hq_id]["position"]
		var start_position := enemy_hq_position + Vector3(-8.0, 0.0, 0.0)
		var destination := enemy_hq_position + Vector3(-12.0, 0.0, 0.0)
		move_sim.units[warden_id]["position"] = start_position
		move_sim.units[warden_id]["target_position"] = start_position
		move_sim.issue_command("attack", "player", {"entity_ids": [warden_id], "target_id": enemy_hq_id})
		_step(move_sim, 1)
		var health_after_attack: float = float(move_sim.buildings[enemy_hq_id]["health"])
		move_sim.units[warden_id]["cooldown"] = 0.0
		move_sim.issue_command("move", "player", {"entity_ids": [warden_id], "position": destination})
		_step(move_sim, 2)
		var moved_unit: Dictionary = move_sim.units[warden_id]
		if str(moved_unit["order"]) != "move":
			failures.append("an explicit Move order should remain the unit's primary objective")
		if float(moved_unit["position"].x) >= start_position.x:
			failures.append("a Move order should advance away from the previous attack target")
		if float(moved_unit["position"].distance_to(destination)) >= start_position.distance_to(destination):
			failures.append("a Move order should reduce distance to its destination")
		if float(move_sim.buildings[enemy_hq_id]["health"]) >= health_after_attack:
			failures.append("a moving unit should still fire when its previous target remains in range")

	var collector_data := {
		"id": "collector_view",
		"team": "player",
		"kind": "collector",
		"position": Vector3.ZERO,
		"target_position": Vector3(5.0, 0.0, 0.0),
		"order": "move",
		"health": 150.0,
		"max_health": 150.0,
		"display_name": "Collector",
		"supply_state": "connected",
		"collector_state": "loading",
		"collector_source_name": "Northern Energy Field",
		"collector_destination_name": "Resource Processor",
		"collector_cargo": 30.0,
		"collector_capacity": 75.0,
	}
	var collector_view = UnitViewScript.new()
	root.add_child(collector_view)
	collector_view.setup(collector_data)
	var moving_collector_data: Dictionary = collector_data.duplicate(true)
	moving_collector_data["position"] = Vector3(5.0, 0.0, 0.0)
	collector_view.sync(moving_collector_data, true, 0.016)
	if collector_view.global_position.x <= 0.0 or collector_view.global_position.x >= 5.0:
		failures.append("unit presentation should interpolate between fixed simulation positions")
	if collector_view.cargo_front == null or collector_view.cargo_back == null:
		failures.append("Collector should expose a dedicated cargo progress bar")
	else:
		if collector_view.cargo_front.scale.x <= 0.02 or collector_view.cargo_front.scale.x >= 0.99:
			failures.append("Collector cargo progress should show a partial load")
		var health_material: StandardMaterial3D = collector_view.health_front.material_override as StandardMaterial3D
		var cargo_material: StandardMaterial3D = collector_view.cargo_front.material_override as StandardMaterial3D
		if health_material.albedo_color == cargo_material.albedo_color:
			failures.append("Collector cargo progress should use a distinct colour from health")
	var unit_health_box: BoxMesh = collector_view.health_front.mesh as BoxMesh
	var unit_health_back_box: BoxMesh = collector_view.health_back.mesh as BoxMesh
	var unit_health_right: float = collector_view.health_front.position.x + unit_health_box.size.x * collector_view.health_front.scale.x * 0.5
	var unit_health_back_right: float = collector_view.health_back.position.x + unit_health_back_box.size.x * 0.5
	if abs(unit_health_right - unit_health_back_right) > 0.01:
		failures.append("a full-health unit bar should reach the end of its background")

	var building_data := {
		"id": "building_view",
		"team": "player",
		"kind": "relay",
		"position": Vector3.ZERO,
		"construction_progress": 0.2,
		"health": 300.0,
		"max_health": 300.0,
		"complete": false,
		"display_name": "Forward Relay",
		"research_id": "",
		"research_remaining": 0.0,
		"research_total": 0.0,
	}
	var building_view = BuildingViewScript.new()
	root.add_child(building_view)
	building_view.setup(building_data)
	var body_box: BoxMesh = building_view.body_mesh.mesh as BoxMesh
	var cap_box: BoxMesh = building_view.cap_mesh.mesh as BoxMesh
	var body_height: float = body_box.size.y * building_view.body_mesh.scale.y
	var body_bottom: float = building_view.body_mesh.position.y - body_height * 0.5
	var body_top: float = building_view.body_mesh.position.y + body_height * 0.5
	var cap_bottom: float = building_view.cap_mesh.position.y - cap_box.size.y * building_view.cap_mesh.scale.y * 0.5
	if abs(body_bottom) > 0.05:
		failures.append("constructing buildings should stay anchored to the ground")
	if cap_bottom < body_top - 0.05:
		failures.append("construction cap should remain on the current building top")
	var completed_data: Dictionary = building_data.duplicate(true)
	completed_data["construction_progress"] = 1.0
	completed_data["complete"] = true
	building_view.sync(completed_data, false)
	if not building_view.antenna_mesh.visible or abs(building_view.body_mesh.position.y - body_box.size.y * 0.5) > 0.05:
		failures.append("completed buildings should restore their full grounded height")
	var building_health_box: BoxMesh = building_view.health_front.mesh as BoxMesh
	var building_health_back_box: BoxMesh = building_view.health_back.mesh as BoxMesh
	var building_health_right: float = building_view.health_front.position.x + building_health_box.size.x * building_view.health_front.scale.x * 0.5
	var building_health_back_right: float = building_view.health_back.position.x + building_health_back_box.size.x * 0.5
	if abs(building_health_right - building_health_back_right) > 0.01:
		failures.append("a full-health building bar should reach the end of its background")

	var rally_data: Dictionary = building_data.duplicate(true)
	rally_data["kind"] = "assembly_bay"
	rally_data["complete"] = true
	rally_data["construction_progress"] = 1.0
	rally_data["rally_enabled"] = true
	rally_data["rally_position"] = Vector3(4.0, 0.0, 0.0)
	var rally_view = BuildingViewScript.new()
	root.add_child(rally_view)
	rally_view.setup(rally_data)
	rally_view.sync(rally_data, true)
	if rally_view.rally_marker == null or not rally_view.rally_marker.visible or abs(rally_view.rally_marker.position.x - 4.0) > 0.05:
		failures.append("a selected Assembly Bay should show its user-set rally marker")

	var production_sim = SimulationScript.new()
	root.add_child(production_sim)
	production_sim.start_match("relay_crossroads")
	var production_assembly_id := _find_entity(production_sim.buildings, "assembly_bay", "player")
	var production_building: Dictionary = production_sim.buildings[production_assembly_id]
	var rally_position: Vector3 = production_building["position"] + Vector3(10.0, 0.0, -1.0)
	production_sim.issue_command("set_rally_point", "player", {"building_id": production_assembly_id, "position": rally_position})
	_step(production_sim, 1)
	if production_sim.buildings[production_assembly_id]["rally_position"].distance_to(rally_position) > 0.05:
		failures.append("a rally command should update the Assembly Bay destination")
	var units_before_production: int = production_sim.units.size()
	production_sim.issue_command("produce", "player", {"building_id": production_assembly_id, "unit_type": "ranger"})
	_step(production_sim, 45)
	var produced_ranger_id := _find_entity(production_sim.units, "ranger", "player")
	if production_sim.units.size() <= units_before_production or produced_ranger_id.is_empty():
		failures.append("production should complete a Ranger in the paced window")
	else:
		if production_sim.units[produced_ranger_id]["position"].distance_to(production_building["position"]) < 3.0:
			failures.append("a completed unit should exit the Assembly Bay before rallying")
		if not _has_event(production_sim, "ProductionCompleted", "unit_type", "ranger"):
			failures.append("unit exit should emit a ProductionCompleted event")

	var queue_sim = SimulationScript.new()
	root.add_child(queue_sim)
	queue_sim.start_match("relay_crossroads")
	var queue_assembly_id := _find_entity(queue_sim.buildings, "assembly_bay", "player")
	for _index in range(6):
		queue_sim.issue_command("produce", "player", {"building_id": queue_assembly_id, "unit_type": "ranger"})
	_step(queue_sim, 1)
	var queue_items: Array = queue_sim.buildings[queue_assembly_id]["queue"]
	if queue_items.size() != 5:
		failures.append("an Assembly Bay should never accept more than five queued units")
	if not _has_reason(queue_sim, "queue full"):
		failures.append("a sixth production order should explain that the queue is full")

	var unit_cap_sim = SimulationScript.new()
	root.add_child(unit_cap_sim)
	unit_cap_sim.start_match("relay_crossroads")
	for _index in range(12):
		unit_cap_sim._add_unit("player", "bulwark", Vector3.ZERO)
	var cap_assembly_id := _find_entity(unit_cap_sim.buildings, "assembly_bay", "player")
	unit_cap_sim.issue_command("produce", "player", {"building_id": cap_assembly_id, "unit_type": "ranger"})
	_step(unit_cap_sim, 1)
	if not unit_cap_sim.buildings[cap_assembly_id]["queue"].is_empty() or not _has_reason(unit_cap_sim, "capacity"):
		failures.append("the authored total force cap should reject production")

	var building_cap_sim = SimulationScript.new()
	root.add_child(building_cap_sim)
	building_cap_sim.start_match("relay_crossroads")
	for _index in range(4):
		building_cap_sim._add_building("player", "relay", Vector3.ZERO)
	var buildings_before_cap: int = building_cap_sim.buildings.size()
	building_cap_sim.issue_command("build", "player", {"building_type": "relay", "position": Vector3(-18.0, 0.0, 12.0)})
	_step(building_cap_sim, 1)
	if building_cap_sim.buildings.size() != buildings_before_cap or not _has_reason(building_cap_sim, "limit reached"):
		failures.append("the authored per-kind building cap should reject another Relay")

	if failures.is_empty():
		print("NEXT_SLICE_SMOKE_PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("NEXT_SLICE_SMOKE_FAIL")
		quit(1)


func _step(simulation, count: int) -> void:
	for _index in range(count):
		simulation._ai_timer = 0.0
		simulation.step_fixed()


func _has_event(simulation, event_type: String, field_name: String, expected_value: String) -> bool:
	for event in simulation.event_history:
		if str(event.get("event_type", "")) == event_type and str(event.get(field_name, "")) == expected_value:
			return true
	return false


func _has_reason(simulation, text_value: String) -> bool:
	for event in simulation.event_history:
		if str(event.get("event_type", "")) == "OrderRejected" and str(event.get("reason", "")).to_lower().find(text_value.to_lower()) >= 0:
			return true
	return false


func _find_entity(entities: Dictionary, kind: String, team: String) -> String:
	for entity_id in entities:
		if entities[entity_id]["kind"] == kind and entities[entity_id]["team"] == team:
			return entity_id
	return ""
