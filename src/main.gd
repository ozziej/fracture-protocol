extends Node3D

const SimulationScript = preload("res://src/rts_simulation.gd")
const UnitViewScript = preload("res://src/rts_unit_view.gd")
const BuildingViewScript = preload("res://src/rts_building_view.gd")
const MinimapScript = preload("res://src/minimap.gd")

const MAP_HALF_WIDTH := 60.0
const MAP_HALF_DEPTH := 40.0

var simulation
var camera: Camera3D
var camera_target := Vector3.ZERO
var camera_distance := 31.0
var camera_yaw := 0.0
var camera_pitch := 0.72
var pointer_position := Vector2.ZERO

var unit_views: Dictionary = {}
var building_views: Dictionary = {}
var control_views: Dictionary = {}
var resource_views: Dictionary = {}
var selected_ids: Array = []
var control_groups: Dictionary = {}

var dragging := false
var drag_start := Vector2.ZERO
var drag_current := Vector2.ZERO
var selection_marquee: ColorRect
var build_mode := ""
var attack_move_mode := false
var build_ghost: Node3D
var collector_assignment_mode := false
var collector_assignment_source_id := ""
var collector_assignment_unit_id := ""

var credits_label: Label
var territory_label: Label
var supply_label: Label
var technology_label: Label
var force_label: Label
var selected_label: Label
var objective_label: Label
var status_label: Label
var event_log_label: Label
var build_button: Button
var queue_button: Button
var heavy_queue_button: Button
var research_button: Button
var repair_button: Button
var collector_button: Button
var minimap
var combat_effect_sequence := 0


func _ready() -> void:
	_build_environment()
	_build_camera()
	simulation = SimulationScript.new()
	add_child(simulation)
	simulation.simulation_event.connect(_on_simulation_event)
	simulation.start_match()
	_build_world_shell()
	_build_ui()
	_sync_views()
	_update_camera()
	_update_hud()


func _process(delta: float) -> void:
	_process_camera_input(delta)
	simulation.step(delta)
	_sync_views(delta)
	_update_camera()
	_update_hud()
	_update_build_ghost()
	if dragging:
		_update_selection_marquee()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		pointer_position = event.position
		if dragging:
			drag_current = event.position
		return
	if event is InputEventMouseButton:
		pointer_position = event.position
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			camera_distance = max(16.0, camera_distance - 2.5)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			camera_distance = min(45.0, camera_distance + 2.5)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if _pointer_over_ui():
					return
				dragging = true
				drag_start = event.position
				drag_current = event.position
				selection_marquee.visible = true
			else:
				if dragging:
					dragging = false
					selection_marquee.visible = false
					_finish_left_click()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if collector_assignment_mode:
				_cancel_collector_assignment()
				return
			_cancel_build_mode()
			_issue_context_order(event.position)
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode >= KEY_0 and event.keycode <= KEY_9:
			_handle_control_group(event.keycode - KEY_0, event.ctrl_pressed or event.meta_pressed)
			return
		match event.keycode:
			KEY_B:
				_toggle_build_mode()
			KEY_F:
				_toggle_attack_move_mode()
			KEY_X:
				_stop_selected_units()
			KEY_Q:
				_queue_strider()
			KEY_C:
				_collector_action()
			KEY_U:
				_begin_collector_assignment()
			KEY_N:
				_restart_match()
			KEY_V:
				_queue_bulwark()
			KEY_T:
				_research_advanced_targeting()
			KEY_Y:
				_repair_selected()
			KEY_E:
				camera_yaw = clamp(camera_yaw + deg_to_rad(8.0), -0.78, 0.78)
			KEY_R:
				camera_yaw = clamp(camera_yaw - deg_to_rad(8.0), -0.78, 0.78)
			KEY_H:
				_focus_selection()
			KEY_ESCAPE:
				_cancel_build_mode()
				_cancel_collector_assignment()
				attack_move_mode = false
				selected_ids.clear()
				_update_selected_visuals()
			KEY_SPACE:
				status_label.text = "Simulation is live — orders resolve on the fixed tick."


func _build_environment() -> void:
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#071321")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#79a4b7")
	environment.ambient_light_energy = 0.7
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_environment.environment = environment
	add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -28.0, 0.0)
	sun.light_color = Color("#d5e7ec")
	sun.light_energy = 1.45
	sun.shadow_enabled = true
	add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-22.0, 148.0, 0.0)
	fill.light_color = Color("#3a6ea0")
	fill.light_energy = 0.38
	add_child(fill)


func _build_camera() -> void:
	camera = Camera3D.new()
	camera.name = "TacticalCamera"
	camera.current = true
	camera.fov = 48.0
	camera.near = 0.1
	camera.far = 180.0
	add_child(camera)


func _build_world_shell() -> void:
	var terrain: Dictionary = simulation.get_level_terrain()
	var bounds: Vector2 = simulation.get_level_bounds()
	var ground_size := _vector3_from_data(terrain.get("ground_size", {}), Vector3(bounds.x * 2.0, 0.25, bounds.y * 2.0))
	var ground_position := _vector3_from_data(terrain.get("ground_position", {}), Vector3(0.0, -0.18, 0.0))
	var ground := MeshInstance3D.new()
	var ground_mesh := BoxMesh.new()
	ground_mesh.size = ground_size
	ground.mesh = ground_mesh
	ground.position = ground_position
	ground.material_override = _material(Color("#0b222b"), 0.92, 0.05)
	add_child(ground)

	var grid_spacing: int = max(1, int(terrain.get("grid_spacing", 4)))
	for x in range(int(-bounds.x), int(bounds.x) + 1, grid_spacing):
		var line := MeshInstance3D.new()
		var line_mesh := BoxMesh.new()
		line_mesh.size = Vector3(0.035, 0.018, ground_size.z)
		line.mesh = line_mesh
		line.position = Vector3(float(x), ground_position.y + ground_size.y * 0.5 + 0.01, 0.0)
		line.material_override = _material(Color(0.13, 0.36, 0.4, 0.45), 1.0, 0.0)
		add_child(line)
	for z in range(int(-bounds.y), int(bounds.y) + 1, grid_spacing):
		var line := MeshInstance3D.new()
		var line_mesh := BoxMesh.new()
		line_mesh.size = Vector3(ground_size.x, 0.018, 0.035)
		line.mesh = line_mesh
		line.position = Vector3(0.0, ground_position.y + ground_size.y * 0.5 + 0.01, float(z))
		line.material_override = _material(Color(0.13, 0.36, 0.4, 0.45), 1.0, 0.0)
		add_child(line)

	for road_data in terrain.get("roads", []):
		var road: Dictionary = road_data
		_create_road(_vector3_from_data(road.get("position", {})), _vector3_from_data(road.get("size", {}), Vector3(4.0, 0.03, 4.0)))
	for marker_data in terrain.get("lane_markers", []):
		var marker: Dictionary = marker_data
		_create_lane_marker(_vector3_from_data(marker.get("position", {})))
	for accent_data in terrain.get("accents", []):
		var accent: Dictionary = accent_data
		_create_terrain_accent(
			_vector3_from_data(accent.get("position", {})),
			_vector3_from_data(accent.get("size", {}), Vector3(4.0, 0.04, 4.0)),
			Color(str(accent.get("color", "#123d49")))
		)
	for obstacle_data in terrain.get("obstacles", []):
		var obstacle: Dictionary = obstacle_data
		_create_obstacle(_vector3_from_data(obstacle.get("position", {})), _vector3_from_data(obstacle.get("size", {}), Vector3(2.0, 1.0, 2.0)))


