extends SceneTree

const SimulationScript = preload("res://src/rts_simulation.gd")
const UnitViewScript = preload("res://src/rts_unit_view.gd")
const BuildingViewScript = preload("res://src/rts_building_view.gd")


func _initialize() -> void:
	await process_frame
	var failures: Array[String] = []

	var move_sim = SimulationScript.new()
	root.add_child(move_sim)
	move_sim.start_match()
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


func _find_entity(entities: Dictionary, kind: String, team: String) -> String:
	for entity_id in entities:
		if entities[entity_id]["kind"] == kind and entities[entity_id]["team"] == team:
			return entity_id
	return ""
