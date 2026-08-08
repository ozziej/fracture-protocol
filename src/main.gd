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

var credits_label: Label
var territory_label: Label
var supply_label: Label
var selected_label: Label
var status_label: Label
var event_log_label: Label
var build_button: Button
var queue_button: Button
var minimap


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
	_sync_views()
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
			KEY_E:
				camera_yaw = clamp(camera_yaw + deg_to_rad(8.0), -0.78, 0.78)
			KEY_R:
				camera_yaw = clamp(camera_yaw - deg_to_rad(8.0), -0.78, 0.78)
			KEY_H:
				_focus_selection()
			KEY_ESCAPE:
				_cancel_build_mode()
				attack_move_mode = false
				selected_ids.clear()
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
	var ground := MeshInstance3D.new()
	var ground_mesh := BoxMesh.new()
	ground_mesh.size = Vector3(120.0, 0.25, 80.0)
	ground.mesh = ground_mesh
	ground.position.y = -0.18
	ground.material_override = _material(Color("#0b222b"), 0.92, 0.05)
	add_child(ground)

	for x in range(-60, 61, 4):
		var line := MeshInstance3D.new()
		var line_mesh := BoxMesh.new()
		line_mesh.size = Vector3(0.035, 0.018, 80.0)
		line.mesh = line_mesh
		line.position = Vector3(float(x), -0.02, 0.0)
		line.material_override = _material(Color(0.13, 0.36, 0.4, 0.45), 1.0, 0.0)
		add_child(line)
	for z in range(-40, 41, 4):
		var line := MeshInstance3D.new()
		var line_mesh := BoxMesh.new()
		line_mesh.size = Vector3(120.0, 0.018, 0.035)
		line.mesh = line_mesh
		line.position = Vector3(0.0, -0.01, float(z))
		line.material_override = _material(Color(0.13, 0.36, 0.4, 0.45), 1.0, 0.0)
		add_child(line)

	_create_road(Vector3(0.0, 0.01, -1.0), Vector3(106.0, 0.03, 3.2))
	_create_road(Vector3(0.0, 0.01, -1.0), Vector3(3.2, 0.03, 68.0))
	_create_road(Vector3(-34.0, 0.01, 15.0), Vector3(20.0, 0.03, 2.6))
	_create_road(Vector3(34.0, 0.01, -15.0), Vector3(20.0, 0.03, 2.6))

	for obstacle in [
		{"position": Vector3(-7.0, 0.55, 15.0), "size": Vector3(8.0, 1.1, 2.0)},
		{"position": Vector3(10.0, 0.7, 12.0), "size": Vector3(3.0, 1.4, 8.0)},
		{"position": Vector3(-17.0, 0.45, -17.0), "size": Vector3(7.0, 0.9, 2.0)},
		{"position": Vector3(6.0, 0.6, -20.0), "size": Vector3(3.0, 1.2, 7.0)},
		{"position": Vector3(40.0, 0.35, 10.0), "size": Vector3(5.0, 0.7, 3.0)},
		{"position": Vector3(-39.0, 0.35, -8.0), "size": Vector3(5.0, 0.7, 3.0)},
	]:
		_create_obstacle(obstacle["position"], obstacle["size"])