func _create_road(position: Vector3, size: Vector3) -> void:
	var road := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	road.mesh = mesh
	road.position = position
	road.material_override = _material(Color("#163741"), 0.98, 0.08)
	add_child(road)


func _create_lane_marker(position: Vector3) -> void:
	var marker := MeshInstance3D.new()
	var marker_mesh := BoxMesh.new()
	marker_mesh.size = Vector3(0.55, 0.025, 0.12)
	marker.mesh = marker_mesh
	marker.position = position
	marker.material_override = _emissive_material(Color("#1da8b6"), 1.4)
	add_child(marker)


func _create_obstacle(position: Vector3, size: Vector3) -> void:
	var obstacle := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	obstacle.mesh = mesh
	obstacle.position = position
	obstacle.material_override = _material(Color("#243c44"), 0.78, 0.22)
	add_child(obstacle)
	var highlight := MeshInstance3D.new()
	var highlight_mesh := BoxMesh.new()
	highlight_mesh.size = Vector3(size.x * 0.72, 0.04, size.z * 0.72)
	highlight.mesh = highlight_mesh
	highlight.position = position + Vector3(0.0, size.y * 0.5 + 0.03, 0.0)
	highlight.material_override = _material(Color("#3c6d70"), 0.85, 0.12)
	add_child(highlight)


func _create_terrain_accent(position: Vector3, size: Vector3, color: Color) -> void:
	var accent := MeshInstance3D.new()
	var accent_mesh := BoxMesh.new()
	accent_mesh.size = size
	accent.mesh = accent_mesh
	accent.position = position
	accent.material_override = _material(color, 0.72, 0.08)
	add_child(accent)


func _vector3_from_data(value: Variant, fallback: Vector3 = Vector3.ZERO) -> Vector3:
	if value is Vector3:
		return value
	if value is Dictionary:
		var data: Dictionary = value
		return Vector3(float(data.get("x", fallback.x)), float(data.get("y", fallback.y)), float(data.get("z", fallback.z)))
	return fallback


func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "TacticalHUD"
	add_child(canvas)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(root)

	var top_panel := PanelContainer.new()
	top_panel.position = Vector2(18.0, 16.0)
	top_panel.size = Vector2(1170.0, 70.0)
	top_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.025, 0.075, 0.1, 0.94), Color(0.18, 0.7, 0.78, 0.75)))
	root.add_child(top_panel)
	var top_margin := MarginContainer.new()
	top_margin.add_theme_constant_override("margin_left", 18)
	top_margin.add_theme_constant_override("margin_right", 18)
	top_margin.add_theme_constant_override("margin_top", 9)
	top_margin.add_theme_constant_override("margin_bottom", 9)
	top_panel.add_child(top_margin)
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 24)
	top_margin.add_child(top_row)
	var title := _label("FRACTURE PROTOCOL", 21, Color("#d6fbff"))
	title.custom_minimum_size.x = 220.0
	top_row.add_child(title)
	credits_label = _label("CREDITS 850", 17, Color("#ffd36a"))
	top_row.add_child(credits_label)
	territory_label = _label("TERRITORY 0/3", 17, Color("#8cebf3"))
	top_row.add_child(territory_label)
	supply_label = _label("SUPPLY CONNECTED", 17, Color("#7cf1ad"))
	top_row.add_child(supply_label)
	technology_label = _label("TECH LOCKED", 17, Color("#ffbf6a"))
	top_row.add_child(technology_label)
	force_label = _label("FORCE 4/24", 17, Color("#c3d8df"))
	top_row.add_child(force_label)

	objective_label = _label("OBJECTIVE: Protect the Collector route, then research Advanced Targeting.", 15, Color("#ffd36a"))
	objective_label.position = Vector2(22.0, 98.0)
	objective_label.size = Vector2(1210.0, 25.0)
	root.add_child(objective_label)

	status_label = _label("Skirmish online. Secure the relay network.", 16, Color("#c3d8df"))
	status_label.position = Vector2(22.0, 123.0)
	status_label.size = Vector2(980.0, 26.0)
	root.add_child(status_label)

	var help := _label("WASD pan   H focus   F attack-move   X stop   Ctrl/Cmd+1-9 assign   1-9 recall   C collector   U route   Q raider   V bulwark   T research   Y repair   B relay   N restart   Right-click order   Right-click a selected Assembly Bay on an active friendly staging site to set its named rally.   Credits fund production/research/repair; unsupplied units are slower and weaker.", 12, Color("#8ca9b5"))
	help.position = Vector2(22.0, 149.0)
	help.size = Vector2(1230.0, 24.0)
	root.add_child(help)

	event_log_label = _label("EVENT LOG\nAwaiting orders...", 14, Color("#abc5cb"))
	event_log_label.position = Vector2(18.0, 500.0)
	event_log_label.size = Vector2(390.0, 96.0)
	event_log_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	event_log_label.add_theme_constant_override("shadow_offset_x", 2)
	event_log_label.add_theme_constant_override("shadow_offset_y", 2)
	root.add_child(event_log_label)

	var bottom_panel := PanelContainer.new()
	bottom_panel.position = Vector2(18.0, 616.0)
	bottom_panel.size = Vector2(1244.0, 88.0)
	bottom_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.025, 0.075, 0.1, 0.96), Color(0.18, 0.7, 0.78, 0.75)))
	root.add_child(bottom_panel)
	var bottom_margin := MarginContainer.new()
	bottom_margin.add_theme_constant_override("margin_left", 16)
	bottom_margin.add_theme_constant_override("margin_right", 16)
	bottom_margin.add_theme_constant_override("margin_top", 12)
	bottom_margin.add_theme_constant_override("margin_bottom", 12)
	bottom_panel.add_child(bottom_margin)
	var bottom_row := HBoxContainer.new()
	bottom_row.add_theme_constant_override("separation", 12)
	bottom_margin.add_child(bottom_row)
	selected_label = _label("NO SELECTION\nSelect units or a structure", 15, Color("#d2e7ec"))
	selected_label.custom_minimum_size = Vector2(260.0, 52.0)
	bottom_row.add_child(selected_label)

	build_button = Button.new()
	build_button.text = "DEPLOY RELAY [B]"
	build_button.custom_minimum_size = Vector2(135.0, 48.0)
	build_button.tooltip_text = "Place a Forward Relay near a connected friendly structure. Cost: 180 credits."
	build_button.pressed.connect(_toggle_build_mode)
	bottom_row.add_child(build_button)

	queue_button = Button.new()
	queue_button.text = "QUEUE RAIDER [Q]"
	queue_button.custom_minimum_size = Vector2(135.0, 48.0)
	queue_button.tooltip_text = "Queue a fast attack vehicle at the Assembly Bay. Cost: 105 credits."
	queue_button.pressed.connect(_queue_strider)
	bottom_row.add_child(queue_button)

	heavy_queue_button = Button.new()
	heavy_queue_button.text = "QUEUE BULWARK [V]"
	heavy_queue_button.custom_minimum_size = Vector2(145.0, 48.0)
	heavy_queue_button.tooltip_text = "Queue a heavy assault vehicle after Advanced Targeting research. Cost: 160 credits."
	heavy_queue_button.pressed.connect(_queue_bulwark)
	bottom_row.add_child(heavy_queue_button)

	research_button = Button.new()
	research_button.text = "RESEARCH TARGETING [T]"
	research_button.custom_minimum_size = Vector2(160.0, 48.0)
	research_button.tooltip_text = "Research Advanced Targeting at the Assembly Bay. Cost: 300 credits."
	research_button.pressed.connect(_research_advanced_targeting)
	bottom_row.add_child(research_button)

	repair_button = Button.new()
	repair_button.text = "REPAIR [Y]"
	repair_button.custom_minimum_size = Vector2(100.0, 48.0)
	repair_button.tooltip_text = "Repair selected units near a repair station or selected structures. Cost: 30/45 credits."
	repair_button.pressed.connect(_repair_selected)
	bottom_row.add_child(repair_button)

	collector_button = Button.new()
	collector_button.text = "QUEUE COLLECTOR [C]"
	collector_button.custom_minimum_size = Vector2(135.0, 48.0)
	collector_button.tooltip_text = "Queue a Collector at the Assembly Bay. Select one and press U to assign its source and Resource Processor. Cost: 115 credits."
	collector_button.pressed.connect(_collector_action)
	bottom_row.add_child(collector_button)

	minimap = MinimapScript.new()
	minimap.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	minimap.position = Vector2(1020.0, 500.0)
	minimap.size = Vector2(242.0, 106.0)
	root.add_child(minimap)

	selection_marquee = ColorRect.new()
	selection_marquee.color = Color(0.25, 0.88, 0.98, 0.13)
	selection_marquee.mouse_filter = Control.MOUSE_FILTER_IGNORE
	selection_marquee.visible = false
	root.add_child(selection_marquee)


