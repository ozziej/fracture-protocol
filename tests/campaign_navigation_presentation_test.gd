extends SceneTree

const SimulationScript = preload("res://src/rts_simulation.gd")
const BuildingViewScript = preload("res://src/rts_building_view.gd")
const WorldBuilderScript = preload("res://src/presentation/rts_world_builder.gd")
const MinimapScript = preload("res://src/minimap.gd")


func _initialize() -> void:
	await process_frame
	var failures: Array[String] = []
	var simulation: Node = SimulationScript.new()
	root.add_child(simulation)
	simulation.start_match("silent_recovery")

	var initial_campaign: Dictionary = simulation.get_campaign_state()
	if initial_campaign.get("mission_item_ids", []).size() != 2:
		failures.append("Level 3 should expose both sealed cases to presentation state")
	if bool(initial_campaign.get("final_destination_revealed", false)):
		failures.append("Level 3 extraction should remain hidden before a case is collected")

	var warden_id := _find_authored(simulation.units, "silent_warden_1")
	var north_case_position: Vector3 = simulation.mission_items["recovery_case_north"]["position"]
	simulation.units[warden_id]["position"] = north_case_position
	simulation.step_fixed()
	var collected_campaign: Dictionary = simulation.get_campaign_state()
	if not bool(collected_campaign.get("final_destination_revealed", false)):
		failures.append("Collecting a sealed case should reveal the final destination")
	if Vector3(collected_campaign.get("final_destination_position", Vector3.INF)) != Vector3(-92.0, 0.0, 0.0):
		failures.append("Level 3 should expose the authored west extraction destination")

	var sensor_id := _find_authored(simulation.buildings, "silent_sensor_north")
	simulation.units[warden_id]["position"] = simulation.buildings[sensor_id]["position"]
	simulation.step_fixed()
	var breached_campaign: Dictionary = simulation.get_campaign_state()
	if not bool(breached_campaign.get("detected", false)) or str(breached_campaign.get("detection_source_kind", "")) != "sensor_mast":
		failures.append("Entering a Sensor Mast radius should produce an explicit sensor-grid breach")

	var sensor_view = BuildingViewScript.new()
	root.add_child(sensor_view)
	sensor_view.setup(simulation.buildings[sensor_id])
	if sensor_view.vision_zone == null or sensor_view.vision_zone_ring == null:
		failures.append("Sensor Mast presentation should create a filled vision zone and outline")
	else:
		if not sensor_view.vision_zone.visible or absf(sensor_view.vision_zone.scale.x - 30.0) > 0.01:
			failures.append("Sensor Mast vision zone should remain visible at its authored range")

	var navigation_sim: Node = SimulationScript.new()
	root.add_child(navigation_sim)
	navigation_sim.start_match("long_road")
	var carrier_id := _find_authored(navigation_sim.units, "long_road_command_carrier")
	var route_path: Array = navigation_sim._build_navigation_path(Vector3(-90.0, 0.0, 0.0), Vector3(0.0, 0.0, 0.0))
	if route_path.size() < 2 or absf(float(route_path[0].z)) < 50.0:
		failures.append("A direct Long Road order should be routed around the mountain wall through a pass")
	if navigation_sim._navigation_point_clear(Vector3(-35.0, 0.0, 0.0)):
		failures.append("The center of a mountain wall must remain impassable to units")
	if navigation_sim._navigation_point_clear(Vector3(35.0, 0.0, 0.0)):
		failures.append("Both mountain walls must remain impassable to units")
	navigation_sim.issue_command("move", "player", {"entity_ids": [carrier_id], "position": Vector3(0.0, 0.0, 0.0)})
	for _index in range(260):
		navigation_sim.step_fixed()
		if not _position_is_clear(navigation_sim, navigation_sim.units[carrier_id]["position"]):
			failures.append("A convoy unit should never enter an authored mountain obstacle")
			break

	var blocked_click_sim: Node = SimulationScript.new()
	root.add_child(blocked_click_sim)
	blocked_click_sim.start_match("long_road")
	var blocked_carrier_id := _find_authored(blocked_click_sim.units, "long_road_command_carrier")
	blocked_click_sim.issue_command("move", "player", {"entity_ids": [blocked_carrier_id], "position": Vector3(-35.0, 0.0, 0.0)})
	blocked_click_sim.step_fixed()
	var resolved_target: Vector3 = blocked_click_sim.units[blocked_carrier_id]["target_position"]
	if not blocked_click_sim._navigation_point_clear(resolved_target):
		failures.append("A click inside a mountain should resolve to a reachable edge position")
	for _index in range(300):
		blocked_click_sim.step_fixed()
	if str(blocked_click_sim.units[blocked_carrier_id].get("order", "")) != "idle" or blocked_click_sim.units[blocked_carrier_id]["position"].distance_to(resolved_target) > 0.25:
		failures.append("A unit ordered onto a solid object should stop at the resolved edge instead of shuffling indefinitely")
	var world_shell := Node3D.new()
	root.add_child(world_shell)
	WorldBuilderScript.build_world_shell(world_shell, navigation_sim)
	var north_route := world_shell.find_child("AuthoredRoute_north_pass", true, false)
	if north_route == null:
		failures.append("Mission routes should render as authored world corridors")
	elif north_route.find_child("KenneyAsset_terrain_road_straight", true, false) == null or north_route.find_child("KenneyAsset_terrain_road_corner", true, false) == null:
		failures.append("Mission routes should use the existing Kenney road GLB")
	elif north_route.find_child("KenneyAsset_terrain_road_split", true, false) == null:
		failures.append("Shared pass junctions should use the existing Kenney roadSplit GLB")
	if north_route != null:
		var straight_tiles: Array = []
		_collect_straight_tiles(north_route, straight_tiles)
		var horizontal_is_rotated := false
		var vertical_stays_source := false
		for tile in straight_tiles:
			var tile_position: Vector3 = tile["position"]
			var yaw: float = tile["yaw"]
			if absf(tile_position.z + 56.0) < 0.1 and absf(yaw - 90.0) < 0.1:
				horizontal_is_rotated = true
			if absf(tile_position.x + 60.0) < 0.1 and tile_position.z < -4.0 and absf(yaw) < 0.1:
				vertical_stays_source = true
		if not horizontal_is_rotated or not vertical_stays_source:
			failures.append("Straight road GLBs should run on local Z: horizontal tiles need a 90 degree rotation")
	var route_tiles: Array = []
	_collect_route_tiles(world_shell, route_tiles)
	var west_spur_positions: Array[float] = []
	var west_end_yaw := -1.0
	for tile in route_tiles:
		var tile_position: Vector3 = tile["position"]
		if absf(tile_position.z) < 0.1 and tile_position.x >= -90.1 and tile_position.x <= -59.9:
			west_spur_positions.append(tile_position.x)
		if str(tile["asset"]) == "terrain_road_end" and tile_position.distance_to(Vector3(-90.0, tile_position.y, 0.0)) < 0.1:
			west_end_yaw = float(tile["yaw"])
	west_spur_positions.sort()
	for position_index in range(1, west_spur_positions.size()):
		if west_spur_positions[position_index] - west_spur_positions[position_index - 1] > 4.01:
			failures.append("Non-divisible route segments should distribute road tiles without visible gaps")
			break
	if absf(west_end_yaw - 270.0) > 0.1:
		failures.append("The western road end should open east toward the route")
	var mountain_wall := world_shell.find_child("TerrainObstacle_mountain_wall", true, false)
	if mountain_wall == null:
		failures.append("Mountain passes should be visibly bounded by mountain-wall structures")
	elif mountain_wall.find_child("KenneyAsset_scenery_rock_a", true, false) == null and mountain_wall.find_child("KenneyAsset_scenery_rock_b", true, false) == null:
		failures.append("Mountain walls should use the existing large scenery-rock GLBs")
	var mountain_wall_count := 0
	for child in world_shell.get_children():
		if child.name.begins_with("TerrainObstacle_mountain_wall"):
			mountain_wall_count += 1
	if mountain_wall_count < 2:
		failures.append("The authored pass should have visible mountain walls on both sides")

	var minimap := MinimapScript.new()
	root.add_child(minimap)
	minimap.snapshot = {
		"visibility": {
			"tile_size": 8.0,
			"visible_cells": PackedVector3Array([Vector3(-90.0, 0.0, 0.0)]),
			"explored_cells": PackedVector3Array(),
		},
	}
	if not minimap._route_point_exposed(Vector3(-90.0, 0.0, 0.0)):
		failures.append("The minimap should retain route detail in an exposed cell")
	if minimap._route_point_exposed(Vector3(0.0, 0.0, -56.0)):
		failures.append("The minimap should hide route detail in an unexposed cell")

	if failures.is_empty():
		print("CAMPAIGN_NAVIGATION_PRESENTATION_PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("CAMPAIGN_NAVIGATION_PRESENTATION_FAIL")
	quit(1)


func _position_is_clear(simulation: Node, position: Vector3) -> bool:
	for obstacle in simulation.navigation_obstacles:
		if obstacle.grow(simulation.NAV_PATH_MARGIN).has_point(Vector2(position.x, position.z)):
			return false
	return true


func _find_authored(entities: Dictionary, authored_id: String) -> String:
	for entity_id in entities:
		if str(entities[entity_id].get("authored_id", "")) == authored_id:
			return str(entity_id)
	return ""


func _collect_straight_tiles(node: Node, result: Array) -> void:
	for child in node.get_children():
		if child.name.begins_with("RouteTile_"):
			var visual := child.find_child("KenneyAsset_terrain_road_straight", true, false)
			if visual != null:
				result.append({"position": child.position, "yaw": visual.rotation_degrees.y})
		_collect_straight_tiles(child, result)


func _collect_route_tiles(node: Node, result: Array) -> void:
	for child in node.get_children():
		if child.name.begins_with("RouteTile_"):
			var asset := str(child.get_meta("terrain_asset", ""))
			var visual := child.find_child("KenneyAsset_%s" % asset, true, false)
			if visual != null:
				result.append({"position": child.global_position, "asset": asset, "yaw": visual.rotation_degrees.y})
		_collect_route_tiles(child, result)
