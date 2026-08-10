extends Node3D

const SimulationScript = preload("res://src/rts_simulation.gd")
const UnitViewScript = preload("res://src/rts_unit_view.gd")
const BuildingViewScript = preload("res://src/rts_building_view.gd")
const MinimapScript = preload("res://src/minimap.gd")
const CampaignProgressScript = preload("res://src/campaign_progress.gd")
const WorldBuilderScript = preload("res://src/presentation/rts_world_builder.gd")
const CombatEffectsScript = preload("res://src/presentation/rts_combat_effects.gd")
const WorldViewSynchronizerScript = preload("res://src/presentation/rts_world_view_synchronizer.gd")

const MAP_HALF_WIDTH := 80.0
const MAP_HALF_DEPTH := 55.0
const CAMERA_TARGET_X_FACTOR := 0.78
const CAMERA_TARGET_Z_FACTOR := 0.78
const AI_DIFFICULTIES := ["standard", "aggressive", "defensive"]

var simulation
var campaign_progress
var camera: Camera3D
var world_shell: Node3D
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
var selected_resource_id := ""
var control_groups: Dictionary = {}

var dragging := false
var drag_start := Vector2.ZERO
var drag_current := Vector2.ZERO
var selection_marquee: ColorRect
var build_mode := ""
var attack_move_mode := false
var patrol_mode := false
var build_ghost: Node3D
var build_ghost_mesh: MeshInstance3D
var build_ghost_label: Label3D
var build_ghost_valid := false
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
var mission_one_button: Button
var mission_two_button: Button
var start_menu_overlay: ColorRect
var start_menu_panel: PanelContainer
var start_menu_briefing_label: Label
var start_menu_visible := true
var combat_effect_sequence := 0
var combat_effects
var objective_target_point_id := ""
var build_source_id := ""
var context_actions: Array = []
var queue_panel: PanelContainer
var queue_title_label: Label
var queue_buttons: Array[Button] = []
var queue_building_id := ""


func _ready() -> void:
	_build_environment()
	_build_camera()
	campaign_progress = CampaignProgressScript.new()
	combat_effects = CombatEffectsScript.new()
	simulation = SimulationScript.new()
	add_child(simulation)
	simulation.simulation_event.connect(_on_simulation_event)
	simulation.start_match()
	camera_target = _starting_camera_target()
	_build_world_shell()
	_build_ui()
	_sync_views()
	_update_camera()
	_update_hud()


func _process(delta: float) -> void:
	_process_camera_input(delta)
	if not start_menu_visible:
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
			_issue_context_order(event.position, event.shift_pressed)
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
			KEY_P:
				_toggle_patrol_mode()
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
			KEY_F1:
				_load_campaign_level("relay_divide")
			KEY_F2:
				_load_campaign_level("relay_crossroads")
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
				patrol_mode = false
				selected_ids.clear()
				selected_resource_id = ""
				_update_selected_visuals()
			KEY_SPACE:
				status_label.text = "Simulation is live — orders resolve on the fixed tick."


func _build_environment() -> void:
	WorldBuilderScript.build_environment(self)


func _build_camera() -> void:
	camera = WorldBuilderScript.build_camera(self)


func _build_world_shell() -> void:
	if world_shell and is_instance_valid(world_shell):
		world_shell.free()
	world_shell = Node3D.new()
	world_shell.name = "AuthoredWorldShell"
	add_child(world_shell)
	WorldBuilderScript.build_world_shell(world_shell, simulation)


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

	objective_label = _label("OBJECTIVE", 15, Color("#ffd36a"))
	objective_label.position = Vector2(22.0, 98.0)
	objective_label.size = Vector2(1210.0, 25.0)
	root.add_child(objective_label)

	status_label = _label("Awaiting orders.", 16, Color("#c3d8df"))
	status_label.position = Vector2(22.0, 123.0)
	status_label.size = Vector2(980.0, 26.0)
	root.add_child(status_label)

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
	build_button.pressed.connect(_run_context_action.bind(0))
	bottom_row.add_child(build_button)

	queue_button = Button.new()
	queue_button.text = "QUEUE RAIDER [Q]"
	queue_button.custom_minimum_size = Vector2(135.0, 48.0)
	queue_button.tooltip_text = "Queue a fast attack vehicle at the Assembly Bay. Cost: 105 credits."
	queue_button.pressed.connect(_run_context_action.bind(1))
	bottom_row.add_child(queue_button)

	heavy_queue_button = Button.new()
	heavy_queue_button.text = "QUEUE BULWARK [V]"
	heavy_queue_button.custom_minimum_size = Vector2(145.0, 48.0)
	heavy_queue_button.tooltip_text = "Queue a heavy assault vehicle after Advanced Targeting research. Cost: 160 credits."
	heavy_queue_button.pressed.connect(_run_context_action.bind(2))
	bottom_row.add_child(heavy_queue_button)

	research_button = Button.new()
	research_button.text = "RESEARCH TARGETING [T]"
	research_button.custom_minimum_size = Vector2(160.0, 48.0)
	research_button.tooltip_text = "Research Advanced Targeting at the Assembly Bay. Cost: 300 credits."
	research_button.pressed.connect(_run_context_action.bind(3))
	bottom_row.add_child(research_button)

	repair_button = Button.new()
	repair_button.text = "REPAIR [Y]"
	repair_button.custom_minimum_size = Vector2(100.0, 48.0)
	repair_button.tooltip_text = "Repair selected units near a repair station or selected structures. Cost: 30/45 credits."
	repair_button.pressed.connect(_run_context_action.bind(4))
	bottom_row.add_child(repair_button)

	collector_button = Button.new()
	collector_button.text = "QUEUE COLLECTOR [C]"
	collector_button.custom_minimum_size = Vector2(135.0, 48.0)
	collector_button.tooltip_text = "Queue a Collector at the Assembly Bay. Select one and press U to assign its source and Resource Processor. Cost: 115 credits."
	collector_button.pressed.connect(_run_context_action.bind(5))
	bottom_row.add_child(collector_button)

	queue_panel = PanelContainer.new()
	queue_panel.name = "ProductionQueuePanel"
	queue_panel.position = Vector2(420.0, 498.0)
	queue_panel.size = Vector2(600.0, 108.0)
	queue_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.025, 0.075, 0.1, 0.96), Color(0.96, 0.68, 0.28, 0.72)))
	var queue_margin := MarginContainer.new()
	queue_margin.add_theme_constant_override("margin_left", 10)
	queue_margin.add_theme_constant_override("margin_right", 10)
	queue_margin.add_theme_constant_override("margin_top", 7)
	queue_margin.add_theme_constant_override("margin_bottom", 7)
	queue_panel.add_child(queue_margin)
	var queue_column := VBoxContainer.new()
	queue_column.add_theme_constant_override("separation", 4)
	queue_margin.add_child(queue_column)
	queue_title_label = _label("PRODUCTION QUEUE — click a job to cancel and refund", 11, Color("#ffd36a"))
	queue_column.add_child(queue_title_label)
	var queue_row := HBoxContainer.new()
	queue_row.add_theme_constant_override("separation", 5)
	queue_column.add_child(queue_row)
	for queue_index in range(5):
		var queue_button := Button.new()
		queue_button.custom_minimum_size = Vector2(108.0, 55.0)
		queue_button.visible = false
		queue_button.pressed.connect(_cancel_queue_slot.bind(queue_index))
		queue_row.add_child(queue_button)
		queue_buttons.append(queue_button)
	root.add_child(queue_panel)
	queue_panel.visible = false

	minimap = MinimapScript.new()
	minimap.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	minimap.position = Vector2(-260.0, -220.0)
	minimap.size = Vector2(242.0, 106.0)
	var bounds: Vector2 = simulation.get_level_bounds()
	minimap.map_bounds = Rect2(-bounds.x, -bounds.y, bounds.x * 2.0, bounds.y * 2.0)
	root.add_child(minimap)

	selection_marquee = ColorRect.new()
	selection_marquee.color = Color(0.25, 0.88, 0.98, 0.13)
	selection_marquee.mouse_filter = Control.MOUSE_FILTER_IGNORE
	selection_marquee.visible = false
	root.add_child(selection_marquee)
	_build_campaign_start_menu(root)