func _finish_left_click() -> void:
	if collector_assignment_mode:
		_handle_collector_assignment_click()
		return
	if build_mode != "":
		var build_position := _screen_to_ground(pointer_position)
		if _is_inside_map(build_position):
			simulation.issue_command("build", "player", {"building_type": build_mode, "position": build_position})
		_cancel_build_mode()
		return
	var drag_rect := Rect2(drag_start, drag_current - drag_start).abs()
	if drag_rect.size.length() < 12.0:
		var clicked_id := _entity_at_screen(pointer_position, true)
		selected_ids.clear()
		if not clicked_id.is_empty() and ((simulation.units.has(clicked_id) and simulation.units[clicked_id]["team"] == "player") or (simulation.buildings.has(clicked_id) and simulation.buildings[clicked_id]["team"] == "player")):
			selected_ids.append(clicked_id)
	else:
		selected_ids.clear()
		for entity_id in simulation.units:
			var unit: Dictionary = simulation.units[entity_id]
			if unit["team"] != "player":
				continue
			var projected := camera.unproject_position(unit["position"] + Vector3.UP * 0.6)
			if drag_rect.has_point(projected):
				selected_ids.append(entity_id)
	_update_selected_visuals()


func _issue_context_order(screen_position: Vector2) -> void:
	if selected_ids.is_empty():
		return
	var clicked_id := _entity_at_screen(screen_position, false)
	var clicked_enemy: bool = not clicked_id.is_empty() and ((simulation.units.has(clicked_id) and simulation.units[clicked_id]["team"] == "enemy") or (simulation.buildings.has(clicked_id) and simulation.buildings[clicked_id]["team"] == "enemy"))
	if clicked_enemy:
		simulation.issue_command("attack", "player", {"entity_ids": selected_ids, "target_id": clicked_id})
		attack_move_mode = false
		return
	var rally_building_id := _selected_rally_building_id()
	var control_point_id := _control_point_at_screen(screen_position)
	var destination := _screen_to_ground(screen_position)
	if not attack_move_mode and not rally_building_id.is_empty() and _is_inside_map(destination):
		if not control_point_id.is_empty():
			simulation.issue_command("set_rally_point", "player", {"building_id": rally_building_id, "control_point_id": control_point_id})
			status_label.text = "Staging rally order queued for the selected Assembly Bay."
		else:
			simulation.issue_command("set_rally_point", "player", {"building_id": rally_building_id, "position": destination})
			status_label.text = "Ground rally order queued for the selected Assembly Bay."
		return
	if _is_inside_map(destination):
		if attack_move_mode:
			simulation.issue_command("attack_move", "player", {"entity_ids": selected_ids, "position": destination})
			attack_move_mode = false
		else:
			simulation.issue_command("move", "player", {"entity_ids": selected_ids, "position": destination})

func _handle_control_group(group_index: int, assign: bool) -> void:
	var group_key := str(group_index)
	if assign:
		var group: Array = []
		for entity_id in selected_ids:
			if simulation.units.has(entity_id) and simulation.units[entity_id]["team"] == "player":
				group.append(entity_id)
			elif simulation.buildings.has(entity_id) and simulation.buildings[entity_id]["team"] == "player":
				group.append(entity_id)
		if group.is_empty():
			status_label.text = "Select a friendly force before assigning a control group."
			return
		control_groups[group_key] = group
		status_label.text = "Control group %d assigned to %d entities." % [group_index, group.size()]
		return
	if not control_groups.has(group_key):
		status_label.text = "Control group %d is empty." % group_index
		return
	selected_ids.clear()
	for entity_id in control_groups[group_key]:
		if (simulation.units.has(entity_id) and simulation.units[entity_id]["team"] == "player") or (simulation.buildings.has(entity_id) and simulation.buildings[entity_id]["team"] == "player"):
			selected_ids.append(entity_id)
	_update_selected_visuals()
	if selected_ids.is_empty():
		status_label.text = "Control group %d is empty." % group_index
	else:
		status_label.text = "Control group %d recalled: %d entities." % [group_index, selected_ids.size()]
	_focus_selection(false)


func _focus_selection(show_status := true) -> void:
	var center := Vector3.ZERO
	var count := 0
	for entity_id in selected_ids:
		if simulation.units.has(entity_id):
			center += simulation.units[entity_id]["position"]
			count += 1
		elif simulation.buildings.has(entity_id):
			center += simulation.buildings[entity_id]["position"]
			count += 1
	if count == 0:
		if show_status:
			status_label.text = "Select a friendly force before focusing the camera."
		return
	center /= float(count)
	var bounds: Vector2 = simulation.get_level_bounds()
	camera_target = Vector3(clamp(center.x, -bounds.x * 0.6, bounds.x * 0.6), 0.0, clamp(center.z, -bounds.y * 0.62, bounds.y * 0.62))
	if show_status:
		status_label.text = "Camera focused on %d selected entities." % count


func _entity_at_screen(screen_position: Vector2, player_only: bool) -> String:
	var closest_id := ""
	var closest_distance := 32.0
	for entity_id in simulation.units:
		var unit: Dictionary = simulation.units[entity_id]
		if player_only and unit["team"] != "player":
			continue
		var projected := camera.unproject_position(unit["position"] + Vector3.UP * 0.7)
		var distance := projected.distance_to(screen_position)
		if distance < closest_distance:
			closest_distance = distance
			closest_id = entity_id
	for entity_id in simulation.buildings:
		var building: Dictionary = simulation.buildings[entity_id]
		if player_only and building["team"] != "player":
			continue
		var projected := camera.unproject_position(building["position"] + Vector3.UP * 1.0)
		var distance := projected.distance_to(screen_position)
		if distance < closest_distance:
			closest_distance = distance
			closest_id = entity_id
	return closest_id