func _create_road(position: Vector3, size: Vector3) -> void:
	var road := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	road.mesh = mesh
	road.position = position
	road.material_override = _material(Color("#163741"), 0.98, 0.08)
	add_child(road)


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
	top_panel.size = Vector2(780.0, 70.0)
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

	status_label = _label("Skirmish online. Secure the relay network.", 16, Color("#c3d8df"))
	status_label.position = Vector2(22.0, 99.0)
	status_label.size = Vector2(760.0, 32.0)
	root.add_child(status_label)

	var help := _label("WASD pan   H focus   F attack-move   X stop   Ctrl/Cmd+1-9 assign   1-9 recall   Q raider   B relay   Right-click order", 13, Color("#8ca9b5"))
	help.position = Vector2(22.0, 130.0)
	help.size = Vector2(1200.0, 24.0)
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
	bottom_panel.size = Vector2(980.0, 88.0)
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
	selected_label.custom_minimum_size = Vector2(350.0, 52.0)
	bottom_row.add_child(selected_label)

	build_button = Button.new()
	build_button.text = "DEPLOY RELAY [B]"
	build_button.custom_minimum_size = Vector2(190.0, 48.0)
	build_button.tooltip_text = "Place a Forward Relay near a connected friendly structure. Cost: 180 credits."
	build_button.pressed.connect(_toggle_build_mode)
	bottom_row.add_child(build_button)

	queue_button = Button.new()
	queue_button.text = "QUEUE RAIDER [Q]"
	queue_button.custom_minimum_size = Vector2(180.0, 48.0)
	queue_button.tooltip_text = "Queue a fast attack vehicle at the Assembly Bay. Cost: 105 credits."
	queue_button.pressed.connect(_queue_strider)
	bottom_row.add_child(queue_button)

	var note := _label("FIRST PASS\nGraybox skirmish", 13, Color("#7e9da7"))
	note.custom_minimum_size = Vector2(150.0, 52.0)
	bottom_row.add_child(note)

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
		if not clicked_id.is_empty() and simulation.units.has(clicked_id) and simulation.units[clicked_id]["team"] == "player":
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
	if not clicked_id.is_empty() and ((simulation.units.has(clicked_id) and simulation.units[clicked_id]["team"] == "enemy") or (simulation.buildings.has(clicked_id) and simulation.buildings[clicked_id]["team"] == "enemy")):
		simulation.issue_command("attack", "player", {"entity_ids": selected_ids, "target_id": clicked_id})
		attack_move_mode = false
	else:
		var destination := _screen_to_ground(screen_position)
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
	camera_target = Vector3(clamp(center.x, -36.0, 36.0), 0.0, clamp(center.z, -25.0, 25.0))
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
	return abs(position.x) <= MAP_HALF_WIDTH - 2.0 and abs(position.z) <= MAP_HALF_DEPTH - 2.0


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


func _queue_strider() -> void:
	var assembly_id := ""
	for building_id in simulation.buildings:
		var building: Dictionary = simulation.buildings[building_id]
		if building["team"] == "player" and building["kind"] == "assembly_bay":
			assembly_id = building_id
			break
	if assembly_id.is_empty():
		status_label.text = "No Assembly Bay available."
		return
	simulation.issue_command("produce", "player", {"building_id": assembly_id, "unit_type": "raider"})


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
	camera_target.x = clamp(camera_target.x, -36.0, 36.0)
	camera_target.z = clamp(camera_target.z, -25.0, 25.0)



func _update_camera() -> void:
	var offset := Vector3(sin(camera_yaw) * camera_distance, camera_distance * camera_pitch, cos(camera_yaw) * camera_distance)
	camera.global_position = camera_target + offset
	camera.look_at(camera_target, Vector3.UP)


func _sync_views() -> void:
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
		unit_views[entity_id].sync(state["units"][entity_id], selected_ids.has(entity_id))
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
	var label: Label3D = view.get_node("PointLabel")
	label.text = "%s %d%%" % [point["display_name"], abs(int(point["capture_progress"]))]
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


func _update_hud() -> void:
	if not simulation:
		return
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
	queue_button.disabled = simulation.player_credits < 105.0
	build_button.disabled = simulation.player_credits < 180.0 and build_mode.is_empty()
	if simulation.match_over:
		queue_button.disabled = true
		build_button.disabled = true
		_cancel_build_mode()

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
	if data.has("order"):
		return "HP %d/%d   ORDER %s%s" % [int(data["health"]), int(data["max_health"]), str(data["order"]).to_upper(), supply_text]
	return "HP %d/%d   %s%s" % [int(data["health"]), int(data["max_health"]), "ONLINE" if data["complete"] else "BUILDING", supply_text]


func _on_simulation_event(event_type: String, payload: Dictionary) -> void:
	if not status_label or not event_log_label:
		return
	if payload.has("message"):
		status_label.text = payload["message"]
	if event_type == "MatchWon" or event_type == "MatchLost":
		status_label.text = "[ %s ] %s" % ["VICTORY" if event_type == "MatchWon" else "DEFEAT", payload.get("message", "Match complete")]
		status_label.modulate = Color("#ffd36a") if event_type == "MatchWon" else Color("#ff7b86")
	var lines: PackedStringArray = event_log_label.text.split("\n")
	if payload.has("message"):
		lines.append("[%03d] %s" % [int(payload.get("tick", 0)), payload["message"]])
	while lines.size() > 5:
		lines.remove_at(0)
	event_log_label.text = "EVENT LOG\n" + "\n".join(lines.slice(1))


func _update_selection_marquee() -> void:
	var rectangle := Rect2(drag_start, drag_current - drag_start).abs()
	selection_marquee.position = rectangle.position
	selection_marquee.size = rectangle.size


func _pointer_over_ui() -> bool:
	return pointer_position.y < 165.0 or pointer_position.y > 605.0 or pointer_position.x > 1000.0


func _material(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	if color.a < 0.99:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = roughness
	material.metallic = metallic
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