func _build_campaign_start_menu(root: Control) -> void:
	start_menu_overlay = ColorRect.new()
	start_menu_overlay.name = "CampaignStartMenuOverlay"
	start_menu_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	start_menu_overlay.color = Color(0.008, 0.025, 0.04, 0.92)
	start_menu_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(start_menu_overlay)

	start_menu_panel = PanelContainer.new()
	start_menu_panel.name = "CampaignStartMenu"
	start_menu_panel.position = Vector2(240.0, 118.0)
	start_menu_panel.size = Vector2(800.0, 470.0)
	start_menu_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.025, 0.075, 0.1, 0.98), Color(0.18, 0.7, 0.78, 0.8)))
	start_menu_overlay.add_child(start_menu_panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	start_menu_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	var title := _label("CAMPAIGN DEPLOYMENT", 24, Color("#d6fbff"))
	column.add_child(title)
	var subtitle := _label("FRACTURE PROTOCOL  //  SELECT A MISSION", 13, Color("#8cebf3"))
	column.add_child(subtitle)
	start_menu_briefing_label = _label("", 14, Color("#c3d8df"))
	start_menu_briefing_label.custom_minimum_size = Vector2(0.0, 54.0)
	start_menu_briefing_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(start_menu_briefing_label)
	mission_one_button = Button.new()
	mission_one_button.name = "LevelOneButton"
	mission_one_button.custom_minimum_size = Vector2(0.0, 58.0)
	mission_one_button.text = "LEVEL 1 — RELAY DIVIDE"
	mission_one_button.pressed.connect(_load_campaign_level.bind("relay_divide"))
	column.add_child(mission_one_button)
	mission_two_button = Button.new()
	mission_two_button.name = "LevelTwoButton"
	mission_two_button.custom_minimum_size = Vector2(0.0, 58.0)
	mission_two_button.text = "LEVEL 2 — RELAY CROSSROADS"
	mission_two_button.tooltip_text = "Complete Relay Divide to unlock this mission."
	mission_two_button.pressed.connect(_load_campaign_level.bind("relay_crossroads"))
	column.add_child(mission_two_button)
	var footer := _label("The opponent tactic is authored by the mission and adapts to battlefield pressure automatically.", 12, Color("#8ca9b5"))
	footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(footer)


func _finish_left_click() -> void:
	if collector_assignment_mode:
		_handle_collector_assignment_click()
		return
	if build_mode != "":
		var build_position := _screen_to_ground(pointer_position)
		var placement: Dictionary = simulation.get_build_placement_status("player", build_mode, build_position, build_source_id)
		if bool(placement.get("valid", false)):
			simulation.issue_command("build", "player", {"building_type": build_mode, "position": build_position, "source_building_id": build_source_id})
			_cancel_build_mode()
		else:
			status_label.text = "CANNOT PLACE — %s" % str(placement.get("reason", "Invalid placement."))
			_update_build_ghost()
		return
	var drag_rect := Rect2(drag_start, drag_current - drag_start).abs()
	if drag_rect.size.length() < 12.0:
		var clicked_resource_id := _resource_node_at_screen(pointer_position)
		if not clicked_resource_id.is_empty():
			selected_ids.clear()
			selected_resource_id = clicked_resource_id
			status_label.text = "%s selected — inspect its finite reserve below." % simulation.resource_nodes[clicked_resource_id]["display_name"]
			_update_selected_visuals()
			return
		var clicked_id := _entity_at_screen(pointer_position, true)
		selected_resource_id = ""
		selected_ids.clear()
		if not clicked_id.is_empty() and ((simulation.units.has(clicked_id) and simulation.units[clicked_id]["team"] == "player") or (simulation.buildings.has(clicked_id) and simulation.buildings[clicked_id]["team"] == "player")):
			selected_ids.append(clicked_id)
	else:
		selected_resource_id = ""
		selected_ids.clear()
		for entity_id in simulation.units:
			var unit: Dictionary = simulation.units[entity_id]
			if unit["team"] != "player":
				continue
			var projected := camera.unproject_position(unit["position"] + Vector3.UP * 0.6)
			if drag_rect.has_point(projected):
				selected_ids.append(entity_id)
	_update_selected_visuals()


func _issue_context_order(screen_position: Vector2, queue_order := false) -> void:
	if selected_ids.is_empty():
		return
	if patrol_mode:
		var patrol_destination := _screen_to_ground(screen_position)
		if _is_inside_map(patrol_destination):
			simulation.issue_command("patrol", "player", {"entity_ids": selected_ids, "position": patrol_destination})
			patrol_mode = false
			status_label.text = "Patrol route queued — units will shuttle between their current position and the destination."
		return
	var clicked_id := _entity_at_screen(screen_position, false)
	var resource_id := _resource_node_at_screen(screen_position)
	var collector_ids: Array = []
	for entity_id in selected_ids:
		if simulation.units.has(entity_id) and simulation.units[entity_id]["team"] == "player" and simulation.units[entity_id]["kind"] == "collector":
			collector_ids.append(entity_id)
	if not resource_id.is_empty() and not collector_ids.is_empty() and collector_ids.size() == selected_ids.size():
		var destination_id := _nearest_friendly_refinery(resource_id)
		if destination_id.is_empty():
			status_label.text = "Build a completed Resource Processor before assigning Collectors."
			return
		for collector_id in collector_ids:
			simulation.issue_command("assign_collector", "player", {"collector_id": collector_id, "source_id": resource_id, "destination_id": destination_id})
		status_label.text = "Collector route queued to %s." % simulation.resource_nodes[resource_id]["display_name"]
		return
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
		var command_type := "queue_move" if queue_order else "move"
		var command_payload := {"entity_ids": selected_ids, "position": destination}
		if attack_move_mode:
			if queue_order:
				command_payload["attack_move"] = true
			else:
				command_type = "attack_move"
			simulation.issue_command(command_type, "player", command_payload)
			attack_move_mode = false
		else:
			simulation.issue_command(command_type, "player", command_payload)
		if queue_order:
			status_label.text = "Waypoint queued for the selected force."

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
	camera_target = Vector3(clamp(center.x, -bounds.x * CAMERA_TARGET_X_FACTOR, bounds.x * CAMERA_TARGET_X_FACTOR), 0.0, clamp(center.z, -bounds.y * CAMERA_TARGET_Z_FACTOR, bounds.y * CAMERA_TARGET_Z_FACTOR))
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
	patrol_mode = false
	attack_move_mode = true
	status_label.text = "ATTACK-MOVE MODE — right-click a destination. Units engage enemies on the route."


func _toggle_patrol_mode() -> void:
	var combat_unit_count := 0
	for entity_id in selected_ids:
		if simulation.units.has(entity_id) and simulation.units[entity_id]["team"] == "player" and simulation.units[entity_id]["kind"] != "collector":
			combat_unit_count += 1
	if combat_unit_count == 0:
		status_label.text = "Select one or more combat units before issuing a patrol order."
		return
	if patrol_mode:
		patrol_mode = false
		status_label.text = "Patrol mode cancelled."
		return
	_cancel_build_mode()
	_cancel_collector_assignment(false)
	attack_move_mode = false
	patrol_mode = true
	status_label.text = "PATROL MODE — right-click a destination. Units will shuttle between here and there."


func _stop_selected_units() -> void:
	if selected_ids.is_empty():
		return
	attack_move_mode = false
	patrol_mode = false
	simulation.issue_command("stop", "player", {"entity_ids": selected_ids})
	status_label.text = "Stop order queued."


func _toggle_build_mode() -> void:
	if build_mode == "relay":
		_cancel_build_mode()
		return
	attack_move_mode = false
	patrol_mode = false
	build_mode = "relay"
	status_label.text = "BUILD MODE — click near your network to place a Forward Relay. Right-click cancels."
	_create_build_ghost()


func _cancel_build_mode() -> void:
	build_mode = ""
	build_source_id = ""
	build_ghost_valid = false
	build_ghost_mesh = null
	build_ghost_label = null
	if build_ghost:
		build_ghost.queue_free()
		build_ghost = null
	if status_label and simulation and not simulation.match_over:
		status_label.text = "Skirmish online. Secure the relay network."
func _create_build_ghost() -> void:
	if build_ghost:
		build_ghost.queue_free()
	build_ghost = Node3D.new()
	build_ghost.name = "BuildPlacementPreview"
	var footprint := Vector3(2.5, 2.2, 2.5)
	if build_mode == "assembly_bay":
		footprint = Vector3(3.5, 2.0, 3.5)
	elif build_mode == "tech_centre":
		footprint = Vector3(3.2, 2.4, 3.2)
	elif build_mode == "refinery":
		footprint = Vector3(3.5, 1.8, 3.5)
	elif build_mode == "storage_silo":
		footprint = Vector3(2.4, 2.8, 2.4)
	var mesh := MeshInstance3D.new()
	mesh.name = "PreviewMesh"
	var box := BoxMesh.new()
	box.size = footprint
	mesh.mesh = box
	mesh.position.y = footprint.y * 0.5
	mesh.material_override = _material(Color(0.18, 0.86, 0.88, 0.55), 0.65, 0.1)
	build_ghost.add_child(mesh)
	var label := Label3D.new()
	label.name = "PreviewLabel"
	label.text = "PLACE %s\nLEFT-CLICK TO BUILD" % build_mode.replace("_", " ").to_upper()
	label.position.y = footprint.y + 1.1
	label.font_size = 24
	label.modulate = Color("#d9fbff")
	label.outline_size = 7
	label.outline_modulate = Color(0.01, 0.02, 0.04, 0.9)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	build_ghost.add_child(label)
	build_ghost_mesh = mesh
	build_ghost_label = label
	if not build_source_id.is_empty() and simulation.buildings.has(build_source_id):
		var source_position: Vector3 = simulation.buildings[build_source_id]["position"]
		build_ghost.position = source_position + Vector3(6.0, 0.0, 0.0)
	add_child(build_ghost)


func _update_build_ghost() -> void:
	if not build_ghost:
		return
	var position := _screen_to_ground(pointer_position)
	build_ghost.position = Vector3(position.x, 0.0, position.z)
	var placement: Dictionary = simulation.get_build_placement_status("player", build_mode, position, build_source_id)
	build_ghost_valid = bool(placement.get("valid", false))
	var preview_color := Color(0.18, 0.86, 0.88, 0.55) if build_ghost_valid else Color(0.96, 0.18, 0.24, 0.65)
	if build_ghost_mesh:
		build_ghost_mesh.material_override = _material(preview_color, 0.65, 0.1)
	if build_ghost_label:
		if build_ghost_valid:
			build_ghost_label.text = "PLACE %s\nLEFT-CLICK TO BUILD" % build_mode.replace("_", " ").to_upper()
		else:
			build_ghost_label.text = "INVALID PLACEMENT\n%s" % str(placement.get("reason", "Cannot build here."))
		build_ghost_label.modulate = Color("#d9fbff") if build_ghost_valid else Color("#ff9ba3")


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
	var refinery_id := _find_player_building("refinery")
	if refinery_id.is_empty():
		status_label.text = "Build a Resource Processor before queuing a Collector."
		return
	simulation.issue_command("produce", "player", {"building_id": refinery_id, "unit_type": "collector"})

func _begin_collector_assignment() -> void:
	var collector_id := _selected_collector_id()
	if collector_id.is_empty():
		status_label.text = "Select exactly one Collector before assigning a route."
		return
	_cancel_build_mode()
	attack_move_mode = false
	patrol_mode = false
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
		if bool(simulation.resource_nodes[source_id].get("depleted", false)) or float(simulation.resource_nodes[source_id].get("remaining", 0.0)) <= 0.01:
			status_label.text = "%s is depleted — choose another Energy Field." % simulation.resource_nodes[source_id]["display_name"]
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

func _nearest_friendly_refinery(resource_id: String) -> String:
	if not simulation.resource_nodes.has(resource_id):
		return ""
	var source_position: Vector3 = simulation.resource_nodes[resource_id]["position"]
	var closest_id: String = ""
	var closest_distance: float = INF
	for building_id in simulation.buildings:
		var building: Dictionary = simulation.buildings[building_id]
		if building["team"] == "player" and building["kind"] == "refinery" and building["complete"]:
			var distance: float = (building["position"] as Vector3).distance_to(source_position)
			if distance < closest_distance:
				closest_distance = distance
				closest_id = building_id
	return closest_id


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
func _begin_build_from_selection(building_type: String) -> void:
	if selected_ids.size() != 1 or not simulation.buildings.has(selected_ids[0]):
		status_label.text = "Select the construction source first."
		return
	var source_id := str(selected_ids[0])
	var source: Dictionary = simulation.buildings[source_id]
	if source["team"] != "player" or not source["complete"]:
		status_label.text = "Select a completed friendly construction source."
		return
	build_source_id = source_id
	build_mode = building_type
	attack_move_mode = false
	patrol_mode = false
	_create_build_ghost()
	var display_name := building_type.replace("_", " ").to_upper()
	status_label.text = "PLACE %s — move the preview near your base, then LEFT-CLICK. RIGHT-CLICK cancels." % display_name
	status_label.text = "BUILD %s — click a valid placement." % building_type.replace("_", " ").to_upper()


func _run_context_action(slot: int) -> void:
	if slot < 0 or slot >= context_actions.size():
		return
	var action := str(context_actions[slot])
	if action.begins_with("build:"):
		_begin_build_from_selection(action.trim_prefix("build:"))
	elif action.begins_with("produce:") and selected_ids.size() == 1:
		simulation.issue_command("produce", "player", {"building_id": selected_ids[0], "unit_type": action.trim_prefix("produce:")})
	elif action == "research" and selected_ids.size() == 1:
		simulation.issue_command("research", "player", {"building_id": selected_ids[0], "technology_id": "advanced_targeting"})
	elif action == "upgrade" and selected_ids.size() == 1:
		simulation.issue_command("upgrade", "player", {"building_id": selected_ids[0]})
	elif action == "collector_route":
		_begin_collector_assignment()
	elif action == "repair":
		_repair_selected()


func _queue_strider() -> void:
	var assembly_id := _find_player_assembly_bay()
	if assembly_id.is_empty():
		status_label.text = "Build an Assembly Bay before queuing Rangers."
		return
	simulation.issue_command("produce", "player", {"building_id": assembly_id, "unit_type": "ranger"})

func _queue_bulwark() -> void:
	var assembly_id := _find_player_assembly_bay()
	if assembly_id.is_empty():
		status_label.text = "No Assembly Bay available."
		return
	simulation.issue_command("produce", "player", {"building_id": assembly_id, "unit_type": "bulwark"})


func _research_advanced_targeting() -> void:
	var tech_centre_id := _find_player_building("tech_centre")
	if tech_centre_id.is_empty():
		status_label.text = "Build a Tech Centre before researching Advanced Targeting."
		return
	simulation.issue_command("research", "player", {"building_id": tech_centre_id, "technology_id": "advanced_targeting"})
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
	camera_target.x = clamp(camera_target.x, -bounds.x * CAMERA_TARGET_X_FACTOR, bounds.x * CAMERA_TARGET_X_FACTOR)
	camera_target.z = clamp(camera_target.z, -bounds.y * CAMERA_TARGET_Z_FACTOR, bounds.y * CAMERA_TARGET_Z_FACTOR)



func _update_camera() -> void:
	var offset := Vector3(sin(camera_yaw) * camera_distance, camera_distance * camera_pitch, cos(camera_yaw) * camera_distance)
	camera.global_position = camera_target + offset
	camera.look_at(camera_target, Vector3.UP)


func _sync_views(frame_delta: float = 0.0) -> void:
	var state: Dictionary = simulation.get_state()
	for selected_id in selected_ids.duplicate():
		if not state["units"].has(selected_id) and not state["buildings"].has(selected_id):
			selected_ids.erase(selected_id)
	if not state["resource_nodes"].has(selected_resource_id):
		selected_resource_id = ""
	WorldViewSynchronizerScript.sync(self, state, selected_ids, unit_views, building_views, control_views, resource_views, selected_resource_id, objective_target_point_id, minimap, frame_delta)


func _create_control_view(point: Dictionary) -> Node3D:
	return WorldViewSynchronizerScript.create_control_view(self, point)


func _update_control_view(view: Node3D, point: Dictionary) -> void:
	WorldViewSynchronizerScript.update_control_view(view, point, objective_target_point_id)


func _create_resource_view(resource: Dictionary) -> Node3D:
	return WorldViewSynchronizerScript.create_resource_view(self, resource)


func _update_selected_visuals() -> void:
	for entity_id in unit_views:
		unit_views[entity_id].selection_disc.visible = selected_ids.has(entity_id)
	for entity_id in building_views:
		building_views[entity_id].selection_disc.visible = selected_ids.has(entity_id)


func _restart_match() -> void:
	_cancel_build_mode()
	_cancel_collector_assignment(false)
	attack_move_mode = false
	patrol_mode = false
	selected_ids.clear()
	selected_resource_id = ""
	control_groups.clear()
	event_log_label.text = "EVENT LOG\nAwaiting orders..."
	status_label.modulate = Color("#c3d8df")
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
	camera_target = _starting_camera_target()
	_update_selected_visuals()
	_sync_views()
	_update_hud()


func _load_campaign_level(level_id: String) -> void:
	if campaign_progress and not campaign_progress.is_unlocked(level_id):
		status_label.text = "Complete Level 1 to unlock Level 2."
		return
	_cancel_build_mode()
	_cancel_collector_assignment(false)
	attack_move_mode = false
	patrol_mode = false
	selected_ids.clear()
	control_groups.clear()
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
	simulation.start_match(level_id)
	_set_start_menu_visible(false)
	camera_target = _starting_camera_target()
	_update_camera()
	_build_world_shell()
	if minimap:
		var bounds: Vector2 = simulation.get_level_bounds()
		minimap.map_bounds = Rect2(-bounds.x, -bounds.y, bounds.x * 2.0, bounds.y * 2.0)
	_update_selected_visuals()
	_sync_views()
	_update_hud()


func _set_start_menu_visible(visible: bool) -> void:
	start_menu_visible = visible
	if start_menu_overlay:
		start_menu_overlay.visible = visible
	if start_menu_panel:
		start_menu_panel.visible = visible
	if visible and status_label and simulation and not simulation.match_over:
		status_label.text = "Select a mission to begin deployment."

func _find_player_building(kind: String) -> String:
	for building_id in simulation.buildings:
		var building: Dictionary = simulation.buildings[building_id]
		if building["team"] == "player" and building["kind"] == kind:
			return building_id
	return ""


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


func _starting_camera_target() -> Vector3:
	for building_id in simulation.buildings:
		var building: Dictionary = simulation.buildings[building_id]
		if building["team"] == "player" and building["kind"] == "command_hub":
			var bounds: Vector2 = simulation.get_level_bounds()
			var position: Vector3 = building["position"]
			return Vector3(clamp(position.x, -bounds.x * CAMERA_TARGET_X_FACTOR, bounds.x * CAMERA_TARGET_X_FACTOR), 0.0, clamp(position.z, -bounds.y * CAMERA_TARGET_Z_FACTOR, bounds.y * CAMERA_TARGET_Z_FACTOR))
	return Vector3.ZERO


func _mission_text(key: String, values: Dictionary = {}) -> String:
	var text := str(simulation.get_level_objective_text().get(key, ""))
	for replacement_key in values:
		text = text.replace("{%s}" % str(replacement_key), str(values[replacement_key]))
	return text


func _set_objective(key: String, values: Dictionary = {}, target_point_id := "") -> void:
	objective_target_point_id = target_point_id
	var text := _mission_text(key, values)
	objective_label.text = "OBJECTIVE: %s" % text if not text.is_empty() else "OBJECTIVE"


func _update_objective() -> void:
	if not objective_label or not simulation:
		return
	if simulation.match_over:
		objective_target_point_id = ""
		objective_label.text = "OBJECTIVE COMPLETE — %s" % _mission_text("match_complete") if simulation.match_winner == "player" else "OBJECTIVE FAILED"
		return
	if _find_player_building("refinery").is_empty():
		_set_objective("build_processor")
		return
	var collector_id := _find_player_collector()
	if collector_id.is_empty():
		_set_objective("collector_missing")
		return
	var collector: Dictionary = simulation.units[collector_id]
	if str(collector.get("collector_state", "")) == "unassigned":
		_set_objective("collector_unassigned")
		return
	if not _has_player_event("ResourceDelivered"):
		_set_objective("collector_delivery")
		return
	if _find_player_building("assembly_bay").is_empty():
		_set_objective("build_assembly")
		return
	var objectives: Dictionary = simulation.get_level_objectives()
	var staging_point_id := str(objectives.get("first_staging_point_id", ""))
	if not staging_point_id.is_empty() and simulation.control_points.has(staging_point_id) and not _has_player_staging_rally(staging_point_id):
		var staging_point: Dictionary = simulation.control_points[staging_point_id]
		if not bool(staging_point.get("staging_active", false)) or staging_point["owner"] != "player":
			_set_objective("staging_secure", {"point": staging_point["display_name"]}, staging_point_id)
		else:
			_set_objective("staging_rally", {"point": staging_point["display_name"]}, staging_point_id)
		return
	if _find_player_building("tech_centre").is_empty():
		_set_objective("build_tech")
		return
	var research_status: Dictionary = simulation.get_research_status("player")
	if not simulation.is_technology_unlocked("player", "advanced_targeting"):
		if not str(research_status.get("active_id", "")).is_empty():
			_set_objective("research_active")
		else:
			_set_objective("research_available")
		return
	var has_bulwark := false
	for entity_id in simulation.units:
		var unit: Dictionary = simulation.units[entity_id]
		if unit["team"] == "player" and unit["kind"] == "bulwark":
			has_bulwark = true
			break
	if not has_bulwark:
		_set_objective("bulwark")
	else:
		_set_objective("destroy_hq")
func _update_hud() -> void:
	if not simulation:
		return
	_update_objective()
	credits_label.text = "CREDITS %03d" % int(simulation.player_credits)
	var territory: Dictionary = simulation.get_territory_summary()
	territory_label.text = "TERRITORY %d/%d  +%dC/S" % [territory["player"], territory["total"], int(territory.get("player_income_per_second", 0.0))]
	territory_label.tooltip_text = _territory_tooltip(territory)
	var supply: Dictionary = simulation.get_supply_summary("player")
	var unsupplied_units: int = int(supply["unsupplied_units"])
	var supply_state := "CONNECTED"
	if unsupplied_units > 0:
		supply_state = "%d UNSUPPLIED" % unsupplied_units
	supply_label.text = "SUPPLY %s" % supply_state
	supply_label.modulate = Color("#ffbf6a") if unsupplied_units > 0 else Color("#7cf1ad")
	supply_label.tooltip_text = "Connected units are within the Hub, Relay, or connected forward-base network. Unsupplied units move and fire at reduced effectiveness."
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
	elif not active_research_id.is_empty():
		var research_total: float = max(0.1, float(research_status.get("total", 0.0)))
		var research_progress: int = int(clamp(1.0 - float(research_status.get("remaining", 0.0)) / research_total, 0.0, 1.0) * 100.0)
		technology_label.text = "TECH %d%%" % research_progress
		technology_label.modulate = Color("#ffd36a")
	else:
		technology_label.text = "TECH LOCKED"
		technology_label.modulate = Color("#ffbf6a")
	if mission_one_button:
		mission_one_button.disabled = false
	if mission_two_button:
		var level_two_unlocked: bool = campaign_progress == null or campaign_progress.is_unlocked("relay_crossroads")
		mission_two_button.disabled = not level_two_unlocked
		mission_two_button.tooltip_text = "Deploy Relay Crossroads" if level_two_unlocked else "Complete Relay Divide to unlock this mission."
	if start_menu_briefing_label:
		start_menu_briefing_label.text = simulation.get_level_briefing()
	if simulation.match_over:
		_cancel_build_mode()
		_cancel_collector_assignment(false)

	var selected_text := "NO SELECTION\nSelect units, a structure, or an Energy Field"
	if not selected_resource_id.is_empty() and simulation.resource_nodes.has(selected_resource_id):
		var resource_summary: Dictionary = simulation.get_resource_summary(selected_resource_id)
		var resource_state := "DEPLETED" if bool(resource_summary.get("depleted", false)) else "%d%% REMAINING" % int(float(resource_summary.get("percent_remaining", 0.0)) * 100.0)
		selected_text = "%s\nENERGY %d / %d   %s" % [str(resource_summary.get("display_name", "ENERGY FIELD")).to_upper(), int(resource_summary.get("remaining", 0.0)), int(resource_summary.get("initial_remaining", 0.0)), resource_state]
	elif not selected_ids.is_empty():
		var first_id: String = selected_ids[0]
		var selected_data: Dictionary = simulation.units.get(first_id, simulation.buildings.get(first_id, {}))
		if not selected_data.is_empty():
			selected_text = "%s  x%d\n%s" % [selected_data["display_name"].to_upper(), selected_ids.size(), _selection_detail(selected_data)]
	selected_label.text = selected_text
	_update_context_cards()
	_update_production_queue_ui()


func _territory_tooltip(territory: Dictionary) -> String:
	var lines: PackedStringArray = []
	lines.append("Owned territory income: +%d credits/sec" % int(territory.get("player_income_per_second", 0.0)))
	var supply_bonus := float(territory.get("player_supply_link_bonus", 0.0))
	if supply_bonus > 0.0:
		lines.append("Network Hub extension: +%d supply-link range" % int(supply_bonus))
	var staging_sites := int(territory.get("player_staging_sites", 0))
	if staging_sites > 0:
		lines.append("Active staging sites: %d — repair and rally available" % staging_sites)
	if lines.size() == 1:
		lines.append("Capture a point to unlock its authored strategic role.")
	return "\n".join(lines)


func _on_ai_difficulty_selected(index: int) -> void:
	if index < 0 or index >= AI_DIFFICULTIES.size() or not simulation:
		return
	var difficulty_id: String = AI_DIFFICULTIES[index]
	simulation.set_ai_difficulty(difficulty_id)
	if status_label and not simulation.match_over:
		status_label.text = "AI difficulty set to %s; its policy will adapt on the next decision." % difficulty_id.capitalize()


func _find_queue_building_for_ui() -> String:
	if selected_ids.size() == 1:
		var selected_id := str(selected_ids[0])
		if simulation.buildings.has(selected_id):
			var selected_building: Dictionary = simulation.buildings[selected_id]
			if selected_building["team"] == "player" and not selected_building.get("queue", []).is_empty():
				return selected_id
	for building_id in simulation.buildings:
		var building: Dictionary = simulation.buildings[building_id]
		if building["team"] == "player" and not building.get("queue", []).is_empty():
			return str(building_id)
	return ""


func _update_production_queue_ui() -> void:
	if not queue_panel:
		return
	queue_building_id = _find_queue_building_for_ui()
	if queue_building_id.is_empty() or not simulation.buildings.has(queue_building_id):
		queue_panel.visible = false
		for button in queue_buttons:
			button.visible = false
		return
	var building: Dictionary = simulation.buildings[queue_building_id]
	var queue: Array = building.get("queue", [])
	queue_panel.visible = not queue.is_empty()
	queue_title_label.text = "PRODUCTION QUEUE — %s — click to cancel and refund" % str(building["display_name"]).to_upper()
	for index in range(queue_buttons.size()):
		var button: Button = queue_buttons[index]
		if index >= queue.size():
			button.visible = false
			continue
		var job: Dictionary = queue[index]
		var unit_type := str(job.get("unit_type", "unit"))
		var definition = simulation.unit_definitions.get(unit_type)
		var display_name := unit_type.replace("_", " ").to_upper()
		if definition:
			display_name = str(definition.display_name).to_upper()
			display_name = "%s [%dF]" % [display_name, max(1, int(definition.force_slots))]
		var remaining: int = int(ceil(float(job.get("remaining", 0.0))))
		var total: float = max(0.1, float(job.get("total", definition.build_time if definition else 1.0)))
		var progress: int = int(clamp(1.0 - float(job.get("remaining", total)) / total, 0.0, 1.0) * 100.0)
		var refund: int = int(float(job.get("cost", definition.cost if definition else 0.0)))
		var queue_marker := "▶" if index == 0 else "#%d" % index
		button.visible = true
		button.disabled = simulation.match_over
		button.text = "%s %s\n%d%%  %ds · REFUND %d" % [queue_marker, display_name, progress, remaining, refund]
		button.tooltip_text = "Cancel %s and refund %d credits." % [display_name, refund]


func _cancel_queue_slot(queue_index: int) -> void:
	if queue_building_id.is_empty() or not simulation.buildings.has(queue_building_id):
		return
	simulation.issue_command("cancel_production", "player", {"building_id": queue_building_id, "queue_index": queue_index})
	status_label.text = "Cancel requested — the queued item will be refunded on the next simulation tick."


func _find_player_completed_building(kind: String) -> String:
	for building_id in simulation.buildings:
		var building: Dictionary = simulation.buildings[building_id]
		if building["team"] == "player" and building["kind"] == kind and bool(building.get("complete", false)):
			return building_id
	return ""


func _building_context_state(kind: String, prerequisite_kind: String = "") -> Dictionary:
	if not simulation.building_definitions.has(kind) or not simulation.is_team_allowed("player", "buildings", kind):
		return {"visible": false}
	if not prerequisite_kind.is_empty() and _find_player_completed_building(prerequisite_kind).is_empty():
		return {"visible": false}
	var definition = simulation.building_definitions[kind]
	var building_summary: Dictionary = simulation.get_limit_summary("player")["buildings"]
	var by_kind: Dictionary = building_summary.get("by_kind", {})
	var kind_limit: Dictionary = by_kind.get(kind, {})
	var current: int = int(kind_limit.get("current", 0))
	var maximum: int = int(kind_limit.get("max", 1))
	var disabled := false
	var reason := ""
	if current >= maximum:
		disabled = true
		reason = "%s limit reached (%d/%d)." % [definition.display_name, current, maximum]
	elif simulation.player_credits < float(definition.cost):
		disabled = true
		reason = "Need %d more credits." % int(float(definition.cost) - simulation.player_credits)
	return {"visible": true, "disabled": disabled, "reason": reason}


func _unit_context_state(unit_type: String, building: Dictionary) -> Dictionary:
	if not simulation.unit_definitions.has(unit_type) or not simulation.is_team_allowed("player", "units", unit_type):
		return {"visible": false}
	var definition = simulation.unit_definitions[unit_type]
	var limits: Dictionary = simulation.get_limit_summary("player")
	var unit_summary: Dictionary = limits["units"]
	var kind_limits: Dictionary = unit_summary.get("by_kind", {})
	var kind_limit: Dictionary = kind_limits.get(unit_type, {})
	var current_total: int = int(unit_summary.get("current", 0)) + int(unit_summary.get("queued", 0))
	var total_maximum: int = int(unit_summary.get("max", 1))
	var current_kind: int = int(kind_limit.get("current", 0)) + int(kind_limit.get("queued", 0))
	var required_force: int = max(1, int(definition.force_slots))
	var queue: Array = building.get("queue", [])
	var queue_maximum: int = int(limits["queue"].get("max", 5))
	var disabled := false
	var reason := ""
	if queue.size() >= queue_maximum:
		disabled = true
		reason = "Production queue full (%d/%d)." % [queue.size(), queue_maximum]
	elif current_total + required_force > total_maximum:
		disabled = true
		reason = "Force capacity reached (%d/%d); %s requires %d force." % [current_total, total_maximum, definition.display_name, required_force]
	elif unit_type == "collector":
		var building_limits: Dictionary = limits["buildings"]
		var storage_limits: Dictionary = building_limits.get("by_kind", {})
		var storage_count: int = int(storage_limits.get("storage_silo", {}).get("current", 0))
		var collector_capacity: int = 1 + storage_count
		if current_kind >= collector_capacity:
			disabled = true
			reason = "Build a Storage Silo for another Collector (%d/%d)." % [current_kind, collector_capacity]
	var required_technology := str(definition.required_technology)
	if not disabled and not required_technology.is_empty() and not simulation.is_technology_unlocked("player", required_technology):
		disabled = true
		var technology_name := required_technology.replace("_", " ").capitalize()
		if simulation.technology_definitions.has(required_technology):
			technology_name = simulation.technology_definitions[required_technology].display_name
		reason = "Requires %s research." % technology_name
	if not disabled and simulation.player_credits < float(definition.cost):
		disabled = true
		reason = "Need %d more credits." % int(float(definition.cost) - simulation.player_credits)
	return {"visible": true, "disabled": disabled, "reason": reason}


func _unit_card_label(unit_type: String, value_text: String) -> String:
	var display_name := unit_type.replace("_", " ").to_upper()
	var force_slots := 1
	if simulation.unit_definitions.has(unit_type):
		var definition = simulation.unit_definitions[unit_type]
		display_name = str(definition.display_name).to_upper()
		force_slots = max(1, int(definition.force_slots))
	return "◈ %s [%dF]\n%s" % [display_name, force_slots, value_text]


func _upgrade_context_state(building: Dictionary) -> Dictionary:
	var definition = simulation.building_definitions.get(str(building.get("kind", "")))
	if definition == null or str(definition.upgrade_id).is_empty():
		return {"visible": false}
	if bool(building.get("upgrade_complete", false)) or not str(building.get("completed_upgrade_id", "")).is_empty():
		return {"visible": false}
	var active_id := str(building.get("upgrade_id", ""))
	if not active_id.is_empty():
		var total: float = max(0.1, float(building.get("upgrade_total", definition.upgrade_time)))
		var remaining: float = float(building.get("upgrade_remaining", total))
		var progress: int = int(clamp(1.0 - remaining / total, 0.0, 1.0) * 100.0)
		return {"visible": true, "disabled": true, "reason": "Upgrade in progress (%d%%)." % progress, "label_suffix": "%d%%" % progress}
	var disabled := false
	var reason := ""
	if simulation.player_credits < float(definition.upgrade_cost):
		disabled = true
		reason = "Need %d more credits." % int(float(definition.upgrade_cost) - simulation.player_credits)
	return {"visible": true, "disabled": disabled, "reason": reason}


func _research_context_state(building: Dictionary) -> Dictionary:
	var definition = simulation.building_definitions.get(str(building.get("kind", "")))
	if definition == null:
		return {"visible": false}
	var technology_id := str(definition.can_research)
	if technology_id.is_empty() or not simulation.technology_definitions.has(technology_id):
		return {"visible": false}
	if simulation.is_technology_unlocked("player", technology_id):
		return {"visible": false}
	var active_id := str(building.get("research_id", ""))
	if not active_id.is_empty():
		var total: float = max(0.1, float(building.get("research_total", 0.0)))
		var remaining: float = float(building.get("research_remaining", total))
		var progress: int = int(clamp(1.0 - remaining / total, 0.0, 1.0) * 100.0)
		return {"visible": true, "disabled": true, "reason": "Research in progress (%d%%)." % progress, "label_suffix": "%d%%" % progress}
	var technology = simulation.technology_definitions[technology_id]
	var disabled := false
	var reason := ""
	if simulation.player_credits < float(technology.cost):
		disabled = true
		reason = "Need %d more credits." % int(float(technology.cost) - simulation.player_credits)
	return {"visible": true, "disabled": disabled, "reason": reason}


func _update_context_cards() -> void:
	var buttons: Array = [build_button, queue_button, heavy_queue_button, research_button, repair_button, collector_button]
	context_actions = ["", "", "", "", "", ""]
	var cards: Array = []
	for index in range(buttons.size()):
		cards.append({"action": "", "label": "", "visible": false, "disabled": true, "reason": ""})
	if selected_ids.size() == 1:
		var entity_id := str(selected_ids[0])
		if simulation.buildings.has(entity_id):
			var building: Dictionary = simulation.buildings[entity_id]
			match str(building["kind"]):
				"command_hub":
					var processor_state := _building_context_state("refinery")
					if bool(processor_state.get("visible", false)):
						cards[0] = {"action": "build:refinery", "label": "◈ PROCESSOR\n%d" % int(simulation.building_definitions["refinery"].cost), "visible": true, "disabled": processor_state.get("disabled", false), "reason": processor_state.get("reason", "")}
					var assembly_state := _building_context_state("assembly_bay", "refinery")
					if bool(assembly_state.get("visible", false)):
						cards[1] = {"action": "build:assembly_bay", "label": "◈ ASSEMBLY\n%d" % int(simulation.building_definitions["assembly_bay"].cost), "visible": true, "disabled": assembly_state.get("disabled", false), "reason": assembly_state.get("reason", "")}
					var tech_state := _building_context_state("tech_centre", "assembly_bay")
					if bool(tech_state.get("visible", false)):
						cards[2] = {"action": "build:tech_centre", "label": "◈ TECH CENTRE\n%d" % int(simulation.building_definitions["tech_centre"].cost), "visible": true, "disabled": tech_state.get("disabled", false), "reason": tech_state.get("reason", "")}
				"refinery":
					var collector_state := _unit_context_state("collector", building)
					if bool(collector_state.get("visible", false)):
						cards[0] = {"action": "produce:collector", "label": _unit_card_label("collector", "%d" % int(simulation.unit_definitions["collector"].cost)), "visible": true, "disabled": collector_state.get("disabled", false), "reason": collector_state.get("reason", "")}
					var silo_state := _building_context_state("storage_silo", "refinery")
					if bool(silo_state.get("visible", false)):
						cards[1] = {"action": "build:storage_silo", "label": "◈ SILO\n%d" % int(simulation.building_definitions["storage_silo"].cost), "visible": true, "disabled": silo_state.get("disabled", false), "reason": silo_state.get("reason", "")}
					var refining_state := _upgrade_context_state(building)
					if bool(refining_state.get("visible", false)):
						var refining_suffix := str(refining_state.get("label_suffix", ""))
						var refining_label := "▲ REFINING\n%d" % int(simulation.building_definitions["refinery"].upgrade_cost)
						if not refining_suffix.is_empty():
							refining_label = "▲ REFINING\n%s" % refining_suffix
						cards[2] = {"action": "upgrade", "label": refining_label, "visible": true, "disabled": refining_state.get("disabled", false), "reason": refining_state.get("reason", "")}
				"assembly_bay":
					var ranger_state := _unit_context_state("ranger", building)
					if bool(ranger_state.get("visible", false)):
						cards[0] = {"action": "produce:ranger", "label": _unit_card_label("ranger", "%d" % int(simulation.unit_definitions["ranger"].cost)), "visible": true, "disabled": ranger_state.get("disabled", false), "reason": ranger_state.get("reason", "")}
					var bulwark_state := _unit_context_state("bulwark", building)
					if bool(bulwark_state.get("visible", false)):
						var bulwark_reason := str(bulwark_state.get("reason", ""))
						var bulwark_label := _unit_card_label("bulwark", "%d" % int(simulation.unit_definitions["bulwark"].cost))
						if not bulwark_reason.is_empty() and bulwark_reason.begins_with("Requires"):
							bulwark_label = _unit_card_label("bulwark", "RESEARCH")
						cards[1] = {"action": "produce:bulwark", "label": bulwark_label, "visible": true, "disabled": bulwark_state.get("disabled", false), "reason": bulwark_reason}
					var warden_state := _unit_context_state("warden", building)
					if bool(warden_state.get("visible", false)):
						cards[2] = {"action": "produce:warden", "label": _unit_card_label("warden", "%d" % int(simulation.unit_definitions["warden"].cost)), "visible": true, "disabled": warden_state.get("disabled", false), "reason": warden_state.get("reason", "")}
					var fabrication_state := _upgrade_context_state(building)
					if bool(fabrication_state.get("visible", false)):
						var fabrication_suffix := str(fabrication_state.get("label_suffix", ""))
						var fabrication_label := "▲ FABRICATION\n%d" % int(simulation.building_definitions["assembly_bay"].upgrade_cost)
						if not fabrication_suffix.is_empty():
							fabrication_label = "▲ FABRICATION\n%s" % fabrication_suffix
						cards[3] = {"action": "upgrade", "label": fabrication_label, "visible": true, "disabled": fabrication_state.get("disabled", false), "reason": fabrication_state.get("reason", "")}
				"tech_centre":
					var research_state := _research_context_state(building)
					if bool(research_state.get("visible", false)):
						var research_suffix := str(research_state.get("label_suffix", ""))
						var research_label := "▲ TARGETING\n%d" % int(simulation.technology_definitions["advanced_targeting"].cost)
						if not research_suffix.is_empty():
							research_label = "▲ TARGETING\n%s" % research_suffix
						cards[0] = {"action": "research", "label": research_label, "visible": true, "disabled": research_state.get("disabled", false), "reason": research_state.get("reason", "")}
			if bool(_has_damaged_selection()):
				cards[4] = {"action": "repair", "label": "REPAIR", "visible": true, "disabled": false, "reason": "Repair the selected friendly entity."}
		elif simulation.units.has(entity_id) and simulation.units[entity_id]["kind"] == "collector":
			cards[0] = {"action": "collector_route", "label": "ROUTE [U]", "visible": true, "disabled": false, "reason": "Assign this Collector to an Energy Field and Processor."}
			if bool(_has_damaged_selection()):
				cards[4] = {"action": "repair", "label": "REPAIR", "visible": true, "disabled": false, "reason": "Repair the selected Collector."}
	elif not selected_ids.is_empty():
		cards[0] = {"action": "", "label": "MULTI-UNIT\nORDERS", "visible": true, "disabled": true, "reason": "Use right-click to issue a group order."}
		if bool(_has_damaged_selection()):
			cards[4] = {"action": "repair", "label": "REPAIR", "visible": true, "disabled": false, "reason": "Repair damaged selected units."}
	else:
		cards[0] = {"action": "", "label": "SELECT\nSTRUCTURE", "visible": true, "disabled": true, "reason": "Select a Command Hub, Processor, Assembly Bay, or Tech Centre."}
	for index in range(buttons.size()):
		var button: Button = buttons[index]
		var card: Dictionary = cards[index]
		var action := str(card.get("action", ""))
		context_actions[index] = action
		button.visible = bool(card.get("visible", false))
		button.text = str(card.get("label", ""))
		button.disabled = bool(card.get("disabled", true)) or simulation.match_over
		var reason := str(card.get("reason", ""))
		button.tooltip_text = reason if not reason.is_empty() else button.text.replace("\n", " ")

func _selection_detail(data: Dictionary) -> String:
	var supply_text := ""
	if data.has("supply_state"):
		supply_text = "   SUPPLY %s" % str(data["supply_state"]).to_upper()
		if str(data.get("supply_reason", "")).is_empty() == false:
			supply_text += " — %s" % str(data.get("supply_reason", ""))
	var force_text := ""
	if data.has("kind") and simulation.unit_definitions.has(str(data["kind"])):
		var selected_definition = simulation.unit_definitions[str(data["kind"])]
		force_text = "   FORCE %d" % max(1, int(selected_definition.force_slots))
		var waypoint_count: int = data.get("command_waypoints", []).size()
		if waypoint_count > 0:
			force_text += "   WAYPOINTS %d" % waypoint_count
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
		elif data["collector_state"] == "depleted":
			collector_route_label = "SOURCE DEPLETED — PRESS U"
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
		return "HP %d/%d   ORDER %s%s%s%s%s%s%s" % [int(data["health"]), int(data["max_health"]), str(data["order"]).to_upper(), force_text, supply_text, collector_text, research_text, queue_text, rally_text]
	return "HP %d/%d   %s%s%s%s%s%s%s" % [int(data["health"]), int(data["max_health"]), "ONLINE" if data["complete"] else "BUILDING", force_text, supply_text, collector_text, research_text, queue_text, rally_text]

func _on_simulation_event(event_type: String, payload: Dictionary) -> void:
	if combat_effects:
		combat_effects.present(self, simulation, event_type, payload)
	if not status_label or not event_log_label:
		return
	var feedback_message: String = str(payload.get("message", payload.get("reason", "")))
	if event_type == "AIIntentDeclared" or event_type == "AIPhaseChanged" or event_type == "AIPostureChanged":
		if not feedback_message.is_empty():
			status_label.text = "OPPONENT INTEL — %s" % feedback_message
		return
	if not _is_player_event(event_type, payload):
		return
	if not feedback_message.is_empty():
		status_label.text = feedback_message
	if event_type == "MatchWon" or event_type == "MatchLost":
		status_label.text = "[ %s ] %s" % ["VICTORY" if event_type == "MatchWon" else "DEFEAT", payload.get("message", "Match complete")]
		status_label.modulate = Color("#ffd36a") if event_type == "MatchWon" else Color("#ff7b86")
	if event_type == "MatchWon" and campaign_progress:
		var unlocked_id: String = campaign_progress.mark_complete(simulation.get_level_id())
		if not unlocked_id.is_empty():
			status_label.text = "LEVEL COMPLETE — Level 2 unlocked. Press F2 to deploy."
	var lines: PackedStringArray = event_log_label.text.split("\n")
	if not feedback_message.is_empty():
		lines.append("[%03d] %s" % [int(payload.get("tick", 0)), feedback_message])
	while lines.size() > 5:
		lines.remove_at(0)
	event_log_label.text = "EVENT LOG\n" + "\n".join(lines.slice(1))


func _is_player_event(event_type: String, payload: Dictionary) -> bool:
	if payload.has("attacker_team"):
		return str(payload.get("team", "")) == "player" or str(payload.get("attacker_team", "")) == "player"
	if payload.has("team"):
		return str(payload.get("team", "")) == "player"
	return event_type == "MatchStarted" or event_type == "MatchWon" or event_type == "MatchLost"


func _update_selection_marquee() -> void:
	var rectangle := Rect2(drag_start, drag_current - drag_start).abs()
	selection_marquee.position = rectangle.position
	selection_marquee.size = rectangle.size


func _pointer_over_ui() -> bool:
	if start_menu_visible:
		return true
	if queue_panel and queue_panel.visible and queue_panel.get_global_rect().has_point(pointer_position):
		return true
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