func _screen_to_ground(screen_position: Vector2) -> Vector3:
	var origin := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	if abs(direction.y) < 0.0001:
		return Vector3.ZERO
	var distance := -origin.y / direction.y
	return origin + direction * distance


func _is_inside_map(position: Vector3) -> bool:
	var bounds: Vector2 = simulation.get_level_bounds() if simulation else Vector2(MAP_HALF_WIDTH, MAP_HALF_DEPTH)
	return abs(position.x) <= bounds.x - 2.0 and abs(position.z) <= bounds.y - 2.0


func _toggle_attack_move_mode() -> void:
	if selected_ids.is_empty():
		status_label.text = "Select units before issuing an attack-move order."
		return
	if attack_move_mode:
		attack_move_mode = false
		status_label.text = "Attack-move mode cancelled."
		return
	_cancel_build_mode()
	attack_move_mode = true
	status_label.text = "ATTACK-MOVE MODE — right-click a destination. Units engage enemies on the route."


func _stop_selected_units() -> void:
	if selected_ids.is_empty():
		return
	attack_move_mode = false
	simulation.issue_command("stop", "player", {"entity_ids": selected_ids})
	status_label.text = "Stop order queued."


func _toggle_build_mode() -> void:
	if build_mode == "relay":
		_cancel_build_mode()
		return
	attack_move_mode = false
	build_mode = "relay"
	status_label.text = "BUILD MODE — click near your network to place a Forward Relay. Right-click cancels."
	_create_build_ghost()


func _cancel_build_mode() -> void:
	build_mode = ""
	if build_ghost:
		build_ghost.queue_free()
		build_ghost = null
	if status_label and simulation and not simulation.match_over:
		status_label.text = "Skirmish online. Secure the relay network."


func _create_build_ghost() -> void:
	if build_ghost:
		build_ghost.queue_free()
	build_ghost = Node3D.new()
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2.5, 2.2, 2.5)
	mesh.mesh = box
	mesh.position.y = 1.1
	mesh.material_override = _material(Color(0.18, 0.86, 0.88, 0.35), 0.65, 0.1)
	build_ghost.add_child(mesh)
	add_child(build_ghost)


func _update_build_ghost() -> void:
	if not build_ghost:
		return
	var position := _screen_to_ground(pointer_position)
	build_ghost.position = Vector3(position.x, 0.0, position.z)


func _find_player_assembly_bay() -> String:
	for building_id in simulation.buildings:
		var building: Dictionary = simulation.buildings[building_id]
		if building["team"] == "player" and building["kind"] == "assembly_bay":
			return building_id
	return ""


func _selected_rally_building_id() -> String:
	if selected_ids.size() != 1:
		return ""
	var entity_id := str(selected_ids[0])
	if not simulation.buildings.has(entity_id):
		return ""
	var building: Dictionary = simulation.buildings[entity_id]
	if building["team"] == "player" and building["kind"] == "assembly_bay" and building["complete"]:
		return entity_id
	return ""


func _collector_action() -> void:
	if collector_assignment_mode:
		_cancel_collector_assignment()
		return
	var selected_collector := _selected_collector_id()
	if not selected_collector.is_empty():
		_begin_collector_assignment()
		return
	_queue_collector()


func _selected_collector_id() -> String:
	if selected_ids.size() != 1:
		return ""
	var entity_id: String = str(selected_ids[0])
	if simulation.units.has(entity_id) and simulation.units[entity_id]["team"] == "player" and simulation.units[entity_id]["kind"] == "collector":
		return entity_id
	return ""


func _queue_collector() -> void:
	var assembly_id := _find_player_assembly_bay()
	if assembly_id.is_empty():
		status_label.text = "No Assembly Bay available for Collector production."
		return
	simulation.issue_command("produce", "player", {"building_id": assembly_id, "unit_type": "collector"})


func _begin_collector_assignment() -> void:
	var collector_id := _selected_collector_id()
	if collector_id.is_empty():
		status_label.text = "Select exactly one Collector before assigning a route."
		return
	_cancel_build_mode()
	attack_move_mode = false
	collector_assignment_mode = true
	collector_assignment_source_id = ""
	collector_assignment_unit_id = collector_id
	status_label.text = "ROUTE MODE — click a resource field, then click a friendly Resource Processor. Right-click or U cancels."


func _handle_collector_assignment_click() -> void:
	if collector_assignment_unit_id.is_empty() or not simulation.units.has(collector_assignment_unit_id):
		_cancel_collector_assignment()
		return
	if collector_assignment_source_id.is_empty():
		var source_id := _resource_node_at_screen(pointer_position)
		if source_id.is_empty():
			status_label.text = "Click the Northern or Southern Energy Field to choose a source."
			return
		collector_assignment_source_id = source_id
		status_label.text = "Source selected: %s — now click a friendly Resource Processor." % simulation.resource_nodes[source_id]["display_name"]
		return
	var destination_id := _refinery_at_screen(pointer_position)
	if destination_id.is_empty():
		status_label.text = "Click a completed friendly Resource Processor to finish the route."
		return
	simulation.issue_command("assign_collector", "player", {
		"collector_id": collector_assignment_unit_id,
		"source_id": collector_assignment_source_id,
		"destination_id": destination_id,
	})
	_cancel_collector_assignment(false)


func _resource_node_at_screen(screen_position: Vector2) -> String:
	var closest_id := ""
	var closest_distance: float = 42.0
	for node_id in simulation.resource_nodes:
		var node: Dictionary = simulation.resource_nodes[node_id]
		var projected := camera.unproject_position(node["position"] + Vector3.UP * 0.6)
		var distance: float = projected.distance_to(screen_position)
		if distance < closest_distance:
			closest_distance = distance
			closest_id = node_id
	return closest_id


func _refinery_at_screen(screen_position: Vector2) -> String:
	var closest_id := ""
	var closest_distance: float = 46.0
	for building_id in simulation.buildings:
		var building: Dictionary = simulation.buildings[building_id]
		if building["team"] != "player" or building["kind"] != "refinery" or not building["complete"]:
			continue
		var projected := camera.unproject_position(building["position"] + Vector3.UP * 1.0)
		var distance: float = projected.distance_to(screen_position)
		if distance < closest_distance:
			closest_distance = distance
			closest_id = building_id
	return closest_id


func _control_point_at_screen(screen_position: Vector2) -> String:
	var closest_id := ""
	var closest_distance: float = 50.0
	for point_id in simulation.control_points:
		var point: Dictionary = simulation.control_points[point_id]
		var projected := camera.unproject_position(point["position"] + Vector3.UP * 1.3)
		var distance := projected.distance_to(screen_position)
		if distance < closest_distance:
			closest_distance = distance
			closest_id = point_id
	return closest_id


func _cancel_collector_assignment(show_status := true) -> void:
	var was_active := collector_assignment_mode
	collector_assignment_mode = false
	collector_assignment_source_id = ""
	collector_assignment_unit_id = ""
	if show_status and was_active and status_label and simulation and not simulation.match_over:
		status_label.text = "Collector route assignment cancelled."


func _queue_strider() -> void:
	var assembly_id := _find_player_assembly_bay()
	if assembly_id.is_empty():
		status_label.text = "No Assembly Bay available."
		return
	simulation.issue_command("produce", "player", {"building_id": assembly_id, "unit_type": "raider"})


func _queue_bulwark() -> void:
	var assembly_id := _find_player_assembly_bay()
	if assembly_id.is_empty():
		status_label.text = "No Assembly Bay available."
		return
	simulation.issue_command("produce", "player", {"building_id": assembly_id, "unit_type": "bulwark"})


func _research_advanced_targeting() -> void:
	var assembly_id := _find_player_assembly_bay()
	if assembly_id.is_empty():
		status_label.text = "No Assembly Bay available for research."
		return
	simulation.issue_command("research", "player", {"building_id": assembly_id, "technology_id": "advanced_targeting"})


func _repair_selected() -> void:
	if selected_ids.is_empty():
		status_label.text = "Select a damaged unit or structure before repairing."
		return
	simulation.issue_command("repair", "player", {"entity_ids": selected_ids})


func _has_damaged_selection() -> bool:
	for entity_id in selected_ids:
		if simulation.units.has(entity_id) and float(simulation.units[entity_id]["health"]) < float(simulation.units[entity_id]["max_health"]):
			return true
		if simulation.buildings.has(entity_id) and float(simulation.buildings[entity_id]["health"]) < float(simulation.buildings[entity_id]["max_health"]):
			return true
	return false


func _process_camera_input(delta: float) -> void:
	var input_vector := Vector2.ZERO
	if Input.is_action_pressed("camera_left"):
		input_vector.x -= 1.0
	if Input.is_action_pressed("camera_right"):
		input_vector.x += 1.0
	if Input.is_action_pressed("camera_forward"):
		input_vector.y += 1.0
	if Input.is_action_pressed("camera_back"):
		input_vector.y -= 1.0
	if input_vector.length() > 0.0:
		input_vector = input_vector.normalized()
		var forward := Vector3(-sin(camera_yaw), 0.0, -cos(camera_yaw))
		var right := Vector3(cos(camera_yaw), 0.0, -sin(camera_yaw))
		camera_target += (right * input_vector.x + forward * input_vector.y) * delta * 30.0
	if pointer_position.x < 12.0:
		camera_target.x -= delta * 18.0
	elif pointer_position.x > get_viewport().size.x - 12.0:
		camera_target.x += delta * 18.0
	if pointer_position.y < 12.0:
		camera_target.z -= delta * 18.0
	elif pointer_position.y > get_viewport().size.y - 12.0:
		camera_target.z += delta * 18.0
	var bounds: Vector2 = simulation.get_level_bounds() if simulation else Vector2(MAP_HALF_WIDTH, MAP_HALF_DEPTH)
	camera_target.x = clamp(camera_target.x, -bounds.x * 0.6, bounds.x * 0.6)
	camera_target.z = clamp(camera_target.z, -bounds.y * 0.62, bounds.y * 0.62)



func _update_camera() -> void:
	var offset := Vector3(sin(camera_yaw) * camera_distance, camera_distance * camera_pitch, cos(camera_yaw) * camera_distance)
	camera.global_position = camera_target + offset
	camera.look_at(camera_target, Vector3.UP)


func _sync_views(frame_delta: float = 0.0) -> void:
	var state: Dictionary = simulation.get_state()
	for selected_id in selected_ids.duplicate():
		if not state["units"].has(selected_id) and not state["buildings"].has(selected_id):
			selected_ids.erase(selected_id)
	for entity_id in state["units"]:
		if not unit_views.has(entity_id):
			var view = UnitViewScript.new()
			add_child(view)
			view.setup(state["units"][entity_id])
			unit_views[entity_id] = view
		unit_views[entity_id].sync(state["units"][entity_id], selected_ids.has(entity_id), frame_delta)
	for entity_id in unit_views.keys():
		if not state["units"].has(entity_id):
			unit_views[entity_id].queue_free()
			unit_views.erase(entity_id)

	for entity_id in state["buildings"]:
		if not building_views.has(entity_id):
			var view = BuildingViewScript.new()
			add_child(view)
			view.setup(state["buildings"][entity_id])
			building_views[entity_id] = view
		building_views[entity_id].sync(state["buildings"][entity_id], selected_ids.has(entity_id))
	for entity_id in building_views.keys():
		if not state["buildings"].has(entity_id):
			building_views[entity_id].queue_free()
			building_views.erase(entity_id)

	for point_id in state["control_points"]:
		if not control_views.has(point_id):
			control_views[point_id] = _create_control_view(state["control_points"][point_id])
		_update_control_view(control_views[point_id], state["control_points"][point_id])
	for node_id in state["resource_nodes"]:
		if not resource_views.has(node_id):
			resource_views[node_id] = _create_resource_view(state["resource_nodes"][node_id])

	if minimap:
		minimap.set_snapshot(state)


func _create_control_view(point: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.position = point["position"]
	var pad := MeshInstance3D.new()
	var pad_mesh := CylinderMesh.new()
	pad_mesh.top_radius = 3.3
	pad_mesh.bottom_radius = 3.3
	pad_mesh.height = 0.12
	pad_mesh.radial_segments = 32
	pad.mesh = pad_mesh
	root.add_child(pad)
	var beacon := MeshInstance3D.new()
	var beacon_mesh := CylinderMesh.new()
	beacon_mesh.top_radius = 0.12
	beacon_mesh.bottom_radius = 0.18
	beacon_mesh.height = 2.8
	beacon_mesh.radial_segments = 10
	beacon.mesh = beacon_mesh
	beacon.position.y = 1.4
	root.add_child(beacon)
	var staging_ring := MeshInstance3D.new()
	staging_ring.name = "StagingRing"
	var staging_mesh := CylinderMesh.new()
	staging_mesh.top_radius = float(point["radius"]) * 0.92
	staging_mesh.bottom_radius = float(point["radius"]) * 0.92
	staging_mesh.height = 0.05
	staging_mesh.radial_segments = 36
	staging_ring.mesh = staging_mesh
	staging_ring.position.y = 0.17
	staging_ring.visible = false
	root.add_child(staging_ring)
	var staging_light := OmniLight3D.new()
	staging_light.name = "StagingLight"
	staging_light.position.y = 1.0
	staging_light.light_energy = 1.1
	staging_light.omni_range = 8.0
	staging_light.visible = false
	root.add_child(staging_light)

	if point["id"] == "central_relay":
		var halo := MeshInstance3D.new()
		halo.name = "RelayHalo"
		var halo_mesh := CylinderMesh.new()
		halo_mesh.top_radius = 4.2
		halo_mesh.bottom_radius = 4.2
		halo_mesh.height = 0.06
		halo_mesh.radial_segments = 40
		halo.mesh = halo_mesh
		halo.position.y = 0.12
		halo.material_override = _emissive_material(Color("#1cc6d7"), 1.6)
		root.add_child(halo)
		var core := MeshInstance3D.new()
		core.name = "RelayCore"
		var core_mesh := SphereMesh.new()
		core_mesh.radius = 0.48
		core_mesh.height = 0.96
		core_mesh.radial_segments = 20
		core_mesh.rings = 10
		core.mesh = core_mesh
		core.position.y = 2.35
		core.material_override = _emissive_material(Color("#a9fbff"), 2.0)
		root.add_child(core)
		var relay_light := OmniLight3D.new()
		relay_light.name = "RelayLight"
		relay_light.position.y = 1.7
		relay_light.light_color = Color("#3ae2ef")
		relay_light.light_energy = 1.8
		relay_light.omni_range = 11.0
		root.add_child(relay_light)

	var label := Label3D.new()
	label.name = "PointLabel"
	label.position.y = 3.0
	label.font_size = 28
	label.outline_size = 7
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	root.add_child(label)
	add_child(root)
	return root


func _update_control_view(view: Node3D, point: Dictionary) -> void:
	var color := Color("#a7b7c8")
	if point["owner"] == "player":
		color = Color("#2ec8e6")
	elif point["owner"] == "enemy":
		color = Color("#f05c67")
	var pad: MeshInstance3D = view.get_child(0)
	var beacon: MeshInstance3D = view.get_child(1)
	pad.material_override = _material(color.darkened(0.28), 0.6, 0.1)
	beacon.material_override = _material(color.lightened(0.2), 0.45, 0.2)
	var staging_active := bool(point.get("staging_active", false))
	var staging_ring := view.get_node_or_null("StagingRing") as MeshInstance3D
	var staging_light := view.get_node_or_null("StagingLight") as OmniLight3D
	if staging_ring:
		staging_ring.visible = staging_active
		if staging_active:
			staging_ring.material_override = _emissive_material(color.lightened(0.18), 1.7)
	if staging_light:
		staging_light.visible = staging_active
		staging_light.light_color = color.lightened(0.15)
	var core := view.get_node_or_null("RelayCore") as MeshInstance3D
	var halo := view.get_node_or_null("RelayHalo") as MeshInstance3D
	if core:
		var pulse := 0.94 + sin(float(Time.get_ticks_msec()) * 0.004) * 0.08
		core.scale = Vector3.ONE * pulse
		core.material_override = _emissive_material(color.lightened(0.3), 2.0)
	if halo:
		halo.material_override = _emissive_material(color.darkened(0.05), 1.6)
	var label: Label3D = view.get_node("PointLabel")
	label.text = "%s %d%%" % [point["display_name"], abs(int(point["capture_progress"]))]
	if staging_active:
		label.text += "\nFORWARD STAGING — REPAIR / RALLY"
	label.modulate = color.lightened(0.35)


func _create_resource_view(resource: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.position = resource["position"]
	var ring := MeshInstance3D.new()
	var ring_mesh := CylinderMesh.new()
	ring_mesh.top_radius = 3.0
	ring_mesh.bottom_radius = 3.0
	ring_mesh.height = 0.08
	ring_mesh.radial_segments = 28
	ring.mesh = ring_mesh
	ring.material_override = _material(Color("#604b24"), 0.72, 0.0)
	root.add_child(ring)
	for index in range(5):
		var crystal := MeshInstance3D.new()
		var crystal_mesh := CylinderMesh.new()
		crystal_mesh.top_radius = 0.2
		crystal_mesh.bottom_radius = 0.42
		crystal_mesh.height = 0.8 + float(index % 3) * 0.35
		crystal_mesh.radial_segments = 6
		crystal.mesh = crystal_mesh
		crystal.position = Vector3(-1.25 + float(index % 3) * 1.25, crystal_mesh.height * 0.5, -0.7 + float(index / 3) * 1.0)
		crystal.rotation_degrees = Vector3(0.0, float(index * 33), 9.0 - float(index) * 3.0)
		crystal.material_override = _material(Color("#e9a93b"), 0.34, 0.36)
		root.add_child(crystal)
	var label := Label3D.new()
	label.text = resource["display_name"]
	label.position.y = 2.8
	label.font_size = 27
	label.modulate = Color("#ffcf68")
	label.outline_size = 7
	label.outline_modulate = Color(0.02, 0.03, 0.05, 0.9)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	root.add_child(label)
	add_child(root)
	return root


func _update_selected_visuals() -> void:
	for entity_id in unit_views:
		unit_views[entity_id].selection_disc.visible = selected_ids.has(entity_id)
	for entity_id in building_views:
		building_views[entity_id].selection_disc.visible = selected_ids.has(entity_id)


func _restart_match() -> void:
	_cancel_build_mode()
	_cancel_collector_assignment(false)
	attack_move_mode = false
	selected_ids.clear()
	control_groups.clear()
	event_log_label.text = "EVENT LOG\nAwaiting orders..."
	status_label.modulate = Color("#c3d8df")
	camera_target = Vector3.ZERO
	camera_yaw = 0.0
	for view in unit_views.values():
		if is_instance_valid(view):
			view.queue_free()
	for view in building_views.values():
		if is_instance_valid(view):
			view.queue_free()
	for view in control_views.values():
		if is_instance_valid(view):
			view.queue_free()
	for view in resource_views.values():
		if is_instance_valid(view):
			view.queue_free()
	unit_views.clear()
	building_views.clear()
	control_views.clear()
	resource_views.clear()
	simulation.restart_match()
	_update_selected_visuals()
	_sync_views()
	_update_hud()


func _find_player_collector() -> String:
	for entity_id in simulation.units:
		var unit: Dictionary = simulation.units[entity_id]
		if unit["team"] == "player" and unit["kind"] == "collector":
			return entity_id
	return ""


func _has_player_event(event_type: String) -> bool:
	for event in simulation.event_history:
		if str(event.get("event_type", "")) == event_type and str(event.get("team", "player")) == "player":
			return true
	return false


func _has_player_staging_rally(point_id: String) -> bool:
	for building_id in simulation.buildings:
		var building: Dictionary = simulation.buildings[building_id]
		if building["team"] == "player" and building["kind"] == "assembly_bay" and str(building.get("rally_mode", "ground")) == "control_point" and str(building.get("rally_point_id", "")) == point_id:
			return true
	return false


func _update_objective() -> void:
	if not objective_label or not simulation:
		return
	if simulation.match_over:
		objective_label.text = "OBJECTIVE COMPLETE — Match ended. Press N for a fresh skirmish."
		return
	var collector_id := _find_player_collector()
	if collector_id.is_empty():
		objective_label.text = "OBJECTIVE: Queue a Collector [C], then assign a resource route [U]."
		return
	var collector: Dictionary = simulation.units[collector_id]
	if str(collector.get("collector_state", "")) == "unassigned":
		objective_label.text = "OBJECTIVE: Assign the Collector [U] — click an Energy Field, then your Resource Processor."
		return
	if not _has_player_event("ResourceDelivered"):
		objective_label.text = "OBJECTIVE: Protect the Collector route until energy reaches the Resource Processor."
		return
	var objectives: Dictionary = simulation.get_level_objectives()
	var staging_point_id := str(objectives.get("first_staging_point_id", ""))
	if not staging_point_id.is_empty() and simulation.control_points.has(staging_point_id) and not _has_player_staging_rally(staging_point_id):
		var staging_point: Dictionary = simulation.control_points[staging_point_id]
		if not bool(staging_point.get("staging_active", false)) or staging_point["owner"] != "player":
			objective_label.text = "OBJECTIVE: Secure and connect %s to establish a forward staging site." % staging_point["display_name"]
		else:
			objective_label.text = "OBJECTIVE: Select the Assembly Bay, then right-click %s to set its staging rally. Damaged units repair there [Y]." % staging_point["display_name"]
		return
	var research_status: Dictionary = simulation.get_research_status("player")
	if not simulation.is_technology_unlocked("player", "advanced_targeting"):
		if not str(research_status.get("active_id", "")).is_empty():
			objective_label.text = "OBJECTIVE: Advanced Targeting is researching — defend the Assembly Bay."
		else:
			objective_label.text = "OBJECTIVE: Research Advanced Targeting [T] (300 credits); repairs cost credits too."
		return
	var has_bulwark := false
	for entity_id in simulation.units:
		var unit: Dictionary = simulation.units[entity_id]
		if unit["team"] == "player" and unit["kind"] == "bulwark":
			has_bulwark = true
			break
	if not has_bulwark:
		objective_label.text = "OBJECTIVE: Queue a Bulwark [V], secure the Central Relay, then push the enemy HQ."
	else:
		objective_label.text = "OBJECTIVE: Destroy the enemy Command Hub."

func _update_hud() -> void:
	if not simulation:
		return
	_update_objective()
	credits_label.text = "CREDITS %03d" % int(simulation.player_credits)
	var territory: Dictionary = simulation.get_territory_summary()
	territory_label.text = "TERRITORY %d/%d" % [territory["player"], territory["total"]]
	var supply: Dictionary = simulation.get_supply_summary("player")
	var unsupplied_units: int = int(supply["unsupplied_units"])
	var supply_state := "CONNECTED"
	if unsupplied_units > 0:
		supply_state = "%d UNSUPPLIED" % unsupplied_units
	supply_label.text = "SUPPLY %s" % supply_state
	supply_label.modulate = Color("#ffbf6a") if unsupplied_units > 0 else Color("#7cf1ad")
	var limits: Dictionary = simulation.get_limit_summary("player")
	var unit_limits: Dictionary = limits["units"]
	force_label.text = "FORCE %d/%d" % [int(unit_limits["current"]) + int(unit_limits["queued"]), int(unit_limits["max"])]
	force_label.modulate = Color("#ff7b86") if int(unit_limits["current"]) + int(unit_limits["queued"]) >= int(unit_limits["max"]) else Color("#c3d8df")
	var research_status: Dictionary = simulation.get_research_status("player")
	var targeting_online: bool = simulation.is_technology_unlocked("player", "advanced_targeting")
	var active_research_id: String = str(research_status.get("active_id", ""))
	if targeting_online:
		technology_label.text = "TECH TARGETING ONLINE"
		technology_label.modulate = Color("#7cf1ad")
		research_button.text = "TARGETING ONLINE"
	elif not active_research_id.is_empty():
		var research_total: float = max(0.1, float(research_status.get("total", 0.0)))
		var research_progress: int = int(clamp(1.0 - float(research_status.get("remaining", 0.0)) / research_total, 0.0, 1.0) * 100.0)
		technology_label.text = "TECH %d%%" % research_progress
		technology_label.modulate = Color("#ffd36a")
		research_button.text = "RESEARCHING %d%%" % research_progress
	else:
		technology_label.text = "TECH LOCKED"
		technology_label.modulate = Color("#ffbf6a")
		research_button.text = "RESEARCH TARGETING [T]"
	var assembly_id := _find_player_assembly_bay()
	var has_assembly := not assembly_id.is_empty()
	var assembly_queue_count := 0
	if has_assembly:
		assembly_queue_count = simulation.buildings[assembly_id].get("queue", []).size()
	var queue_limit: int = int(limits["queue"]["max"])
	var queue_full := assembly_queue_count >= queue_limit
	queue_button.text = "QUEUE FULL %d/%d" % [assembly_queue_count, queue_limit] if queue_full else "QUEUE RAIDER [Q]"
	queue_button.disabled = simulation.player_credits < 105.0 or not has_assembly or queue_full
	var selected_collector := _selected_collector_id()
	if collector_assignment_mode:
		collector_button.text = "CANCEL ROUTE [U]"
		collector_button.tooltip_text = "Choose a resource field and a friendly Resource Processor. Right-click or U cancels."
		collector_button.disabled = false
	elif not selected_collector.is_empty():
		collector_button.text = "ASSIGN ROUTE [U]"
		collector_button.tooltip_text = "Assign this Collector to a resource field and a specific Resource Processor."
		collector_button.disabled = false
	else:
		collector_button.text = "QUEUE COLLECTOR [C]"
		collector_button.tooltip_text = "Queue a Collector at the Assembly Bay. Select one and press U to assign its source and Resource Processor. Cost: 115 credits."
		collector_button.disabled = simulation.player_credits < 115.0 or not has_assembly or queue_full
	heavy_queue_button.disabled = simulation.player_credits < 160.0 or not targeting_online or not has_assembly or queue_full
	research_button.disabled = targeting_online or not active_research_id.is_empty() or simulation.player_credits < 300.0 or not has_assembly
	repair_button.disabled = simulation.player_credits < 30.0 or not _has_damaged_selection()
	build_button.disabled = simulation.player_credits < 180.0 and build_mode.is_empty()
	if simulation.match_over:
		queue_button.disabled = true
		heavy_queue_button.disabled = true
		research_button.disabled = true
		repair_button.disabled = true
		collector_button.disabled = true
		build_button.disabled = true
		_cancel_build_mode()
		_cancel_collector_assignment(false)

	var selected_text := "NO SELECTION\nSelect units or a structure"
	if not selected_ids.is_empty():
		var first_id: String = selected_ids[0]
		var selected_data: Dictionary = simulation.units.get(first_id, simulation.buildings.get(first_id, {}))
		if not selected_data.is_empty():
			selected_text = "%s  x%d\n%s" % [selected_data["display_name"].to_upper(), selected_ids.size(), _selection_detail(selected_data)]
	selected_label.text = selected_text


func _selection_detail(data: Dictionary) -> String:
	var supply_text := ""
	if data.has("supply_state"):
		supply_text = "   SUPPLY %s" % str(data["supply_state"]).to_upper()
	var collector_text := ""
	if not str(data.get("collector_state", "")).is_empty():
		var collector_route_label := str(data["collector_state"]).replace("_", "-").to_upper()
		if data["collector_state"] == "to_source":
			collector_route_label = "SOURCE " + str(data.get("collector_source_name", ""))
		elif data["collector_state"] == "to_destination":
			collector_route_label = "TO " + str(data.get("collector_destination_name", ""))
		elif data["collector_state"] == "retreating":
			collector_route_label = "RETREAT TO BASE"
		elif data["collector_state"] == "unassigned":
			collector_route_label = "UNASSIGNED — PRESS U"
		collector_text = "   %s %d/%d" % [
			collector_route_label,
			int(data.get("collector_cargo", 0.0)),
			int(data.get("collector_capacity", 0.0)),
		]
	var research_text := ""
	if not str(data.get("research_id", "")).is_empty():
		var research_total: float = max(0.1, float(data.get("research_total", 0.0)))
		var research_progress: int = int(clamp(1.0 - float(data.get("research_remaining", 0.0)) / research_total, 0.0, 1.0) * 100.0)
		research_text = "   RESEARCH %d%%" % research_progress
	var queue_text := ""
	if data.has("queue"):
		var queue_items: Array = data["queue"]
		var queue_limit: int = simulation.get_limit_summary("player")["queue"]["max"]
		queue_text = "   QUEUE %d/%d" % [queue_items.size(), queue_limit]
		if not queue_items.is_empty():
			var next_job: Dictionary = queue_items[0]
			queue_text += " NEXT %s %ds" % [str(next_job.get("unit_type", "")).to_upper(), int(ceil(float(next_job.get("remaining", 0.0))))]
	var rally_text := ""
	if bool(data.get("rally_enabled", false)):
		var rally_mode := str(data.get("rally_mode", "ground"))
		if rally_mode == "control_point":
			var point_id := str(data.get("rally_point_id", ""))
			var point_name := str(simulation.control_points[point_id].get("display_name", point_id)) if simulation.control_points.has(point_id) else point_id
			rally_text = "   RALLY %s" % point_name.to_upper()
			if bool(data.get("rally_suspended", false)):
				rally_text += " (SUSPENDED)"
		else:
			rally_text = "   RALLY SET"
	if data.has("order"):
		return "HP %d/%d   ORDER %s%s%s%s%s%s" % [int(data["health"]), int(data["max_health"]), str(data["order"]).to_upper(), supply_text, collector_text, research_text, queue_text, rally_text]
	return "HP %d/%d   %s%s%s%s%s%s" % [int(data["health"]), int(data["max_health"]), "ONLINE" if data["complete"] else "BUILDING", supply_text, collector_text, research_text, queue_text, rally_text]


func _on_simulation_event(event_type: String, payload: Dictionary) -> void:
	if event_type == "UnitDamaged" or event_type == "BuildingDamaged":
		_spawn_damage_feedback(payload, event_type == "BuildingDamaged")
	elif event_type == "UnitDestroyed" or event_type == "BuildingDestroyed":
		_spawn_destruction_feedback(payload)
	if not status_label or not event_log_label:
		return
	var feedback_message: String = str(payload.get("message", payload.get("reason", "")))
	if not feedback_message.is_empty():
		status_label.text = feedback_message
	if event_type == "MatchWon" or event_type == "MatchLost":
		status_label.text = "[ %s ] %s" % ["VICTORY" if event_type == "MatchWon" else "DEFEAT", payload.get("message", "Match complete")]
		status_label.modulate = Color("#ffd36a") if event_type == "MatchWon" else Color("#ff7b86")
	var lines: PackedStringArray = event_log_label.text.split("\n")
	if not feedback_message.is_empty():
		lines.append("[%03d] %s" % [int(payload.get("tick", 0)), feedback_message])
	while lines.size() > 5:
		lines.remove_at(0)
	event_log_label.text = "EVENT LOG\n" + "\n".join(lines.slice(1))


func _spawn_damage_feedback(payload: Dictionary, building_hit: bool) -> void:
	var attacker_position: Vector3 = payload.get("attacker_position", payload.get("target_position", Vector3.ZERO))
	var target_position: Vector3 = payload.get("target_position", Vector3.ZERO)
	var effect_color := Color("#ffb347") if building_hit else Color("#ffd36a")
	_spawn_combat_tracer(attacker_position + Vector3.UP * 0.75, target_position + Vector3.UP * (1.0 if building_hit else 0.55), effect_color)
	var damage: int = int(round(float(payload.get("damage", 0.0))))
	_spawn_combat_impact(target_position + Vector3.UP * (1.0 if building_hit else 0.55), effect_color, "-%d" % damage)


func _spawn_combat_tracer(start: Vector3, finish: Vector3, color: Color) -> void:
	var effect := Node3D.new()
	combat_effect_sequence += 1
	effect.name = "CombatEffect_%03d" % combat_effect_sequence
	var beam_mesh := BoxMesh.new()
	beam_mesh.size = Vector3(0.075, 0.075, max(0.25, start.distance_to(finish)))
	var beam := MeshInstance3D.new()
	beam.mesh = beam_mesh
	beam.material_override = _material(Color(color.r, color.g, color.b, 0.9), 0.22, 0.35)
	effect.add_child(beam)
	effect.position = (start + finish) * 0.5
	add_child(effect)
	effect.look_at(finish, Vector3.UP)
	var tween := effect.create_tween()
	tween.tween_interval(0.1)
	tween.tween_callback(Callable(effect, "queue_free"))


func _spawn_combat_impact(position: Vector3, color: Color, label_text: String) -> void:
	var effect := Node3D.new()
	combat_effect_sequence += 1
	effect.name = "CombatEffect_%03d" % combat_effect_sequence
	effect.position = position
	var flash_mesh := SphereMesh.new()
	flash_mesh.radius = 0.25
	flash_mesh.height = 0.5
	flash_mesh.radial_segments = 12
	flash_mesh.rings = 6
	var flash := MeshInstance3D.new()
	flash.mesh = flash_mesh
	flash.material_override = _material(Color(color.r, color.g, color.b, 0.88), 0.18, 0.15)
	effect.add_child(flash)
	var label := Label3D.new()
	label.text = label_text
	label.position.y = 0.35
	label.font_size = 30
	label.modulate = color
	label.outline_size = 7
	label.outline_modulate = Color(0.01, 0.02, 0.04, 0.9)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	effect.add_child(label)
	add_child(effect)
	var tween := effect.create_tween()
	tween.set_parallel()
	tween.tween_property(effect, "scale", Vector3.ONE * 1.7, 0.28)
	tween.tween_property(effect, "position", effect.position + Vector3.UP * 0.8, 0.35)
	tween.set_parallel(false)
	tween.tween_callback(Callable(effect, "queue_free"))


func _spawn_destruction_feedback(payload: Dictionary) -> void:
	var effect := Node3D.new()
	combat_effect_sequence += 1
	effect.name = "CombatEffect_%03d" % combat_effect_sequence
	effect.position = payload.get("position", Vector3.ZERO) + Vector3.UP * 0.65
	var burst_mesh := SphereMesh.new()
	burst_mesh.radius = 0.45
	burst_mesh.height = 0.9
	burst_mesh.radial_segments = 14
	burst_mesh.rings = 7
	var burst := MeshInstance3D.new()
	burst.mesh = burst_mesh
	burst.material_override = _material(Color(1.0, 0.35, 0.12, 0.9), 0.18, 0.1)
	effect.add_child(burst)
	var label := Label3D.new()
	label.text = "DESTROYED"
	label.position.y = 0.7
	label.font_size = 30
	label.modulate = Color("#ff8066")
	label.outline_size = 8
	label.outline_modulate = Color(0.01, 0.02, 0.04, 0.9)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	effect.add_child(label)
	add_child(effect)
	var tween := effect.create_tween()
	tween.set_parallel()
	tween.tween_property(effect, "scale", Vector3.ONE * 2.4, 0.42)
	tween.tween_property(effect, "position", effect.position + Vector3.UP * 1.4, 0.48)
	tween.set_parallel(false)
	tween.tween_callback(Callable(effect, "queue_free"))


func _update_selection_marquee() -> void:
	var rectangle := Rect2(drag_start, drag_current - drag_start).abs()
	selection_marquee.position = rectangle.position
	selection_marquee.size = rectangle.size


func _pointer_over_ui() -> bool:
	return pointer_position.y < 184.0 or pointer_position.y > 605.0 or pointer_position.x > 1000.0


func _material(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	if color.a < 0.99:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = roughness
	material.metallic = metallic
	return material


func _emissive_material(color: Color, energy: float) -> StandardMaterial3D:
	var material := _material(color, 0.3, 0.1)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	return material


func _panel_style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	return style


func _label(text_value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label

