extends Node3D

const SimulationScript = preload("res://src/rts_simulation.gd")
const UnitViewScript = preload("res://src/rts_unit_view.gd")
const BuildingViewScript = preload("res://src/rts_building_view.gd")
const MinimapScript = preload("res://src/minimap.gd")
const CampaignProgressScript = preload("res://src/campaign_progress.gd")
const WorldBuilderScript = preload("res://src/presentation/rts_world_builder.gd")
const CombatEffectsScript = preload("res://src/presentation/rts_combat_effects.gd")
const AudioManagerScript = preload("res://src/presentation/rts_audio_manager.gd")
const WorldViewSynchronizerScript = preload("res://src/presentation/rts_world_view_synchronizer.gd")
const FogOfWarViewScript = preload("res://src/presentation/rts_fog_of_war_view.gd")
const CampaignMarkerViewScript = preload("res://src/presentation/rts_campaign_marker_view.gd")
const HudIconScript = preload("res://src/ui/rts_hud_icon.gd")

const MAP_HALF_WIDTH := 80.0
const MAP_HALF_DEPTH := 55.0
const CAMERA_TARGET_X_FACTOR := 0.78
const CAMERA_TARGET_Z_FACTOR := 0.78
const AI_DIFFICULTIES := ["standard", "aggressive", "defensive"]

var simulation
var campaign_progress
var camera: Camera3D
var world_shell: Node3D
var fog_view
var camera_target := Vector3.ZERO
var camera_distance := 31.0
var camera_yaw := 0.0
var camera_pitch := 0.72
var pointer_position := Vector2.ZERO

var unit_views: Dictionary = {}
var building_views: Dictionary = {}
var control_views: Dictionary = {}
var resource_views: Dictionary = {}
var campaign_marker_views: Dictionary = {}
var selected_ids: Array = []
var selected_resource_id := ""
var inspected_target_id := ""
var control_groups: Dictionary = {}

var dragging := false
var drag_start := Vector2.ZERO
var drag_current := Vector2.ZERO
var pointer_inside_viewport := true
var selection_marquee: ColorRect
var build_mode := ""
var attack_move_mode := false
var patrol_mode := false
var build_ghost: Node3D
var build_ghost_mesh: MeshInstance3D
var build_ghost_label: Label3D
var build_ghost_valid := false
var build_range_guides: Dictionary = {}
var collector_assignment_mode := false
var collector_assignment_source_id := ""
var collector_assignment_unit_id := ""

var credits_label: Label
var territory_label: Label
var supply_label: Label
var force_label: Label
var match_context_label: Label
var match_time_label: Label
var top_status_icons: Dictionary = {}
var selected_label: Label
var selected_icon: Control
var selected_info_panel: PanelContainer
var objective_label: Label
var scenario_progress_label: Label
var status_label: Label
var event_log_label: Label
var damage_feedback_last_tick: Dictionary = {}
var pause_menu_overlay: ColorRect
var pause_menu_panel: PanelContainer
var pause_menu_visible := false
var game_log_toggle: CheckButton
var play_hints_toggle: CheckButton
var game_log_enabled := false
var play_hints_enabled := true
var master_volume_slider: HSlider
var sfx_volume_slider: HSlider
var music_volume_slider: HSlider
var master_volume_value_label: Label
var sfx_volume_value_label: Label
var music_volume_value_label: Label
var build_button: Button
var queue_button: Button
var heavy_queue_button: Button
var research_button: Button
var repair_button: Button
var collector_button: Button
var repair_overflow_button: Button
var bottom_panel: PanelContainer
var action_card_icons: Array = []
var action_card_titles: Array = []
var action_card_prices: Array = []
var minimap
var mission_one_button: Button
var mission_two_button: Button
var campaign_mission_buttons: Dictionary = {}
var campaign_mission_scroll: ScrollContainer
var campaign_mission_list: VBoxContainer
var campaign_mission_detail_label: Label
var campaign_doctrine_option: OptionButton
var campaign_start_button: Button
var selected_campaign_level_id := "relay_divide"
var start_menu_overlay: ColorRect
var start_menu_panel: PanelContainer
var start_menu_briefing_label: Label
var campaign_tab_button: Button
var skirmish_tab_button: Button
var campaign_menu_container: VBoxContainer
var skirmish_menu_container: VBoxContainer
var skirmish_map_option: OptionButton
var skirmish_scenario_option: OptionButton
var skirmish_difficulty_option: OptionButton
var skirmish_intent_option: OptionButton
var skirmish_briefing_label: Label
var skirmish_deploy_button: Button
var deployment_mode := "campaign"
var start_menu_visible := true
var result_overlay: ColorRect
var result_panel: PanelContainer
var result_title_label: Label
var result_mission_label: Label
var result_detail_label: Label
var result_summary_label: Label
var result_receipt_label: Label
var rematch_button: Button
var return_deployment_button: Button
var result_visible := false
var objective_briefing_overlay: ColorRect
var objective_briefing_panel: PanelContainer
var objective_briefing_title_label: Label
var objective_briefing_body_label: Label
var objective_briefing_acknowledge_button: Button
var objective_briefing_visible := false
var combat_effect_sequence := 0
var combat_effects
var audio_manager
var objective_target_point_id := ""
var objective_target_point_ids: Array = []
var build_source_id := ""
var context_actions: Array = []
var queue_panel: PanelContainer
var queue_title_label: Label
var queue_buttons: Array[Button] = []
var queue_card_icons: Array = []
var queue_card_titles: Array = []
var queue_card_progress: Array = []
var queue_card_refunds: Array = []
var queue_building_id := ""


func _ready() -> void:
	_build_environment()
	_build_camera()
	campaign_progress = CampaignProgressScript.new()
	combat_effects = CombatEffectsScript.new()
	audio_manager = AudioManagerScript.new()
	audio_manager.name = "AudioManager"
	add_child(audio_manager)
	simulation = SimulationScript.new()
	add_child(simulation)
	simulation.simulation_event.connect(_on_simulation_event)
	simulation.start_match()
	camera_target = _starting_camera_target()
	_build_world_shell()
	_build_ui()
	_connect_pointer_signals()
	_sync_views()
	_update_camera()
	_update_hud()


func _process(delta: float) -> void:
	_process_camera_input(delta)
	if not start_menu_visible and not objective_briefing_visible and not pause_menu_visible:
		simulation.step(delta)
	_sync_views(delta)
	_update_camera()
	_update_hud()
	_update_build_ghost()
	_update_build_range_guides()
	if dragging:
		_update_selection_marquee()


func _connect_pointer_signals() -> void:
	var window := get_window()
	if window == null:
		return
	if window.has_signal("mouse_entered"):
		window.connect("mouse_entered", _on_pointer_entered)
	if window.has_signal("mouse_exited"):
		window.connect("mouse_exited", _on_pointer_exited)


func _on_pointer_entered() -> void:
	pointer_inside_viewport = true


func _on_pointer_exited() -> void:
	pointer_inside_viewport = false
	if dragging:
		dragging = false
		if selection_marquee:
			selection_marquee.visible = false


func _input(event: InputEvent) -> void:
	# Track the pointer before GUI controls receive the event. This keeps edge
	# scrolling honest when the cursor leaves the window and lets a marquee
	# finish even when the release happens over a HUD button.
	if event is InputEventMouseMotion:
		pointer_inside_viewport = get_viewport().get_visible_rect().has_point(event.position)
		pointer_position = event.position
		if dragging:
			drag_current = event.position
			if not pointer_inside_viewport:
				dragging = false
				selection_marquee.visible = false
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and dragging:
		pointer_position = event.position
		drag_current = event.position
		dragging = false
		selection_marquee.visible = false
		_finish_left_click()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		pointer_position = event.position
		pointer_inside_viewport = get_viewport().get_visible_rect().has_point(event.position)
		if dragging:
			drag_current = event.position
		return
	if event is InputEventMouseButton:
		pointer_position = event.position
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			if not _pointer_over_ui():
				camera_distance = max(16.0, camera_distance - 2.5)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			if not _pointer_over_ui():
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
			if _pointer_over_ui():
				return
			if collector_assignment_mode:
				_cancel_collector_assignment()
				return
			_cancel_build_mode()
			_issue_context_order(event.position, event.shift_pressed)
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if collector_assignment_mode or not build_mode.is_empty() or attack_move_mode or patrol_mode:
				_cancel_build_mode()
				_cancel_collector_assignment()
				attack_move_mode = false
				patrol_mode = false
				return
			_toggle_pause_menu()
			return
		if pause_menu_visible:
			return
		if event.keycode >= KEY_0 and event.keycode <= KEY_9:
			_handle_control_group(event.keycode - KEY_0, event.ctrl_pressed or event.meta_pressed)
			return
		match event.keycode:
			KEY_B:
				if _selected_build_source_id().is_empty():
					status_label.text = "Select a completed Command Hub or Forward Base before building."
				else:
					_toggle_build_mode()
			KEY_G:
				_guard_selected_units()
			KEY_T:
				_toggle_attack_move_mode()
			KEY_P:
				_toggle_patrol_mode()
			KEY_X:
				_stop_selected_units()
			KEY_U:
				_begin_collector_assignment()
			KEY_E:
				camera_yaw = clamp(camera_yaw + deg_to_rad(8.0), -0.78, 0.78)
			KEY_R:
				camera_yaw = clamp(camera_yaw - deg_to_rad(8.0), -0.78, 0.78)
			KEY_H:
				_focus_selection()
			KEY_SPACE:
				if play_hints_enabled:
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
	fog_view = FogOfWarViewScript.new()
	fog_view.name = "FogOfWarView"
	fog_view.configure(simulation.get_level_bounds(), float(simulation.level_rules.get("fog_tile_size", 8.0)))
	world_shell.add_child(fog_view)


func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "TacticalHUD"
	add_child(canvas)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ui_theme := Theme.new()
	ui_theme.default_font = ThemeDB.fallback_font
	ui_theme.default_font_size = 14
	root.theme = ui_theme
	canvas.add_child(root)

	var top_panel := PanelContainer.new()
	top_panel.name = "TopStatusPanel"
	top_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_panel.offset_left = 18.0
	top_panel.offset_right = -18.0
	top_panel.offset_top = 16.0
	top_panel.offset_bottom = 116.0
	top_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.025, 0.075, 0.1, 0.94), Color(0.18, 0.7, 0.78, 0.75)))
	root.add_child(top_panel)
	var top_margin := MarginContainer.new()
	top_margin.add_theme_constant_override("margin_left", 12)
	top_margin.add_theme_constant_override("margin_right", 12)
	top_margin.add_theme_constant_override("margin_top", 7)
	top_margin.add_theme_constant_override("margin_bottom", 7)
	top_panel.add_child(top_margin)
	var top_column := VBoxContainer.new()
	top_column.name = "TopStatusColumn"
	top_column.add_theme_constant_override("separation", 4)
	top_margin.add_child(top_column)
	var top_row := HBoxContainer.new()
	top_row.name = "TopTitleRow"
	top_row.add_theme_constant_override("separation", 10)
	top_column.add_child(top_row)
	var title := _label("FRACTURE PROTOCOL", 23, Color("#d6fbff"))
	title.custom_minimum_size.x = 235.0
	top_row.add_child(title)
	match_context_label = _label("DEPLOYMENT  //  CAMPAIGN", 12, Color(0.58, 0.78, 0.82, 0.78))
	match_context_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	match_context_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	match_context_label.clip_text = true
	top_row.add_child(match_context_label)
	match_time_label = _label("TIME 00:00", 13, Color("#ffd36a"))
	match_time_label.custom_minimum_size.x = 82.0
	match_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top_row.add_child(match_time_label)

	var top_stats_scroll := ScrollContainer.new()
	top_stats_scroll.name = "TopStatsScroll"
	top_stats_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	top_stats_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	top_stats_scroll.custom_minimum_size = Vector2(0.0, 34.0)
	top_stats_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_stats_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	top_column.add_child(top_stats_scroll)
	var top_stats_row := HBoxContainer.new()
	top_stats_row.name = "TopStatsRow"
	top_stats_row.add_theme_constant_override("separation", 7)
	top_stats_scroll.add_child(top_stats_row)
	credits_label = _label("CREDITS 850", 14, Color("#ffd36a"))
	# The storage counter can grow to five digits on both sides of the slash.
	# Give it its own breathing room so it never clips into the next status chip.
	top_stats_row.add_child(_create_status_chip("CreditsChip", credits_label, 220.0, Color("#ffd36a"), "resource"))
	territory_label = _label("TERRITORY 0/3", 14, Color("#8cebf3"))
	territory_label.custom_minimum_size.x = 168.0
	var territory_chip := _create_status_chip("TerritoryChip", territory_label, 222.0, Color("#8cebf3"), "forward_relay")
	territory_label.clip_text = false
	top_stats_row.add_child(territory_chip)
	supply_label = _label("SUPPLY CONNECTED", 14, Color("#7cf1ad"))
	force_label = _label("FORCE 4/24", 14, Color("#c3d8df"))
	top_stats_row.add_child(_create_status_chip("ForceChip", force_label, 128.0, Color("#c3d8df"), "mixed"))
	# Keep the operational supply warning at the end of the row, where it can
	# use the remaining HUD width without pushing the core economy stats away.
	top_stats_row.add_child(_create_status_chip("SupplyChip", supply_label, 184.0, Color("#7cf1ad"), "route"))

	# Keep objective, progress, and transient tactical feedback in one quiet
	# information band. The previous three floating text rows competed with
	# the battlefield and made every update look like another HUD alert.
	var objective_panel := PanelContainer.new()
	objective_panel.name = "ObjectiveStatusPanel"
	objective_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	objective_panel.offset_left = 18.0
	objective_panel.offset_right = -18.0
	objective_panel.offset_top = 126.0
	objective_panel.offset_bottom = 211.0
	objective_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	objective_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.018, 0.055, 0.07, 0.78), Color(0.18, 0.7, 0.78, 0.38)))
	root.add_child(objective_panel)
	var objective_margin := MarginContainer.new()
	objective_margin.add_theme_constant_override("margin_left", 12)
	objective_margin.add_theme_constant_override("margin_right", 12)
	objective_margin.add_theme_constant_override("margin_top", 6)
	objective_margin.add_theme_constant_override("margin_bottom", 6)
	objective_panel.add_child(objective_margin)
	var objective_column := VBoxContainer.new()
	objective_column.name = "ObjectiveStatusColumn"
	objective_column.add_theme_constant_override("separation", 1)
	objective_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	objective_margin.add_child(objective_column)
	objective_label = _label("OBJECTIVE", 17, Color("#ffd36a"))
	objective_label.custom_minimum_size = Vector2(0.0, 25.0)
	objective_label.clip_text = true
	objective_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	objective_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	objective_column.add_child(objective_label)

	scenario_progress_label = _label("", 13, Color("#8cebf3"))
	scenario_progress_label.custom_minimum_size = Vector2(0.0, 21.0)
	scenario_progress_label.clip_text = true
	scenario_progress_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	scenario_progress_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	objective_column.add_child(scenario_progress_label)

	status_label = _label("Awaiting orders.", 13, Color("#b4c9ce"))
	status_label.custom_minimum_size = Vector2(0.0, 21.0)
	status_label.clip_text = true
	status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	objective_column.add_child(status_label)

	event_log_label = _label("EVENT LOG\nAwaiting orders...", 12, Color("#9db6bc"))
	event_log_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	event_log_label.offset_left = 24.0
	event_log_label.offset_right = 390.0
	event_log_label.offset_top = -214.0
	event_log_label.offset_bottom = -122.0
	event_log_label.clip_text = true
	event_log_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	event_log_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	event_log_label.add_theme_constant_override("shadow_offset_x", 2)
	event_log_label.add_theme_constant_override("shadow_offset_y", 2)
	root.add_child(event_log_label)

	bottom_panel = PanelContainer.new()
	bottom_panel.name = "ContextActionPanel"
	bottom_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_panel.offset_left = 18.0
	bottom_panel.offset_right = -18.0
	bottom_panel.offset_top = -112.0
	bottom_panel.offset_bottom = -18.0
	bottom_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.025, 0.075, 0.1, 0.96), Color(0.18, 0.7, 0.78, 0.75)))
	root.add_child(bottom_panel)
	var bottom_margin := MarginContainer.new()
	bottom_margin.add_theme_constant_override("margin_left", 10)
	bottom_margin.add_theme_constant_override("margin_right", 10)
	bottom_margin.add_theme_constant_override("margin_top", 9)
	bottom_margin.add_theme_constant_override("margin_bottom", 9)
	bottom_panel.add_child(bottom_margin)
	var bottom_row := HBoxContainer.new()
	bottom_row.add_theme_constant_override("separation", 8)
	bottom_margin.add_child(bottom_row)
	selected_info_panel = PanelContainer.new()
	selected_info_panel.name = "SelectedEntityCard"
	selected_info_panel.custom_minimum_size = Vector2(236.0, 74.0)
	selected_info_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	selected_info_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.035, 0.11, 0.14, 0.96), Color(0.22, 0.78, 0.82, 0.72)))
	bottom_row.add_child(selected_info_panel)
	var selected_margin := MarginContainer.new()
	selected_margin.add_theme_constant_override("margin_left", 7)
	selected_margin.add_theme_constant_override("margin_right", 7)
	selected_margin.add_theme_constant_override("margin_top", 5)
	selected_margin.add_theme_constant_override("margin_bottom", 5)
	selected_info_panel.add_child(selected_margin)
	var selected_row := HBoxContainer.new()
	selected_row.add_theme_constant_override("separation", 7)
	selected_margin.add_child(selected_row)
	selected_icon = HudIconScript.new()
	selected_icon.name = "SelectedEntityIcon"
	selected_icon.custom_minimum_size = Vector2(54.0, 54.0)
	selected_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	selected_row.add_child(selected_icon)
	selected_label = _label("NO SELECTION\nSelect units or a structure", 14, Color("#d2e7ec"))
	selected_label.custom_minimum_size = Vector2(170.0, 54.0)
	selected_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selected_label.clip_text = true
	selected_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	selected_row.add_child(selected_label)

	var action_scroll := ScrollContainer.new()
	action_scroll.name = "ContextActionScroll"
	action_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	action_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	action_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	action_scroll.custom_minimum_size = Vector2(0.0, 76.0)
	action_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	bottom_row.add_child(action_scroll)
	var action_row := HBoxContainer.new()
	action_row.name = "ContextActionRow"
	action_row.add_theme_constant_override("separation", 7)
	action_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	action_scroll.add_child(action_row)

	build_button = _create_action_card(0)
	queue_button = _create_action_card(1)
	heavy_queue_button = _create_action_card(2)
	research_button = _create_action_card(3)
	repair_button = _create_action_card(4)
	collector_button = _create_action_card(5)
	repair_overflow_button = _create_action_card(6)
	for action_button in [build_button, queue_button, heavy_queue_button, research_button, repair_button, collector_button, repair_overflow_button]:
		action_row.add_child(action_button)

	queue_panel = PanelContainer.new()
	queue_panel.name = "ProductionQueuePanel"
	queue_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	queue_panel.offset_left = 30.0
	queue_panel.offset_right = -30.0
	queue_panel.offset_top = -236.0
	queue_panel.offset_bottom = -122.0
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
	queue_title_label = _label("QUEUE  //  CLICK A CARD TO CANCEL", 12, Color("#ffd36a"))
	queue_title_label.name = "ProductionQueueTitle"
	queue_title_label.clip_text = true
	queue_title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	queue_column.add_child(queue_title_label)
	var queue_scroll := ScrollContainer.new()
	queue_scroll.name = "ProductionQueueScroll"
	queue_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	queue_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	queue_scroll.custom_minimum_size = Vector2(0.0, 78.0)
	queue_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	queue_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	queue_column.add_child(queue_scroll)
	var queue_row := HBoxContainer.new()
	queue_row.name = "ProductionQueueRow"
	queue_row.add_theme_constant_override("separation", 7)
	queue_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	queue_row.alignment = BoxContainer.ALIGNMENT_CENTER
	queue_scroll.add_child(queue_row)
	for queue_index in range(5):
		var queue_button := _create_queue_card(queue_index)
		queue_button.visible = false
		queue_button.pressed.connect(_cancel_queue_slot.bind(queue_index))
		queue_row.add_child(queue_button)
		queue_buttons.append(queue_button)
	root.add_child(queue_panel)
	queue_panel.visible = false

	minimap = MinimapScript.new()
	minimap.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	minimap.offset_left = -270.0
	minimap.offset_right = -18.0
	minimap.offset_top = -274.0
	minimap.offset_bottom = -108.0
	minimap.world_position_clicked.connect(_on_minimap_world_position_clicked)
	var bounds: Vector2 = simulation.get_level_bounds()
	minimap.map_bounds = Rect2(-bounds.x, -bounds.y, bounds.x * 2.0, bounds.y * 2.0)
	root.add_child(minimap)

	selection_marquee = ColorRect.new()
	selection_marquee.color = Color(0.25, 0.88, 0.98, 0.13)
	selection_marquee.mouse_filter = Control.MOUSE_FILTER_IGNORE
	selection_marquee.visible = false
	root.add_child(selection_marquee)
	_build_campaign_start_menu(root)
	_build_match_result_overlay(root)
	_build_objective_briefing(root)
	_build_pause_menu(root)
	if audio_manager:
		audio_manager.wire_ui(self)


func _build_pause_menu(root: Control) -> void:
	pause_menu_overlay = ColorRect.new()
	pause_menu_overlay.name = "PauseMenuOverlay"
	pause_menu_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_menu_overlay.color = Color(0.008, 0.025, 0.04, 0.84)
	pause_menu_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(pause_menu_overlay)

	pause_menu_panel = PanelContainer.new()
	pause_menu_panel.name = "PauseMenuPanel"
	pause_menu_panel.set_anchors_preset(Control.PRESET_CENTER)
	pause_menu_panel.offset_left = -250.0
	pause_menu_panel.offset_right = 250.0
	pause_menu_panel.offset_top = -270.0
	pause_menu_panel.offset_bottom = 270.0
	pause_menu_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.025, 0.075, 0.1, 0.99), Color(0.18, 0.7, 0.78, 0.9)))
	pause_menu_overlay.add_child(pause_menu_panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	pause_menu_panel.add_child(margin)
	var pause_scroll := ScrollContainer.new()
	pause_scroll.name = "PauseMenuScroll"
	pause_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pause_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(pause_scroll)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pause_scroll.add_child(column)
	var title := _label("PAUSED", 26, Color("#d6fbff"))
	column.add_child(title)
	var subtitle := _label("Simulation paused. Configure the information layer before resuming.", 13, Color("#c3d8df"))
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(subtitle)
	var separator := HSeparator.new()
	column.add_child(separator)
	game_log_toggle = CheckButton.new()
	game_log_toggle.name = "GameLogToggle"
	game_log_toggle.text = "GAME LOG"
	game_log_toggle.tooltip_text = "Show or hide the bottom-left event log."
	game_log_toggle.button_pressed = game_log_enabled
	game_log_toggle.toggled.connect(_on_game_log_toggled)
	column.add_child(game_log_toggle)
	play_hints_toggle = CheckButton.new()
	play_hints_toggle.name = "PlayHintsToggle"
	play_hints_toggle.text = "PLAY HINTS"
	play_hints_toggle.tooltip_text = "Show or hide combat warnings and contextual counterplay guidance."
	play_hints_toggle.button_pressed = play_hints_enabled
	play_hints_toggle.toggled.connect(_on_play_hints_toggled)
	column.add_child(play_hints_toggle)
	var hint := _label("Hints include the top-left tactical status and selection guidance. Objective and result screens remain available.", 12, Color("#8ca9b5"))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(hint)
	var audio_separator := HSeparator.new()
	column.add_child(audio_separator)
	var audio_title := _label("AUDIO", 15, Color("#ffd36a"))
	column.add_child(audio_title)
	var master_control := _create_volume_control("MasterVolume", "MASTER", 100.0, Callable(self, "_on_master_volume_changed"))
	master_volume_slider = master_control["slider"] as HSlider
	master_volume_value_label = master_control["value_label"] as Label
	column.add_child(master_control["row"])
	var sfx_control := _create_volume_control("SfxVolume", "EFFECTS", 85.0, Callable(self, "_on_sfx_volume_changed"))
	sfx_volume_slider = sfx_control["slider"] as HSlider
	sfx_volume_value_label = sfx_control["value_label"] as Label
	column.add_child(sfx_control["row"])
	var music_control := _create_volume_control("MusicVolume", "MUSIC", 70.0, Callable(self, "_on_music_volume_changed"))
	music_volume_slider = music_control["slider"] as HSlider
	music_volume_value_label = music_control["value_label"] as Label
	music_volume_slider.tooltip_text = "Music bus ready. Add tracks under res://audio/music when available."
	column.add_child(music_control["row"])
	var music_note := _label("Music bus ready — no music track loaded.", 11, Color("#8ca9b5"))
	music_note.name = "MusicTrackStatus"
	if audio_manager and audio_manager.music_track_loaded:
		music_note.text = "Music track loaded."
	column.add_child(music_note)
	var resume_button := Button.new()
	resume_button.name = "ResumeButton"
	resume_button.text = "RESUME"
	resume_button.custom_minimum_size = Vector2(0.0, 48.0)
	resume_button.pressed.connect(_hide_pause_menu)
	column.add_child(resume_button)
	pause_menu_overlay.visible = false


func _toggle_pause_menu() -> void:
	if start_menu_visible or result_visible or objective_briefing_visible:
		return
	if pause_menu_visible:
		_hide_pause_menu()
	else:
		_show_pause_menu()


func _show_pause_menu() -> void:
	_cancel_build_mode()
	_cancel_collector_assignment(false)
	attack_move_mode = false
	patrol_mode = false
	pause_menu_visible = true
	if pause_menu_overlay:
		pause_menu_overlay.visible = true
	if game_log_toggle:
		game_log_toggle.button_pressed = game_log_enabled
	if play_hints_toggle:
		play_hints_toggle.button_pressed = play_hints_enabled
	if audio_manager:
		if master_volume_slider:
			master_volume_slider.value = audio_manager.master_volume * 100.0
		if sfx_volume_slider:
			sfx_volume_slider.value = audio_manager.sfx_volume * 100.0
		if music_volume_slider:
			music_volume_slider.value = audio_manager.music_volume * 100.0


func _hide_pause_menu() -> void:
	pause_menu_visible = false
	if pause_menu_overlay:
		pause_menu_overlay.visible = false


func _on_game_log_toggled(enabled: bool) -> void:
	game_log_enabled = enabled
	if event_log_label:
		event_log_label.visible = enabled


func _on_play_hints_toggled(enabled: bool) -> void:
	play_hints_enabled = enabled
	if status_label:
		status_label.visible = enabled
	_update_hud()


func _on_master_volume_changed(value: float) -> void:
	if audio_manager:
		audio_manager.set_master_volume(value / 100.0)
	_update_volume_label(master_volume_value_label, value)


func _on_sfx_volume_changed(value: float) -> void:
	if audio_manager:
		audio_manager.set_sfx_volume(value / 100.0)
	_update_volume_label(sfx_volume_value_label, value)


func _on_music_volume_changed(value: float) -> void:
	if audio_manager:
		audio_manager.set_music_volume(value / 100.0)
	_update_volume_label(music_volume_value_label, value)


func _update_volume_label(label: Label, value: float) -> void:
	if label:
		label.text = "%d%%" % int(round(value))


func _create_volume_control(control_name: String, label_text: String, initial_value: float, callback: Callable) -> Dictionary:
	var row := HBoxContainer.new()
	row.name = control_name
	row.add_theme_constant_override("separation", 8)
	var label := _label(label_text, 12, Color("#d6fbff"))
	label.custom_minimum_size.x = 92.0
	row.add_child(label)
	var slider := HSlider.new()
	slider.name = "%sSlider" % control_name
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.value = initial_value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size.y = 24.0
	slider.focus_mode = Control.FOCUS_NONE
	slider.value_changed.connect(callback)
	row.add_child(slider)
	var value_label := _label("%d%%" % int(initial_value), 11, Color("#ffd36a"))
	value_label.name = "%sValue" % control_name
	value_label.custom_minimum_size.x = 42.0
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)
	return {"row": row, "slider": slider, "value_label": value_label}


func _build_campaign_start_menu(root: Control) -> void:
	start_menu_overlay = ColorRect.new()
	start_menu_overlay.name = "CampaignStartMenuOverlay"
	start_menu_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	start_menu_overlay.color = Color(0.008, 0.025, 0.04, 0.92)
	start_menu_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(start_menu_overlay)

	start_menu_panel = PanelContainer.new()
	start_menu_panel.name = "DeploymentMenu"
	start_menu_panel.position = Vector2(160.0, 68.0)
	start_menu_panel.size = Vector2(960.0, 650.0)
	start_menu_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.025, 0.075, 0.1, 0.98), Color(0.18, 0.7, 0.78, 0.8)))
	start_menu_overlay.add_child(start_menu_panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	start_menu_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 9)
	margin.add_child(column)
	var title := _label("DEPLOYMENT CONTROL", 24, Color("#d6fbff"))
	column.add_child(title)
	var subtitle := _label("FRACTURE PROTOCOL  //  CAMPAIGN OR LOCAL SKIRMISH", 13, Color("#8cebf3"))
	column.add_child(subtitle)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	column.add_child(tabs)
	campaign_tab_button = Button.new()
	campaign_tab_button.name = "CampaignTabButton"
	campaign_tab_button.text = "CAMPAIGN"
	campaign_tab_button.custom_minimum_size = Vector2(180.0, 38.0)
	campaign_tab_button.pressed.connect(_set_deployment_mode.bind("campaign"))
	tabs.add_child(campaign_tab_button)
	skirmish_tab_button = Button.new()
	skirmish_tab_button.name = "SkirmishTabButton"
	skirmish_tab_button.text = "SKIRMISH"
	skirmish_tab_button.custom_minimum_size = Vector2(180.0, 38.0)
	skirmish_tab_button.pressed.connect(_set_deployment_mode.bind("skirmish"))
	tabs.add_child(skirmish_tab_button)

	campaign_menu_container = VBoxContainer.new()
	campaign_menu_container.name = "CampaignDeployment"
	campaign_menu_container.add_theme_constant_override("separation", 9)
	column.add_child(campaign_menu_container)
	start_menu_briefing_label = _label("SELECT A MISSION", 14, Color("#c3d8df"))
	start_menu_briefing_label.custom_minimum_size = Vector2(0.0, 28.0)
	start_menu_briefing_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	campaign_menu_container.add_child(start_menu_briefing_label)
	campaign_mission_scroll = ScrollContainer.new()
	campaign_mission_scroll.name = "CampaignMissionScroll"
	campaign_mission_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	campaign_mission_scroll.custom_minimum_size = Vector2(0.0, 184.0)
	campaign_mission_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	campaign_menu_container.add_child(campaign_mission_scroll)
	campaign_mission_list = VBoxContainer.new()
	campaign_mission_list.name = "CampaignMissionList"
	campaign_mission_list.add_theme_constant_override("separation", 6)
	campaign_mission_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	campaign_mission_scroll.add_child(campaign_mission_list)
	mission_one_button = Button.new()
	mission_one_button.name = "LevelOneButton"
	mission_one_button.custom_minimum_size = Vector2(0.0, 44.0)
	mission_one_button.text = _campaign_button_text("relay_divide")
	mission_one_button.pressed.connect(_select_campaign_level.bind("relay_divide"))
	campaign_mission_list.add_child(mission_one_button)
	mission_two_button = Button.new()
	mission_two_button.name = "LevelTwoButton"
	mission_two_button.custom_minimum_size = Vector2(0.0, 44.0)
	mission_two_button.text = _campaign_button_text("relay_crossroads")
	mission_two_button.tooltip_text = "Complete Relay Divide to unlock this mission."
	mission_two_button.pressed.connect(_select_campaign_level.bind("relay_crossroads"))
	campaign_mission_list.add_child(mission_two_button)
	campaign_mission_buttons = {"relay_divide": mission_one_button, "relay_crossroads": mission_two_button}
	if campaign_progress:
		for mission_data in campaign_progress.get_missions():
			var mission: Dictionary = mission_data
			var mission_id := str(mission.get("id", ""))
			if mission_id.is_empty() or campaign_mission_buttons.has(mission_id):
				continue
			var mission_button := Button.new()
			mission_button.name = "%sButton" % mission_id.capitalize()
			mission_button.custom_minimum_size = Vector2(0.0, 44.0)
			mission_button.text = _campaign_button_text_from_data(mission)
			mission_button.pressed.connect(_select_campaign_level.bind(mission_id))
			campaign_mission_list.add_child(mission_button)
			campaign_mission_buttons[mission_id] = mission_button
	campaign_mission_detail_label = _label("", 13, Color("#c3d8df"))
	campaign_mission_detail_label.name = "CampaignMissionDetail"
	campaign_mission_detail_label.custom_minimum_size = Vector2(0.0, 118.0)
	campaign_mission_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	campaign_menu_container.add_child(campaign_mission_detail_label)
	campaign_doctrine_option = OptionButton.new()
	campaign_doctrine_option.name = "CampaignDoctrineOption"
	campaign_doctrine_option.custom_minimum_size = Vector2(0.0, 38.0)
	campaign_doctrine_option.add_item("SELECT DOCTRINE PACKAGE")
	campaign_doctrine_option.set_item_metadata(0, "")
	if campaign_progress:
		for doctrine_value in campaign_progress.get_doctrines():
			var doctrine: Dictionary = doctrine_value
			campaign_doctrine_option.add_item(str(doctrine.get("display_name", doctrine.get("id", "DOCTRINE"))))
			campaign_doctrine_option.set_item_metadata(campaign_doctrine_option.item_count - 1, str(doctrine.get("id", "")))
	campaign_doctrine_option.item_selected.connect(_on_campaign_doctrine_selected)
	campaign_menu_container.add_child(_deployment_option_row("DOCTRINE REWARD", campaign_doctrine_option))
	campaign_start_button = Button.new()
	campaign_start_button.name = "StartCampaignButton"
	campaign_start_button.text = "START CAMPAIGN"
	campaign_start_button.custom_minimum_size = Vector2(0.0, 48.0)
	campaign_start_button.pressed.connect(_start_selected_campaign)
	campaign_menu_container.add_child(campaign_start_button)

	skirmish_menu_container = VBoxContainer.new()
	skirmish_menu_container.name = "SkirmishDeployment"
	skirmish_menu_container.add_theme_constant_override("separation", 7)
	column.add_child(skirmish_menu_container)
	var skirmish_intro := _label("Replay the authored battlefield with a selectable opponent policy. Skirmish settings do not alter campaign progress.", 13, Color("#c3d8df"))
	skirmish_intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	skirmish_intro.custom_minimum_size = Vector2(0.0, 40.0)
	skirmish_menu_container.add_child(skirmish_intro)
	skirmish_map_option = OptionButton.new()
	skirmish_map_option.name = "SkirmishMapOption"
	skirmish_map_option.custom_minimum_size = Vector2(0.0, 38.0)
	skirmish_map_option.item_selected.connect(_on_skirmish_map_selected)
	skirmish_menu_container.add_child(_deployment_option_row("MAP", skirmish_map_option))
	skirmish_scenario_option = OptionButton.new()
	skirmish_scenario_option.name = "SkirmishScenarioOption"
	skirmish_scenario_option.custom_minimum_size = Vector2(0.0, 38.0)
	skirmish_scenario_option.item_selected.connect(_on_skirmish_scenario_selected)
	skirmish_menu_container.add_child(_deployment_option_row("SCENARIO", skirmish_scenario_option))
	skirmish_difficulty_option = OptionButton.new()
	skirmish_difficulty_option.name = "SkirmishDifficultyOption"
	skirmish_difficulty_option.custom_minimum_size = Vector2(0.0, 38.0)
	for difficulty_id in AI_DIFFICULTIES:
		skirmish_difficulty_option.add_item(difficulty_id.replace("_", " ").to_upper())
		skirmish_difficulty_option.set_item_metadata(skirmish_difficulty_option.item_count - 1, difficulty_id)
	skirmish_menu_container.add_child(_deployment_option_row("AI DIFFICULTY", skirmish_difficulty_option))
	skirmish_intent_option = OptionButton.new()
	skirmish_intent_option.name = "SkirmishIntentOption"
	skirmish_intent_option.custom_minimum_size = Vector2(0.0, 38.0)
	skirmish_menu_container.add_child(_deployment_option_row("AI INTENT", skirmish_intent_option))
	skirmish_briefing_label = _label("", 13, Color("#ffd36a"))
	skirmish_briefing_label.name = "SkirmishBriefing"
	skirmish_briefing_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	skirmish_briefing_label.custom_minimum_size = Vector2(0.0, 58.0)
	skirmish_menu_container.add_child(skirmish_briefing_label)
	skirmish_deploy_button = Button.new()
	skirmish_deploy_button.name = "DeploySkirmishButton"
	skirmish_deploy_button.text = "DEPLOY SKIRMISH"
	skirmish_deploy_button.custom_minimum_size = Vector2(0.0, 52.0)
	skirmish_deploy_button.pressed.connect(_start_skirmish_from_menu)
	skirmish_menu_container.add_child(skirmish_deploy_button)

	_refresh_skirmish_menu()
	_set_deployment_mode("campaign")
	_select_campaign_level(_initial_campaign_level_id())


func _campaign_button_text(level_id: String) -> String:
	if campaign_progress:
		return _campaign_button_text_from_data(campaign_progress.get_mission(level_id))
	return level_id.replace("_", " ").to_upper()


func _campaign_button_text_from_data(mission: Dictionary) -> String:
	var mission_id := str(mission.get("id", "MISSION"))
	var display_name := str(mission.get("display_name", mission_id.replace("_", " ").capitalize())).to_upper()
	return display_name


func _campaign_button_tooltip(level_id: String, unlocked: bool) -> String:
	if not unlocked:
		return _campaign_unlock_reason(level_id)
	return "Select this mission to review its brief and available units."


func _initial_campaign_level_id() -> String:
	if campaign_progress:
		for mission_value in campaign_progress.get_missions():
			var mission: Dictionary = mission_value
			var mission_id := str(mission.get("id", ""))
			if campaign_progress.is_unlocked(mission_id):
				return mission_id
	return "relay_divide"


func _select_campaign_level(level_id: String) -> void:
	if not campaign_mission_buttons.has(level_id):
		return
	selected_campaign_level_id = level_id
	_update_campaign_mission_detail()


func _update_campaign_mission_detail() -> void:
	if not campaign_mission_detail_label or not simulation:
		return
	var mission: Dictionary = campaign_progress.get_mission(selected_campaign_level_id) if campaign_progress else {}
	var preview: Dictionary = simulation.get_campaign_level_preview(selected_campaign_level_id)
	if mission.is_empty() and preview.is_empty():
		campaign_mission_detail_label.text = "Select a campaign mission."
		if campaign_start_button:
			campaign_start_button.disabled = true
		return
	var display_name := str(mission.get("display_name", preview.get("display_name", selected_campaign_level_id.replace("_", " ").capitalize()))).to_upper()
	var brief := str(preview.get("briefing", mission.get("briefing", "Mission briefing unavailable.")))
	var allowed_units: Array = preview.get("allowed_player_units", [])
	if allowed_units.is_empty() and campaign_progress:
		allowed_units = campaign_progress.get_unlocked_content("units")
	var detail_lines := PackedStringArray([display_name, brief, "UNITS AVAILABLE  ·  %s" % _format_campaign_content(allowed_units)])
	var doctrine_id: String = campaign_progress.get_doctrine_id() if campaign_progress else ""
	var doctrine: Dictionary = campaign_progress.get_doctrine(doctrine_id) if campaign_progress and not doctrine_id.is_empty() else {}
	if not doctrine_id.is_empty():
		detail_lines.append("DOCTRINE  ·  %s  ·  %s" % [str(doctrine.get("display_name", doctrine_id)), str(doctrine.get("effect_summary", "Package active."))])
	elif campaign_progress and campaign_progress.is_doctrine_choice_unlocked():
		detail_lines.append("DOCTRINE REWARD READY  ·  Select one package; it persists through later operations.")
	else:
		detail_lines.append("DOCTRINE REWARD  ·  Complete Network Sever to unlock one persistent package.")
	var unlocked: bool = campaign_progress == null or campaign_progress.is_unlocked(selected_campaign_level_id)
	if not unlocked:
		detail_lines.append("LOCKED  ·  %s" % _campaign_unlock_reason(selected_campaign_level_id))
	elif campaign_progress and campaign_progress.mission_requires_doctrine(selected_campaign_level_id) and doctrine_id.is_empty():
		detail_lines.append("SELECT A DOCTRINE PACKAGE BEFORE STARTING THIS OPERATION.")
	campaign_mission_detail_label.text = "\n".join(detail_lines)
	if campaign_doctrine_option:
		var selected_index := 0
		for index in campaign_doctrine_option.item_count:
			if str(campaign_doctrine_option.get_item_metadata(index)) == doctrine_id and not doctrine_id.is_empty():
				selected_index = index
				break
		campaign_doctrine_option.select(selected_index)
		campaign_doctrine_option.disabled = not campaign_progress or not campaign_progress.is_doctrine_choice_unlocked() or not doctrine_id.is_empty()
	if campaign_start_button:
		var doctrine_required: bool = campaign_progress != null and campaign_progress.mission_requires_doctrine(selected_campaign_level_id)
		campaign_start_button.disabled = not unlocked or (doctrine_required and doctrine_id.is_empty())
		if not unlocked:
			campaign_start_button.tooltip_text = "Complete the prerequisite mission first."
		elif doctrine_required and doctrine_id.is_empty():
			campaign_start_button.tooltip_text = "Select a persistent doctrine package first."
		else:
			campaign_start_button.tooltip_text = "Start %s." % display_name


func _on_campaign_doctrine_selected(index: int) -> void:
	if not campaign_progress or not campaign_doctrine_option or index < 0 or index >= campaign_doctrine_option.item_count:
		return
	var doctrine_id := str(campaign_doctrine_option.get_item_metadata(index))
	if doctrine_id.is_empty():
		_update_campaign_mission_detail()
		return
	var selection: Dictionary = campaign_progress.choose_doctrine(doctrine_id, selected_campaign_level_id)
	if not bool(selection.get("valid", false)):
		if status_label:
			status_label.text = str(selection.get("reason", "Doctrine package unavailable."))
		_update_campaign_mission_detail()
		return
	if status_label:
		status_label.text = "%s selected — this package persists through later operations." % str(selection.get("display_name", doctrine_id))
	_update_campaign_mission_detail()


func _format_campaign_content(content_ids: Array) -> String:
	var labels := PackedStringArray()
	for content_value in content_ids:
		labels.append(str(content_value).replace("_", " ").capitalize())
	return "  ·  ".join(labels) if not labels.is_empty() else "NONE"


func _deployment_option_row(caption: String, option: OptionButton) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var label := _label(caption, 12, Color("#8cebf3"))
	label.custom_minimum_size = Vector2(150.0, 38.0)
	row.add_child(label)
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(option)
	return row


func _set_deployment_mode(mode: String) -> void:
	deployment_mode = "skirmish" if mode == "skirmish" else "campaign"
	if campaign_menu_container:
		campaign_menu_container.visible = deployment_mode == "campaign"
	if skirmish_menu_container:
		skirmish_menu_container.visible = deployment_mode == "skirmish"
	if campaign_tab_button:
		campaign_tab_button.disabled = deployment_mode == "campaign"
	if skirmish_tab_button:
		skirmish_tab_button.disabled = deployment_mode == "skirmish"
	if deployment_mode == "campaign":
		_update_campaign_mission_detail()


func _refresh_skirmish_menu() -> void:
	if not simulation or not skirmish_map_option or not skirmish_scenario_option:
		return
	skirmish_map_option.clear()
	var maps: Array = simulation.get_skirmish_map_catalog()
	var selected_map_index := 0
	for map_index in range(maps.size()):
		var map_data: Dictionary = maps[map_index]
		var map_id := str(map_data.get("id", ""))
		skirmish_map_option.add_item(str(map_data.get("display_name", map_id.replace("_", " ").capitalize())))
		skirmish_map_option.set_item_metadata(map_index, map_id)
		if map_id == "relay_crossroads":
			selected_map_index = map_index
	if not maps.is_empty():
		skirmish_map_option.select(selected_map_index)
	_refresh_skirmish_scenarios()
	if skirmish_difficulty_option:
		var standard_index := 0
		for index in range(skirmish_difficulty_option.item_count):
			if str(skirmish_difficulty_option.get_item_metadata(index)) == "standard":
				standard_index = index
				break
		skirmish_difficulty_option.select(standard_index)


func _refresh_skirmish_scenarios() -> void:
	if not simulation or not skirmish_map_option or not skirmish_scenario_option:
		return
	var map_id := _option_metadata(skirmish_map_option)
	skirmish_scenario_option.clear()
	var scenarios: Array = simulation.get_skirmish_scenarios_for_map(map_id)
	var selected_index := 0
	for scenario_index in range(scenarios.size()):
		var scenario: Dictionary = scenarios[scenario_index]
		var scenario_id := str(scenario.get("id", ""))
		skirmish_scenario_option.add_item(str(scenario.get("display_name", scenario_id.replace("_", " ").capitalize())))
		skirmish_scenario_option.set_item_metadata(scenario_index, scenario_id)
		if scenario_id == "network_hold":
			selected_index = scenario_index
	if not scenarios.is_empty():
		skirmish_scenario_option.select(selected_index)
	_refresh_skirmish_intents()
	_on_skirmish_scenario_selected(selected_index)


func _refresh_skirmish_intents() -> void:
	if not simulation or not skirmish_intent_option:
		return
	skirmish_intent_option.clear()
	var intents: Array = simulation.get_ai_intent_catalog()
	var selected_scenario_id := _option_metadata(skirmish_scenario_option)
	var scenario_default_intent := "secure_then_assault"
	for scenario in simulation.get_skirmish_scenario_catalog():
		var definition: Dictionary = scenario
		if str(definition.get("id", "")) == selected_scenario_id:
			scenario_default_intent = str(definition.get("default_ai_intent", scenario_default_intent))
			break
	var selected_index := 0
	for intent_index in range(intents.size()):
		var intent: Dictionary = intents[intent_index]
		var intent_id := str(intent.get("id", ""))
		skirmish_intent_option.add_item(str(intent.get("display_name", intent_id.replace("_", " ").to_upper())))
		skirmish_intent_option.set_item_metadata(intent_index, intent_id)
		if intent_id == scenario_default_intent:
			selected_index = intent_index
	if not intents.is_empty():
		skirmish_intent_option.select(selected_index)


func _on_skirmish_map_selected(_index: int) -> void:
	_refresh_skirmish_scenarios()


func _on_skirmish_scenario_selected(_index: int) -> void:
	if not simulation:
		return
	_refresh_skirmish_intents()
	if not skirmish_briefing_label:
		return
	var scenario_id := _option_metadata(skirmish_scenario_option)
	for scenario in simulation.get_skirmish_scenario_catalog():
		var definition: Dictionary = scenario
		if str(definition.get("id", "")) == scenario_id:
			var briefing := str(definition.get("briefing_message", definition.get("description", "")))
			skirmish_briefing_label.text = "%s\n%s" % [briefing, str(definition.get("player_objective", ""))]
			return


func _option_metadata(option: OptionButton) -> String:
	if option == null or option.get_selected() < 0:
		return ""
	return str(option.get_item_metadata(option.get_selected()))


func _start_skirmish_from_menu() -> void:
	var map_id := _option_metadata(skirmish_map_option)
	var selected_scenario_id := _option_metadata(skirmish_scenario_option)
	var difficulty_id := _option_metadata(skirmish_difficulty_option)
	var intent_id := _option_metadata(skirmish_intent_option)
	if map_id.is_empty() or selected_scenario_id.is_empty():
		return
	_load_skirmish_match(map_id, {
		"mode": "skirmish",
		"scenario_id": selected_scenario_id,
		"ai_difficulty": difficulty_id,
		"ai_intent": intent_id,
	})


func _build_match_result_overlay(root: Control) -> void:
	result_overlay = ColorRect.new()
	result_overlay.name = "MatchResultOverlay"
	result_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	result_overlay.color = Color(0.008, 0.025, 0.04, 0.78)
	result_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	result_overlay.visible = false
	root.add_child(result_overlay)
	result_panel = PanelContainer.new()
	result_panel.name = "MatchResultPanel"
	result_panel.set_anchors_preset(Control.PRESET_CENTER)
	result_panel.offset_left = -380.0
	result_panel.offset_right = 380.0
	result_panel.offset_top = -300.0
	result_panel.offset_bottom = 300.0
	result_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.025, 0.075, 0.1, 0.99), Color(0.96, 0.68, 0.28, 0.85)))
	result_overlay.add_child(result_panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	result_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	result_title_label = _label("VICTORY", 32, Color("#ffd36a"))
	result_title_label.name = "ResultTitle"
	column.add_child(result_title_label)
	result_mission_label = _label("", 15, Color("#8cebf3"))
	result_mission_label.name = "ResultMission"
	result_mission_label.clip_text = true
	result_mission_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(result_mission_label)
	var outcome_heading := _label("OUTCOME", 11, Color("#ffd36a"))
	outcome_heading.name = "ResultOutcomeHeading"
	column.add_child(outcome_heading)
	result_detail_label = _label("", 16, Color("#d6e7eb"))
	result_detail_label.name = "ResultDetail"
	result_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_detail_label.custom_minimum_size = Vector2(0.0, 62.0)
	column.add_child(result_detail_label)
	var report_separator := HSeparator.new()
	report_separator.name = "ResultReportSeparator"
	column.add_child(report_separator)
	var report_heading := _label("BATTLE REPORT", 11, Color("#ffd36a"))
	report_heading.name = "ResultReportHeading"
	column.add_child(report_heading)
	result_summary_label = _label("", 14, Color("#c5dadd"))
	result_summary_label.name = "ResultSummary"
	result_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_summary_label.custom_minimum_size = Vector2(0.0, 100.0)
	column.add_child(result_summary_label)
	result_receipt_label = _label("", 14, Color("#7cf1ad"))
	result_receipt_label.name = "ResultCampaignReceipt"
	result_receipt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_receipt_label.custom_minimum_size = Vector2(0.0, 44.0)
	result_receipt_label.visible = false
	column.add_child(result_receipt_label)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(buttons)
	rematch_button = Button.new()
	rematch_button.name = "RematchButton"
	rematch_button.text = "REMATCH"
	rematch_button.custom_minimum_size = Vector2(190.0, 50.0)
	rematch_button.pressed.connect(_restart_match)
	buttons.add_child(rematch_button)
	return_deployment_button = Button.new()
	return_deployment_button.name = "ReturnToDeploymentButton"
	return_deployment_button.text = "RETURN TO DEPLOYMENT"
	return_deployment_button.custom_minimum_size = Vector2(250.0, 50.0)
	return_deployment_button.pressed.connect(_return_to_deployment)
	buttons.add_child(return_deployment_button)


func _build_objective_briefing(root: Control) -> void:
	objective_briefing_overlay = ColorRect.new()
	objective_briefing_overlay.name = "ObjectiveBriefingOverlay"
	objective_briefing_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	objective_briefing_overlay.color = Color(0.008, 0.025, 0.04, 0.78)
	objective_briefing_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(objective_briefing_overlay)

	objective_briefing_panel = PanelContainer.new()
	objective_briefing_panel.name = "ObjectiveBriefingPanel"
	objective_briefing_panel.set_anchors_preset(Control.PRESET_CENTER)
	objective_briefing_panel.offset_left = -350.0
	objective_briefing_panel.offset_right = 350.0
	objective_briefing_panel.offset_top = -215.0
	objective_briefing_panel.offset_bottom = 215.0
	objective_briefing_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.025, 0.075, 0.1, 0.99), Color(0.96, 0.68, 0.28, 0.9)))
	objective_briefing_overlay.add_child(objective_briefing_panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	objective_briefing_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	objective_briefing_title_label = _label("MISSION BRIEFING", 24, Color("#ffd36a"))
	objective_briefing_title_label.name = "ObjectiveBriefingTitle"
	column.add_child(objective_briefing_title_label)
	var rule := HSeparator.new()
	column.add_child(rule)
	objective_briefing_body_label = _label("", 15, Color("#d6fbff"))
	objective_briefing_body_label.name = "ObjectiveBriefingBody"
	objective_briefing_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	objective_briefing_body_label.custom_minimum_size = Vector2(0.0, 270.0)
	column.add_child(objective_briefing_body_label)
	objective_briefing_acknowledge_button = Button.new()
	objective_briefing_acknowledge_button.name = "ObjectiveBriefingAcknowledgeButton"
	objective_briefing_acknowledge_button.text = "UNDERSTOOD — BEGIN OPERATIONS"
	objective_briefing_acknowledge_button.custom_minimum_size = Vector2(0.0, 48.0)
	objective_briefing_acknowledge_button.pressed.connect(_hide_objective_briefing)
	column.add_child(objective_briefing_acknowledge_button)
	objective_briefing_overlay.visible = false


func _show_objective_briefing() -> void:
	if not objective_briefing_overlay or not simulation:
		return
	var lines: PackedStringArray = []
	if simulation.get_match_mode() == "skirmish":
		var scenario: Dictionary = simulation.get_scenario_state("player")
		var scenario_name := str(scenario.get("display_name", "SKIRMISH")).to_upper()
		objective_briefing_title_label.text = "MISSION BRIEFING  //  %s" % scenario_name
		lines.append("PRIMARY OBJECTIVE")
		lines.append(str(scenario.get("objective_text", "Complete the authored skirmish objective.")))
		lines.append("")
		lines.append(str(scenario.get("briefing_message", scenario.get("description", ""))))
		var required_names: Array = scenario.get("required_point_names", [])
		if not required_names.is_empty():
			lines.append("")
			lines.append("OBJECTIVE SITES  //  %s" % "  +  ".join(PackedStringArray(required_names)))
		lines.append("")
		if str(scenario.get("objective_type", "")) == "defend_network":
			lines.append("Defence progress is cumulative while the chain is online. If NETWORK SEVERED appears, restore the marked sites before the failure timer expires.")
		else:
			lines.append("Keep the marked sites connected and watch the objective progress bar for interruptions.")
	else:
		var campaign: Dictionary = simulation.get_campaign_state()
		if bool(campaign.get("active", false)):
			objective_briefing_title_label.text = "MISSION BRIEFING  //  %s" % str(campaign.get("display_name", simulation.get_level_display_name())).to_upper()
			lines.append("PRIMARY OBJECTIVE")
			lines.append(str(campaign.get("objective_text", "Complete the current campaign phase.")))
			lines.append("")
			lines.append(str(campaign.get("briefing", simulation.get_level_briefing())))
			var player_faction: Dictionary = simulation.get_faction_profile("player")
			var enemy_faction: Dictionary = simulation.get_faction_profile("enemy")
			lines.append("")
			lines.append("FORCE IDENTITY  //  %s — %s" % [str(player_faction.get("display_name", "Coalition")), str(player_faction.get("doctrine", "Fortified network"))])
			lines.append("OPPOSITION  //  %s — %s" % [str(enemy_faction.get("display_name", "Frontier")), str(enemy_faction.get("doctrine", "Mobile pressure"))])
			var route_id := str(campaign.get("route_id", ""))
			if not route_id.is_empty():
				lines.append("")
				lines.append("AUTHORED ROUTE  //  %s" % route_id.replace("_", " ").to_upper())
			lines.append("")
			if str(campaign.get("objective_type", "")) == "network_hold":
				lines.append("The phase bar shows online hold progress. If the relay is contested, progress drains until the connected network is restored. Keep the marked site supplied while the counter-offensive arrives.")
			else:
				lines.append("The phase bar will show progress, alarm pressure, convoy readiness, and the next handoff. Follow the marked passes instead of crossing the mountain walls.")
		else:
			objective_briefing_title_label.text = "MISSION BRIEFING  //  %s" % simulation.get_level_display_name().to_upper()
			lines.append("PRIMARY OBJECTIVE")
			lines.append(simulation.get_level_briefing())
			var objective_text: Dictionary = simulation.get_level_objective_text()
			var first_action := str(objective_text.get("build_processor", "Follow the objective bar and yellow markers to establish your forward network."))
			lines.append("")
			lines.append("FIRST ACTION")
			lines.append(first_action)
			lines.append("")
			lines.append("The objective bar, yellow tactical-map circles, and world markers will guide you through the next step.")
	objective_briefing_body_label.text = "\n".join(lines)
	objective_briefing_visible = true
	objective_briefing_overlay.visible = true
	objective_briefing_acknowledge_button.grab_focus()


func _hide_objective_briefing() -> void:
	objective_briefing_visible = false
	if objective_briefing_overlay:
		objective_briefing_overlay.visible = false
	if status_label and simulation and not simulation.match_over:
		status_label.text = "Orders are live — follow the objective markers."


func _show_match_result(event_type: String, payload: Dictionary) -> void:
	if not result_overlay or not result_title_label or not result_detail_label:
		return
	_hide_pause_menu()
	_hide_objective_briefing()
	result_visible = true
	result_overlay.visible = true
	var won := event_type == "MatchWon"
	result_title_label.text = "VICTORY" if won else "DEFEAT"
	result_title_label.modulate = Color("#ffd36a") if won else Color("#ff7b86")
	result_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.025, 0.075, 0.1, 0.99), Color("#ffd36a") if won else Color("#ff7b86")))
	var mode_text := "SKIRMISH" if simulation.get_match_mode() == "skirmish" else "CAMPAIGN"
	result_mission_label.text = "%s  ·  %s" % [mode_text, simulation.get_level_display_name()]
	result_detail_label.text = _format_result_detail(payload)
	if result_summary_label:
		result_summary_label.text = _format_match_summary(simulation.get_match_summary())
	if result_receipt_label:
		result_receipt_label.text = ""
		result_receipt_label.visible = false
		var doctrine_state: Dictionary = simulation.get_campaign_doctrine_state()
		var doctrine_id := str(doctrine_state.get("id", ""))
		if not doctrine_id.is_empty() and simulation.get_match_mode() == "campaign":
			result_receipt_label.text = "DOCTRINE ACTIVE\n%s" % str(doctrine_state.get("display_name", doctrine_id))
			result_receipt_label.visible = true


func _format_result_detail(payload: Dictionary) -> String:
	var lines: PackedStringArray = []
	if simulation.get_match_mode() == "skirmish":
		var scenario: Dictionary = simulation.get_scenario_state("player")
		var progress_seconds := float(scenario.get("progress_seconds", 0.0))
		var target_seconds := float(scenario.get("target_seconds", scenario.get("hold_ticks", 1) * simulation.TICK_SECONDS))
		if str(scenario.get("objective_type", "")) == "defend_network":
			lines.append("NETWORK DEFENCE  %s / %s" % [_format_duration(progress_seconds), _format_duration(target_seconds)])
			if bool(scenario.get("network_online", false)):
				lines.append("NETWORK STATUS  ONLINE")
			else:
				lines.append("NETWORK STATUS  SEVERED  ·  SEVER TIMER %s / %s" % [
					_format_duration(float(scenario.get("disruption_seconds", 0.0))),
					_format_duration(float(scenario.get("sever_seconds", 0.0))),
				])
		else:
			lines.append("OBJECTIVE HOLD  %s / %s" % [_format_duration(progress_seconds), _format_duration(target_seconds)])
		var objective_text := str(scenario.get("objective_text", ""))
		if not objective_text.is_empty():
			lines.append(objective_text)
	lines.append(str(payload.get("message", "Match complete.")))
	return "\n".join(lines)


func _hide_match_result() -> void:
	result_visible = false
	if result_overlay:
		result_overlay.visible = false


func _return_to_deployment() -> void:
	_hide_match_result()
	_set_start_menu_visible(true)
	_set_deployment_mode(deployment_mode if simulation.get_match_mode() == "skirmish" else "campaign")
	_refresh_skirmish_menu()


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
			inspected_target_id = ""
			status_label.text = "%s selected — inspect its finite reserve below." % simulation.resource_nodes[clicked_resource_id]["display_name"]
			_update_selected_visuals()
			return
		var clicked_id := _entity_at_screen(pointer_position, false)
		selected_resource_id = ""
		selected_ids.clear()
		if not clicked_id.is_empty() and ((simulation.units.has(clicked_id) and simulation.units[clicked_id]["team"] == "player") or (simulation.buildings.has(clicked_id) and simulation.buildings[clicked_id]["team"] == "player")):
			inspected_target_id = ""
			selected_ids.append(clicked_id)
		elif not clicked_id.is_empty():
			inspected_target_id = clicked_id
			status_label.text = "%s inspected — left-click shows its combat readout; right-click orders an attack." % _entity_display_name(clicked_id)
			_update_selected_visuals()
			_update_hud()
			return
		else:
			inspected_target_id = ""
	else:
		selected_resource_id = ""
		selected_ids.clear()
		for entity_id in simulation.units:
			var unit: Dictionary = simulation.units[entity_id]
			if unit["team"] != "player":
				continue
			if _unit_intersects_screen_rect(str(entity_id), unit, drag_rect):
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
		inspected_target_id = clicked_id
		_flash_target_view(clicked_id)
		attack_move_mode = false
		status_label.text = "ATTACK ORDER — %s targeted." % _entity_display_name(clicked_id)
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
	var closest_score := 1.0
	for entity_id in simulation.units:
		var unit: Dictionary = simulation.units[entity_id]
		if player_only and unit["team"] != "player":
			continue
		if not player_only and unit["team"] != "player" and not simulation.is_entity_visible_to_team("player", entity_id):
			continue
		var hit_radius := 42.0 if str(unit.get("kind", "")) == "command_carrier" else 32.0
		var distance := _unit_screen_distance(str(entity_id), unit, screen_position)
		var score := distance / hit_radius
		if score < closest_score:
			closest_score = score
			closest_id = entity_id
	for entity_id in simulation.buildings:
		var building: Dictionary = simulation.buildings[entity_id]
		if player_only and building["team"] != "player":
			continue
		if not player_only and building["team"] != "player" and not simulation.is_entity_visible_to_team("player", entity_id):
			continue
		var projected := camera.unproject_position(building["position"] + Vector3.UP * 1.0)
		var distance := projected.distance_to(screen_position)
		var score := distance / 32.0
		if score < closest_score:
			closest_score = score
			closest_id = entity_id
	return closest_id


func _unit_screen_distance(entity_id: String, unit: Dictionary, screen_position: Vector2) -> float:
	if str(unit.get("kind", "")) != "command_carrier" or not unit_views.has(entity_id) or not is_instance_valid(unit_views[entity_id]):
		return camera.unproject_position(unit["position"] + Vector3.UP * 0.7).distance_to(screen_position)
	var view: Node3D = unit_views[entity_id]
	var first_endpoint := camera.unproject_position(view.global_transform * Vector3(0.0, 0.7, -3.2))
	var second_endpoint := camera.unproject_position(view.global_transform * Vector3(0.0, 0.7, 3.2))
	var nearest := Geometry2D.get_closest_point_to_segment(screen_position, first_endpoint, second_endpoint)
	return nearest.distance_to(screen_position)


func _unit_intersects_screen_rect(entity_id: String, unit: Dictionary, rectangle: Rect2) -> bool:
	if str(unit.get("kind", "")) != "command_carrier" or not unit_views.has(entity_id) or not is_instance_valid(unit_views[entity_id]):
		return rectangle.has_point(camera.unproject_position(unit["position"] + Vector3.UP * 0.6))
	var view: Node3D = unit_views[entity_id]
	for sample_index in range(7):
		var local_z := lerpf(-3.2, 3.2, float(sample_index) / 6.0)
		var projected := camera.unproject_position(view.global_transform * Vector3(0.0, 0.6, local_z))
		if rectangle.has_point(projected):
			return true
	return false


func _entity_display_name(entity_id: String) -> String:
	if simulation.units.has(entity_id):
		return str(simulation.units[entity_id].get("display_name", simulation.units[entity_id].get("kind", "UNIT")))
	if simulation.buildings.has(entity_id):
		return str(simulation.buildings[entity_id].get("display_name", simulation.buildings[entity_id].get("kind", "BUILDING")))
	return entity_id


func _flash_target_view(entity_id: String) -> void:
	if unit_views.has(entity_id) and is_instance_valid(unit_views[entity_id]):
		unit_views[entity_id].flash_target()
	elif building_views.has(entity_id) and is_instance_valid(building_views[entity_id]):
		building_views[entity_id].flash_target()


func _inspected_target_data() -> Dictionary:
	if inspected_target_id.is_empty():
		return {}
	if simulation.units.has(inspected_target_id):
		return simulation.units[inspected_target_id]
	if simulation.buildings.has(inspected_target_id):
		return simulation.buildings[inspected_target_id]
	return {}


func _target_detail(data: Dictionary) -> String:
	var health_text := "HP %d / %d" % [int(data.get("health", 0.0)), int(data.get("max_health", 0.0))]
	if data.has("kind") and simulation.unit_definitions.has(str(data["kind"])):
		var definition = simulation.unit_definitions[str(data["kind"])]
		var range_value: float = simulation.get_effective_attack_range(str(data.get("team", "enemy")), str(data["kind"]))
		var counterplay := ""
		if play_hints_enabled:
			if str(data.get("team", "")) == "enemy" and str(data.get("kind", "")) == "bulwark":
				counterplay = "\nCOUNTERPLAY  RUSH INSIDE %.1f OR FLANK  ·  KEEP FORCE SPREAD" % float(data.get("minimum_attack_range", definition.minimum_attack_range))
			elif str(data.get("team", "")) == "enemy":
				counterplay = "\nCOUNTERPLAY  FOCUS FIRE  ·  RETREAT DAMAGED UNITS TO REPAIR"
		return "TARGET %s\n%s   DMG %d   RANGE %.1f%s" % [str(data.get("display_name", data.get("kind", "UNIT"))).to_upper(), health_text, int(definition.attack_damage), range_value, counterplay]
	return "TARGET %s\n%s   STRUCTURE" % [str(data.get("display_name", data.get("kind", "BUILDING"))).to_upper(), health_text]


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


func _selected_combat_unit_ids() -> Array:
	var ids: Array = []
	for entity_id in selected_ids:
		if not simulation.units.has(entity_id):
			continue
		var unit: Dictionary = simulation.units[entity_id]
		if unit["team"] == "player" and str(unit.get("kind", "")) != "collector" and float(unit.get("attack_range", 0.0)) > 0.0:
			ids.append(str(entity_id))
	return ids


func _selected_build_source_id() -> String:
	if selected_ids.size() != 1 or not simulation.buildings.has(selected_ids[0]):
		return ""
	var building: Dictionary = simulation.buildings[selected_ids[0]]
	if building["team"] != "player" or not building["complete"]:
		return ""
	if str(building.get("kind", "")) != "command_hub" and str(building.get("kind", "")) != "forward_base":
		return ""
	return str(selected_ids[0])


func _toggle_attack_move_mode() -> void:
	var combat_ids := _selected_combat_unit_ids()
	if combat_ids.is_empty():
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
	var combat_ids := _selected_combat_unit_ids()
	if combat_ids.is_empty():
		status_label.text = "Select one or more armed units before issuing Stop."
		return
	attack_move_mode = false
	patrol_mode = false
	simulation.issue_command("stop", "player", {"entity_ids": combat_ids})
	status_label.text = "Stop order queued."


func _guard_selected_units() -> void:
	var combat_ids := _selected_combat_unit_ids()
	if combat_ids.is_empty():
		status_label.text = "Select one or more armed units before issuing Guard."
		return
	_cancel_build_mode()
	_cancel_collector_assignment(false)
	attack_move_mode = false
	patrol_mode = false
	simulation.issue_command("guard", "player", {"entity_ids": combat_ids})
	status_label.text = "GUARD order queued — units hold position and engage only inside their guard radius."


func _toggle_build_mode() -> void:
	if _selected_build_source_id().is_empty():
		status_label.text = "Select a completed Command Hub or Forward Base before building."
		return
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
	_clear_build_range_guides()
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


func _update_build_range_guides() -> void:
	if build_mode != "relay" or simulation == null or _is_dialog_open():
		_clear_build_range_guides()
		return
	var active_sources: Dictionary = {}
	for source_id_variant in simulation._get_connected_supply_source_ids("player"):
		var source_id := str(source_id_variant)
		var source_position := _network_source_position(source_id)
		if source_position == Vector3.INF:
			continue
		active_sources[source_id] = true
		var guide: Node3D
		if build_range_guides.has(source_id) and is_instance_valid(build_range_guides[source_id]):
			guide = build_range_guides[source_id]
		else:
			guide = _create_build_range_guide(source_id)
			build_range_guides[source_id] = guide
		guide.position = Vector3(source_position.x, 0.0, source_position.z)
		guide.visible = true
	for source_id in build_range_guides.keys().duplicate():
		if not active_sources.has(source_id):
			var stale_guide: Node3D = build_range_guides[source_id]
			if is_instance_valid(stale_guide):
				stale_guide.queue_free()
			build_range_guides.erase(source_id)


func _clear_build_range_guides() -> void:
	for guide_variant in build_range_guides.values():
		var guide: Node3D = guide_variant
		if is_instance_valid(guide):
			guide.queue_free()
	build_range_guides.clear()


func _network_source_position(source_id: String) -> Vector3:
	if simulation.buildings.has(source_id):
		return simulation.buildings[source_id]["position"]
	if simulation.control_points.has(source_id):
		return simulation.control_points[source_id]["position"]
	return Vector3.INF


func _create_build_range_guide(source_id: String) -> Node3D:
	var guide := Node3D.new()
	guide.name = "RelayLinkRange_%s" % source_id
	var fill_mesh := CylinderMesh.new()
	fill_mesh.top_radius = simulation.SUPPLY_LINK_RADIUS
	fill_mesh.bottom_radius = simulation.SUPPLY_LINK_RADIUS
	fill_mesh.height = 0.018
	fill_mesh.radial_segments = 96
	var fill := MeshInstance3D.new()
	fill.name = "LinkRangeArea"
	fill.mesh = fill_mesh
	fill.material_override = _material(Color(0.12, 0.82, 0.92, 0.045), 0.5, 0.05)
	fill.position.y = 0.025
	guide.add_child(fill)
	var ring_mesh := TorusMesh.new()
	ring_mesh.outer_radius = simulation.SUPPLY_LINK_RADIUS
	ring_mesh.inner_radius = simulation.SUPPLY_LINK_RADIUS - 0.18
	ring_mesh.rings = 96
	ring_mesh.ring_segments = 8
	var ring := MeshInstance3D.new()
	ring.name = "LinkRangeRing"
	ring.mesh = ring_mesh
	ring.material_override = _emissive_material(Color("#52e7ef"), 1.25)
	ring.position.y = 0.08
	guide.add_child(ring)
	add_child(guide)
	return guide


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
			status_label.text = "Click an available Energy Field to choose a source."
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
		if not simulation.is_position_explored_by_team("player", node["position"]):
			continue
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
		if not simulation.is_position_explored_by_team("player", point["position"]):
			continue
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
	elif (action == "research" or action.begins_with("research:")) and selected_ids.size() == 1:
		var technology_id := "advanced_targeting" if action == "research" else action.trim_prefix("research:")
		simulation.issue_command("research", "player", {"building_id": selected_ids[0], "technology_id": technology_id})
	elif action == "upgrade" and selected_ids.size() == 1:
		simulation.issue_command("upgrade", "player", {"building_id": selected_ids[0]})
	elif action == "deploy" and selected_ids.size() == 1:
		simulation.issue_command("deploy", "player", {"unit_id": str(selected_ids[0])})
	elif action == "collector_route":
		_begin_collector_assignment()
	elif action == "unit_guard":
		_guard_selected_units()
	elif action == "unit_attack_move":
		_toggle_attack_move_mode()
	elif action == "unit_stop":
		_stop_selected_units()
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
	if selected_ids.size() != 1 or not simulation.buildings.has(selected_ids[0]):
		status_label.text = "Select a friendly building to repair nearby damaged units."
		return
	var building_id := str(selected_ids[0])
	var status: Dictionary = simulation.get_building_repair_status("player", building_id)
	if not bool(status.get("available", false)):
		status_label.text = "Select a completed friendly building before repairing."
		return
	if not bool(status.get("building_damaged", false)) and status.get("nearby_unit_ids", []).is_empty():
		status_label.text = "Move damaged units inside this building's green repair circle first."
		return
	simulation.issue_command("repair", "player", {"building_id": building_id})
	status_label.text = "Repair order queued from %s — all nearby damaged units will repair at the building." % simulation.buildings[building_id]["display_name"]


func _has_damaged_selection() -> bool:
	for entity_id in selected_ids:
		if simulation.buildings.has(entity_id) and float(simulation.buildings[entity_id]["health"]) < float(simulation.buildings[entity_id]["max_health"]):
			return true
	return false


func _process_camera_input(delta: float) -> void:
	if pause_menu_visible:
		return
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
	var viewport_rect := get_viewport().get_visible_rect()
	var edge_scroll_allowed := pointer_inside_viewport and not dragging and not _is_dialog_open() and viewport_rect.has_point(pointer_position) and not _pointer_over_ui()
	if edge_scroll_allowed:
		var edge_margin := 16.0
		if pointer_position.x < viewport_rect.position.x + edge_margin:
			camera_target.x -= delta * 18.0
		elif pointer_position.x > viewport_rect.end.x - edge_margin:
			camera_target.x += delta * 18.0
		if pointer_position.y < viewport_rect.position.y + edge_margin:
			camera_target.z -= delta * 18.0
		elif pointer_position.y > viewport_rect.end.y - edge_margin:
			camera_target.z += delta * 18.0
	var bounds: Vector2 = simulation.get_level_bounds() if simulation else Vector2(MAP_HALF_WIDTH, MAP_HALF_DEPTH)
	camera_target.x = clamp(camera_target.x, -bounds.x * CAMERA_TARGET_X_FACTOR, bounds.x * CAMERA_TARGET_X_FACTOR)
	camera_target.z = clamp(camera_target.z, -bounds.y * CAMERA_TARGET_Z_FACTOR, bounds.y * CAMERA_TARGET_Z_FACTOR)



func _update_camera() -> void:
	var offset := Vector3(sin(camera_yaw) * camera_distance, camera_distance * camera_pitch, cos(camera_yaw) * camera_distance)
	camera.global_position = camera_target + offset
	camera.look_at(camera_target, Vector3.UP)
	if minimap:
		minimap.set_camera_view(camera_target, camera_distance)


func _sync_views(frame_delta: float = 0.0) -> void:
	var state: Dictionary = simulation.get_state("player")
	for selected_id in selected_ids.duplicate():
		if not state["units"].has(selected_id) and not state["buildings"].has(selected_id):
			selected_ids.erase(selected_id)
	if not inspected_target_id.is_empty() and not state["units"].has(inspected_target_id) and not state["buildings"].has(inspected_target_id):
		inspected_target_id = ""
	if not state["resource_nodes"].has(selected_resource_id):
		selected_resource_id = ""
	WorldViewSynchronizerScript.sync(self, state, selected_ids, unit_views, building_views, control_views, resource_views, selected_resource_id, objective_target_point_ids, minimap, frame_delta)
	_sync_campaign_markers(state)
	var terrain: Dictionary = simulation.get_level_terrain()
	for entity_id in unit_views:
		if state["units"].has(entity_id):
			var unit_view = unit_views[entity_id]
			unit_view.apply_terrain_height(WorldBuilderScript.terrain_height_at(terrain, unit_view.global_position), frame_delta)
	if world_shell:
		WorldBuilderScript.sync_scenery_visibility(world_shell, state.get("visibility", {}))
	if fog_view:
		fog_view.sync(state.get("visibility", {}))
	if minimap:
		minimap.set_selection(selected_ids, selected_resource_id, objective_target_point_ids)


func _sync_campaign_markers(state: Dictionary) -> void:
	if not world_shell:
		return
	var active_markers: Dictionary = {}
	var campaign: Dictionary = state.get("campaign", {})
	if bool(campaign.get("active", false)):
		var phase_id := str(campaign.get("phase_id", "phase"))
		var objective_type := str(campaign.get("objective_type", ""))
		var mission_items: Dictionary = state.get("mission_items", {})
		var final_destination_position: Vector3 = campaign.get("final_destination_position", Vector3.INF)
		if bool(campaign.get("final_destination_revealed", false)) and final_destination_position != Vector3.INF and objective_type != "reach":
			_add_campaign_marker(active_markers, {
				"id": "%s:final-destination" % phase_id,
				"type": "objective",
				"position": final_destination_position,
				"label": "EXFIL  //  FINAL DESTINATION",
				"color": Color("#ffd36a"),
				"radius": 3.6,
			})
		var breach_position: Vector3 = campaign.get("detection_source_position", Vector3.INF)
		if bool(campaign.get("detected", false)) and breach_position != Vector3.INF:
			var breach_kind := str(campaign.get("detection_source_kind", ""))
			var breach_label := "SENSOR GRID BREACHED" if breach_kind == "sensor_mast" else "CONTACT"
			_add_campaign_marker(active_markers, {
				"id": "%s:sensor-breach" % phase_id,
				"type": "breach",
				"position": breach_position,
				"label": breach_label,
				"color": Color("#ff5964"),
				"radius": 3.2,
			})
		if objective_type == "collect_items":
			for item_id_value in campaign.get("item_ids", []):
				var item_id := str(item_id_value)
				var item: Dictionary = mission_items.get(item_id, {})
				if item.is_empty() or bool(item.get("collected", false)):
					continue
				_add_campaign_marker(active_markers, {
					"id": "%s:item:%s" % [phase_id, item_id],
					"type": "item",
					"position": item.get("position", Vector3.ZERO),
					"label": "RECOVER  //  %s" % str(item.get("display_name", item_id)).to_upper(),
					"color": Color("#7cf1ad"),
					"radius": 2.5,
				})
		if objective_type == "destroy_targets":
			var target_index := 0
			for target_position_value in campaign.get("target_positions", []):
				var target_position: Vector3 = target_position_value
				_add_campaign_marker(active_markers, {
					"id": "%s:target:%d" % [phase_id, target_index],
					"type": "target",
					"position": target_position,
					"label": "DISABLE  //  RELAY %d" % (target_index + 1),
					"color": Color("#ff8066"),
					"radius": 3.4,
				})
				target_index += 1
		if objective_type == "network_hold":
			var network_index := 0
			for target_position_value in campaign.get("target_positions", []):
				var network_position: Vector3 = target_position_value
				_add_campaign_marker(active_markers, {
					"id": "%s:network:%d" % [phase_id, network_index],
					"type": "defend",
					"position": network_position,
					"label": "HOLD  //  NETWORK %s" % ("ONLINE" if bool(campaign.get("network_online", false)) else "CONTESTED"),
					"color": Color("#7cf1ad") if bool(campaign.get("network_online", false)) else Color("#ff8066"),
					"radius": 4.5,
				})
				network_index += 1
		if objective_type in ["reach", "escort", "deploy"]:
			var phase_position: Vector3 = campaign.get("target_position", Vector3.INF)
			if phase_position != Vector3.INF:
				var phase_label := "REACH  //  EXTRACTION" if objective_type == "reach" else "DEPLOY  //  FORWARD BASE" if objective_type == "deploy" else "CONVOY  //  ARRIVAL"
				var phase_color := Color("#ffd36a") if objective_type != "deploy" else Color("#7ce7ff")
				_add_campaign_marker(active_markers, {
					"id": "%s:phase-target" % phase_id,
					"type": "deploy" if objective_type == "deploy" else "objective",
					"position": phase_position,
					"label": phase_label,
					"color": phase_color,
					"radius": 4.0 if objective_type == "deploy" else 3.0,
				})
		if objective_type == "escort":
			var route_id := str(campaign.get("route_id", ""))
			var route: Dictionary = simulation.get_level_route(route_id)
			var route_points: Array = route.get("waypoints", [])
			var next_checkpoint := int(campaign.get("route_checkpoint", 1))
			if route_points.size() > 1 and next_checkpoint < route_points.size():
				var checkpoint_position: Vector3 = simulation._level_vector3(route_points[next_checkpoint])
				_add_campaign_marker(active_markers, {
					"id": "%s:route-checkpoint" % phase_id,
					"type": "route",
					"position": checkpoint_position,
					"label": "PASS %02d  //  %s" % [next_checkpoint, str(route.get("display_name", route_id)).to_upper()],
					"color": Color("#ffd36a"),
					"radius": 2.7,
				})
		if objective_type in ["build_structures", "defend"]:
			var forward_base_id := str(campaign.get("forward_base_id", ""))
			var buildings: Dictionary = state.get("buildings", {})
			if buildings.has(forward_base_id):
				var forward_base: Dictionary = buildings[forward_base_id]
				_add_campaign_marker(active_markers, {
					"id": "%s:forward-base" % phase_id,
					"type": "defend" if objective_type == "defend" else "objective",
					"position": forward_base.get("position", Vector3.ZERO),
					"label": "HOLD  //  FORWARD BASE" if objective_type == "defend" else "BUILD  //  FORWARD BASE PERIMETER",
					"color": Color("#7ce7ff"),
					"radius": 4.5 if objective_type == "defend" else 3.0,
				})
	for marker_id in campaign_marker_views.keys().duplicate():
		if not active_markers.has(marker_id):
			var stale_view = campaign_marker_views[marker_id]
			if is_instance_valid(stale_view):
				stale_view.queue_free()
			campaign_marker_views.erase(marker_id)
	for marker_id in active_markers:
		var marker_data: Dictionary = active_markers[marker_id]
		if not campaign_marker_views.has(marker_id):
			var marker_view = CampaignMarkerViewScript.new()
			marker_view.name = "CampaignMarker_%s" % str(marker_id).replace(":", "_")
			world_shell.add_child(marker_view)
			marker_view.setup(marker_data)
			campaign_marker_views[marker_id] = marker_view
		else:
			campaign_marker_views[marker_id].sync(marker_data)


func _add_campaign_marker(active_markers: Dictionary, marker_data: Dictionary) -> void:
	var marker_id := str(marker_data.get("id", ""))
	if marker_id.is_empty():
		return
	active_markers[marker_id] = marker_data


func _on_minimap_world_position_clicked(world_position: Vector3) -> void:
	var bounds: Vector2 = simulation.get_level_bounds() if simulation else Vector2(MAP_HALF_WIDTH, MAP_HALF_DEPTH)
	camera_target = Vector3(
		clamp(world_position.x, -bounds.x * CAMERA_TARGET_X_FACTOR, bounds.x * CAMERA_TARGET_X_FACTOR),
		0.0,
		clamp(world_position.z, -bounds.y * CAMERA_TARGET_Z_FACTOR, bounds.y * CAMERA_TARGET_Z_FACTOR)
	)
	_update_camera()
	if status_label and not start_menu_visible:
		status_label.text = "TACTICAL MAP — camera moved to %d, %d." % [int(world_position.x), int(world_position.z)]


func _create_control_view(point: Dictionary) -> Node3D:
	return WorldViewSynchronizerScript.create_control_view(self, point)


func _update_control_view(view: Node3D, point: Dictionary) -> void:
	WorldViewSynchronizerScript.update_control_view(view, point, objective_target_point_ids)


func _update_selected_visuals() -> void:
	for entity_id in unit_views:
		unit_views[entity_id].selection_disc.visible = selected_ids.has(entity_id)
	for entity_id in building_views:
		building_views[entity_id].set_selected(selected_ids.has(entity_id))


func _clear_match_views() -> void:
	_clear_build_range_guides()
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
	for view in campaign_marker_views.values():
		if is_instance_valid(view):
			view.queue_free()
	unit_views.clear()
	building_views.clear()
	control_views.clear()
	resource_views.clear()
	campaign_marker_views.clear()


func _restart_match() -> void:
	_hide_pause_menu()
	_hide_match_result()
	_hide_objective_briefing()
	_cancel_build_mode()
	_cancel_collector_assignment(false)
	attack_move_mode = false
	patrol_mode = false
	selected_ids.clear()
	selected_resource_id = ""
	inspected_target_id = ""
	objective_target_point_id = ""
	objective_target_point_ids = []
	control_groups.clear()
	event_log_label.text = "EVENT LOG\nAwaiting orders..."
	_clear_combat_feedback()
	status_label.modulate = Color("#c3d8df")
	camera_yaw = 0.0
	_clear_match_views()
	simulation.restart_match()
	camera_target = _starting_camera_target()
	_update_selected_visuals()
	_sync_views()
	_update_hud()
	_show_objective_briefing()


func _start_selected_campaign() -> void:
	if selected_campaign_level_id.is_empty():
		return
	if campaign_progress and not campaign_progress.is_unlocked(selected_campaign_level_id):
		status_label.text = _campaign_unlock_reason(selected_campaign_level_id)
		_update_campaign_mission_detail()
		return
	if campaign_progress and campaign_progress.mission_requires_doctrine(selected_campaign_level_id) and campaign_progress.get_doctrine_id().is_empty():
		status_label.text = "Select a persistent doctrine package before starting this operation."
		_update_campaign_mission_detail()
		return
	_load_campaign_level(selected_campaign_level_id)


func _load_campaign_level(level_id: String) -> void:
	if campaign_progress and not campaign_progress.is_unlocked(level_id):
		status_label.text = _campaign_unlock_reason(level_id)
		return
	_hide_pause_menu()
	_hide_match_result()
	_cancel_build_mode()
	_cancel_collector_assignment(false)
	attack_move_mode = false
	patrol_mode = false
	selected_ids.clear()
	inspected_target_id = ""
	objective_target_point_id = ""
	objective_target_point_ids = []
	control_groups.clear()
	_clear_combat_feedback()
	_clear_match_views()
	var doctrine_state: Dictionary = campaign_progress.get_doctrine_state() if campaign_progress else {}
	simulation.start_match(level_id, "", {"mode": "campaign", "campaign_doctrine": doctrine_state})
	_set_deployment_mode("campaign")
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
	_show_objective_briefing()


func _campaign_unlock_reason(level_id: String) -> String:
	if not campaign_progress:
		return "Campaign mission unavailable."
	for mission_data in campaign_progress.get_missions():
		var mission: Dictionary = mission_data
		if str(mission.get("unlock_on_complete", "")) == level_id:
			var prerequisite_id := str(mission.get("id", ""))
			var prerequisite_name := prerequisite_id.replace("_", " ").capitalize()
			for candidate_data in campaign_progress.get_missions():
				var candidate: Dictionary = candidate_data
				if str(candidate.get("id", "")) == prerequisite_id:
					prerequisite_name = str(candidate.get("display_name", prerequisite_name))
					break
			return "Complete %s to unlock this mission." % prerequisite_name
	return "This campaign mission is locked."


func _load_skirmish_match(level_id: String, settings: Dictionary) -> void:
	_hide_pause_menu()
	_hide_match_result()
	_cancel_build_mode()
	_cancel_collector_assignment(false)
	attack_move_mode = false
	patrol_mode = false
	selected_ids.clear()
	selected_resource_id = ""
	inspected_target_id = ""
	objective_target_point_id = ""
	objective_target_point_ids = []
	control_groups.clear()
	_clear_combat_feedback()
	_clear_match_views()
	simulation.start_match(level_id, "", settings)
	_set_deployment_mode("skirmish")
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
	_show_objective_briefing()


func _set_start_menu_visible(visible: bool) -> void:
	start_menu_visible = visible
	if visible:
		_hide_pause_menu()
		_hide_objective_briefing()
	if start_menu_overlay:
		start_menu_overlay.visible = visible
	if start_menu_panel:
		start_menu_panel.visible = visible
	if visible and status_label and simulation and not simulation.match_over:
		status_label.text = "Select a deployment to begin the match."

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
	var fallback_target := Vector3.ZERO
	for building_id in simulation.buildings:
		var building: Dictionary = simulation.buildings[building_id]
		if building["team"] == "player" and building["kind"] == "command_hub":
			var bounds: Vector2 = simulation.get_level_bounds()
			var position: Vector3 = building["position"]
			return Vector3(clamp(position.x, -bounds.x * CAMERA_TARGET_X_FACTOR, bounds.x * CAMERA_TARGET_X_FACTOR), 0.0, clamp(position.z, -bounds.y * CAMERA_TARGET_Z_FACTOR, bounds.y * CAMERA_TARGET_Z_FACTOR))
		if fallback_target == Vector3.ZERO and building["team"] == "player" and building["kind"] == "forward_base":
			fallback_target = building["position"]
	if fallback_target != Vector3.ZERO:
		var fallback_bounds: Vector2 = simulation.get_level_bounds()
		return Vector3(clamp(fallback_target.x, -fallback_bounds.x * CAMERA_TARGET_X_FACTOR, fallback_bounds.x * CAMERA_TARGET_X_FACTOR), 0.0, clamp(fallback_target.z, -fallback_bounds.y * CAMERA_TARGET_Z_FACTOR, fallback_bounds.y * CAMERA_TARGET_Z_FACTOR))
	for unit_id in simulation.units:
		var unit: Dictionary = simulation.units[unit_id]
		if unit.get("team", "") == "player":
			return unit["position"]
	return Vector3.ZERO


func _mission_text(key: String, values: Dictionary = {}) -> String:
	var text := str(simulation.get_level_objective_text().get(key, ""))
	for replacement_key in values:
		text = text.replace("{%s}" % str(replacement_key), str(values[replacement_key]))
	return text


func _set_objective(key: String, values: Dictionary = {}, target_point_id := "") -> void:
	objective_target_point_id = target_point_id
	objective_target_point_ids = [] if target_point_id.is_empty() else [target_point_id]
	var text := _mission_text(key, values)
	objective_label.text = "OBJECTIVE: %s" % text if not text.is_empty() else "OBJECTIVE"


func _update_objective() -> void:
	if not objective_label or not simulation:
		return
	if simulation.match_over:
		objective_target_point_id = ""
		objective_target_point_ids = []
		if simulation.get_match_mode() == "skirmish":
			var scenario_result: Dictionary = simulation.get_scenario_state("player")
			objective_label.text = "OBJECTIVE COMPLETE — %s" % str(scenario_result.get("result_reason", "Network objective resolved.")) if simulation.match_winner == "player" else "OBJECTIVE FAILED — %s" % str(scenario_result.get("result_reason", "Network objective lost."))
		else:
			var campaign_result: Dictionary = simulation.get_campaign_state()
			var campaign_reason := str(campaign_result.get("result_reason", ""))
			if campaign_reason.is_empty():
				campaign_reason = _mission_text("match_complete")
			objective_label.text = "OBJECTIVE COMPLETE — %s" % campaign_reason if simulation.match_winner == "player" else "OBJECTIVE FAILED — %s" % campaign_reason
		return
	if simulation.get_match_mode() == "skirmish":
		_update_skirmish_objective()
		return
	var campaign: Dictionary = simulation.get_campaign_state()
	if bool(campaign.get("active", false)):
		_update_campaign_objective(campaign)
		return
	if _find_player_building("refinery").is_empty():
		_set_objective("build_processor")
		return
	var collector_id := _find_player_collector()
	if collector_id.is_empty():
		_set_objective("collector_missing")
		return
	var collector: Dictionary = simulation.units[collector_id]
	if str(collector.get("collector_state", "")) == "unassigned" or str(collector.get("collector_state", "")) == "awaiting_source":
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
	var tech_available: bool = simulation.is_team_allowed("player", "buildings", "tech_centre")
	if tech_available:
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
	if simulation.is_team_allowed("player", "units", "bulwark") and not has_bulwark:
		_set_objective("bulwark")
	else:
		_set_objective("destroy_hq")


func _update_skirmish_objective() -> void:
	var scenario: Dictionary = simulation.get_scenario_state("player")
	var required_points: Array = scenario.get("required_point_ids", [])
	objective_target_point_ids = required_points.duplicate()
	objective_target_point_id = str(required_points[0]) if not required_points.is_empty() else ""
	var objective_text := str(scenario.get("objective_text", "Hold the required network points."))
	objective_label.text = "OBJECTIVE  ·  %s  —  %s" % [str(scenario.get("display_name", "SKIRMISH")).to_upper(), objective_text]


func _update_campaign_objective(campaign: Dictionary) -> void:
	objective_target_point_id = ""
	objective_target_point_ids = []
	var phase_name := str(campaign.get("phase_display_name", "OBJECTIVE")).to_upper()
	var objective_text := str(campaign.get("objective_text", "Complete the current campaign phase."))
	if bool(campaign.get("detected", false)):
		var detection_label := "SENSOR GRID BREACHED" if str(campaign.get("detection_source_kind", "")) == "sensor_mast" else "CONTACT"
		objective_text += "  ·  %s — BREAK CONTACT" % detection_label
	objective_label.text = "OBJECTIVE  ·  %s  —  %s" % [phase_name, objective_text]
	objective_label.modulate = Color("#ff7b86") if bool(campaign.get("detected", false)) else Color("#ffd36a")


func _update_scenario_progress_hud() -> void:
	if not scenario_progress_label or not simulation:
		if scenario_progress_label:
			scenario_progress_label.text = ""
		return
	if simulation.get_match_mode() != "skirmish":
		var campaign: Dictionary = simulation.get_campaign_state()
		if not bool(campaign.get("active", false)):
			scenario_progress_label.text = ""
			return
			var campaign_progress_value := int(float(campaign.get("progress", 0.0)))
			var campaign_target_value := int(float(campaign.get("target", 0.0)))
			var campaign_text := "PROGRESS %d/%d" % [campaign_progress_value, campaign_target_value]
			if str(campaign.get("objective_type", "")) == "network_hold":
				campaign_text += "  ·  %s" % ("NETWORK ONLINE" if bool(campaign.get("network_online", false)) else "NETWORK CONTESTED")
			var campaign_route := str(campaign.get("route_id", ""))
			if not campaign_route.is_empty():
				campaign_text += "  ·  ROUTE %s" % campaign_route.replace("_", " ").to_upper()
				var route_checkpoint_count := int(campaign.get("route_checkpoint_count", 0))
				if route_checkpoint_count > 0:
					campaign_text += " %d/%d" % [int(campaign.get("route_checkpoint", 0)), route_checkpoint_count]
			var alarm_limit_seconds := float(campaign.get("alarm_limit_seconds", 0.0))
			if alarm_limit_seconds > 0.0:
				campaign_text += "  ·  ALARM %s/%s" % [_format_duration(float(campaign.get("alarm_seconds", 0.0))), _format_duration(alarm_limit_seconds)]
			scenario_progress_label.text = campaign_text
		scenario_progress_label.modulate = Color("#ffbf6a") if bool(campaign.get("detected", false)) else Color("#8cebf3")
		if bool(campaign.get("deployment_ready", false)):
			scenario_progress_label.text += "  ·  DEPLOY READY"
			scenario_progress_label.modulate = Color("#7cf1ad")
		if bool(campaign.get("detected", false)):
			var detection_label := "SENSOR GRID BREACHED" if str(campaign.get("detection_source_kind", "")) == "sensor_mast" else "CONTACT"
			scenario_progress_label.text += "  ·  %s" % detection_label
			scenario_progress_label.modulate = Color("#ff7b86")
		return
	var scenario: Dictionary = simulation.get_scenario_state("player")
	if str(scenario.get("objective_type", "")) == "defend_network":
		var defence_seconds := float(scenario.get("progress_seconds", 0.0))
		var target_seconds := float(scenario.get("target_seconds", 90.0))
		var sever_seconds := float(scenario.get("disruption_seconds", 0.0))
		var sever_limit_seconds := float(scenario.get("sever_seconds", 15.0))
		if bool(scenario.get("network_online", false)):
			scenario_progress_label.text = "NETWORK ONLINE  ·  DEFENCE %s / %s" % [_format_duration(defence_seconds), _format_duration(target_seconds)]
			scenario_progress_label.modulate = Color("#7cf1ad")
		else:
			scenario_progress_label.text = "NETWORK SEVERED  ·  DEFENCE %s / %s  ·  SEVER TIMER %s / %s" % [
				_format_duration(defence_seconds),
				_format_duration(target_seconds),
				_format_duration(sever_seconds),
				_format_duration(sever_limit_seconds),
			]
			scenario_progress_label.modulate = Color("#ff7b86")
		return
	var progress_seconds := int(float(scenario.get("progress_seconds", 0.0)))
	var hold_seconds := int(float(scenario.get("hold_ticks", 900)) * simulation.TICK_SECONDS)
	var minutes := int(progress_seconds / 60)
	var seconds := progress_seconds % 60
	var hold_minutes := int(hold_seconds / 60)
	var hold_remainder := hold_seconds % 60
	var state_text := "HOLDING" if bool(scenario.get("holding", false)) else "INTERRUPTED"
	scenario_progress_label.text = "HOLD %02d:%02d / %02d:%02d  ·  %s" % [minutes, seconds, hold_minutes, hold_remainder, state_text]
	scenario_progress_label.modulate = Color("#7cf1ad") if bool(scenario.get("holding", false)) else Color("#ffbf6a")


func _update_hud() -> void:
	if not simulation:
		return
	if status_label:
		status_label.visible = play_hints_enabled
	if event_log_label:
		event_log_label.visible = game_log_enabled
	_update_objective()
	_update_scenario_progress_hud()
	if match_context_label:
		var mode_text := "SKIRMISH" if simulation.get_match_mode() == "skirmish" else "CAMPAIGN"
		var context_text := mode_text
		if simulation.get_match_mode() == "skirmish":
			var scenario: Dictionary = simulation.get_scenario_state("player")
			context_text += "  //  " + str(scenario.get("display_name", "NETWORK HOLD")).to_upper()
		else:
			context_text += "  //  " + simulation.get_level_display_name().to_upper()
		var player_faction: Dictionary = simulation.get_faction_profile("player")
		var enemy_faction: Dictionary = simulation.get_faction_profile("enemy")
		context_text += "  //  %s vs %s" % [str(player_faction.get("display_name", "COALITION")).to_upper(), str(enemy_faction.get("display_name", "FRONTIER")).to_upper()]
		match_context_label.text = context_text
		match_context_label.tooltip_text = "Current deployment: %s" % context_text
	if match_time_label:
		match_time_label.text = "TIME %s" % _format_duration(float(simulation.current_tick) * simulation.TICK_SECONDS)
	var storage: Dictionary = simulation.get_storage_summary("player")
	var storage_capacity: int = int(storage.get("capacity", 0.0))
	if storage_capacity > 0:
		credits_label.add_theme_font_size_override("font_size", 13)
		credits_label.text = "CREDITS %d/%d" % [int(storage.get("credits", simulation.player_credits)), storage_capacity]
		credits_label.tooltip_text = "Stored resources: %d/%d. Build a Storage Silo when the Processor is full." % [int(storage.get("credits", simulation.player_credits)), storage_capacity]
		credits_label.modulate = Color("#ff8b8b") if bool(storage.get("full", false)) else Color("#ffd36a")
	else:
		credits_label.add_theme_font_size_override("font_size", 14)
		credits_label.text = "CREDITS %03d" % int(simulation.player_credits)
		credits_label.tooltip_text = "Available credits. Collector deliveries and connected territory add to this total."
		credits_label.modulate = Color("#ffd36a")
	var territory: Dictionary = simulation.get_territory_summary()
	territory_label.text = "TERRITORY %d/%d  ·  +%d C/S" % [territory["player"], territory["total"], int(territory.get("player_income_per_second", 0.0))]
	territory_label.tooltip_text = _territory_tooltip(territory)
	var supply: Dictionary = simulation.get_supply_summary("player")
	var unsupplied_units: int = int(supply["unsupplied_units"])
	var supply_state := "CONNECTED"
	if unsupplied_units > 0:
		supply_state = "%d UNSUPPLIED" % unsupplied_units
	supply_label.text = "SUPPLY %s" % supply_state
	var supply_accent := Color("#ffbf6a") if unsupplied_units > 0 else Color("#7cf1ad")
	supply_label.modulate = supply_accent
	if top_status_icons.has("SupplyChip"):
		top_status_icons["SupplyChip"].set_icon("route", supply_accent)
	supply_label.tooltip_text = "Connected units are within the Hub, Relay, or connected forward-base network. Unsupplied units move and fire at reduced effectiveness."
	var limits: Dictionary = simulation.get_limit_summary("player")
	var unit_limits: Dictionary = limits["units"]
	var force_total := int(unit_limits["current"]) + int(unit_limits["queued"])
	force_label.text = "FORCE %d/%d" % [force_total, int(unit_limits["max"])]
	var force_accent := Color("#ff7b86") if force_total >= int(unit_limits["max"]) else Color("#c3d8df")
	force_label.modulate = force_accent
	if top_status_icons.has("ForceChip"):
		top_status_icons["ForceChip"].set_icon("mixed", force_accent)
	for mission_id in campaign_mission_buttons:
		var mission_button: Button = campaign_mission_buttons[mission_id]
		var mission_unlocked: bool = campaign_progress == null or campaign_progress.is_unlocked(str(mission_id))
		# Locked missions remain selectable so the player can see what is ahead;
		# only START CAMPAIGN is gated.
		mission_button.disabled = false
		mission_button.tooltip_text = _campaign_button_tooltip(str(mission_id), mission_unlocked)
	_update_campaign_mission_detail()
	if simulation.match_over:
		_cancel_build_mode()
		_cancel_collector_assignment(false)

	var selected_text := "NO SELECTION\nSelect units, a structure, or an Energy Field"
	var selected_icon_key := "unit"
	var selected_icon_accent := Color("#8cebf3")
	if not selected_resource_id.is_empty() and simulation.resource_nodes.has(selected_resource_id):
		var resource_summary: Dictionary = simulation.get_resource_summary(selected_resource_id)
		var resource_state := "DEPLETED" if bool(resource_summary.get("depleted", false)) else "%d%% REMAINING" % int(float(resource_summary.get("percent_remaining", 0.0)) * 100.0)
		selected_text = "%s\nENERGY %d / %d   %s" % [str(resource_summary.get("display_name", "ENERGY FIELD")).to_upper(), int(resource_summary.get("remaining", 0.0)), int(resource_summary.get("initial_remaining", 0.0)), resource_state]
		selected_icon_key = "resource"
		selected_icon_accent = Color("#ffd36a")
	elif not selected_ids.is_empty():
		var first_id: String = selected_ids[0]
		var selected_data: Dictionary = simulation.units.get(first_id, simulation.buildings.get(first_id, {}))
		if not selected_data.is_empty():
			var selection_detail := _selection_detail(selected_data)
			if selected_ids.size() > 1:
				selection_detail += "\n" + _selection_composition()
			selected_text = "%s\n%s" % [_selection_title(), selection_detail]
			selected_icon_key = _selection_icon_key(selected_data)
			selected_icon_accent = Color("#8cebf3")
	var inspected_data := _inspected_target_data()
	if not inspected_data.is_empty() and selected_resource_id.is_empty():
		var target_text := _target_detail(inspected_data)
		if selected_ids.is_empty():
			selected_text = target_text
		else:
			selected_text += "\n" + target_text
			selected_icon_key = _selection_icon_key(inspected_data, true)
			selected_icon_accent = Color("#ff7b86")
	if not selected_ids.is_empty() and selected_resource_id.is_empty():
		var compact_data: Dictionary = simulation.units.get(str(selected_ids[0]), simulation.buildings.get(str(selected_ids[0]), {}))
		if not compact_data.is_empty():
			selected_label.text = _selection_card_text(compact_data)
		else:
			selected_label.text = selected_text
	else:
		selected_label.text = selected_text
	selected_label.tooltip_text = selected_text
	if selected_icon:
		selected_icon.set_icon(selected_icon_key, selected_icon_accent)
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
		lines.append("Active staging sites: %d — forward rally support available" % staging_sites)
	if lines.size() == 1:
		lines.append("Capture a point to unlock its authored strategic role.")
	return "\n".join(lines)


func _format_duration(seconds: float) -> String:
	var total_seconds: int = maxi(0, int(floor(seconds)))
	return "%02d:%02d" % [int(total_seconds / 60), total_seconds % 60]


func _format_match_summary(summary: Dictionary) -> String:
	var collector_income := int(round(float(summary.get("player_credits_from_collectors", 0.0))))
	var territory_income := int(round(float(summary.get("player_credits_from_territory", 0.0))))
	var total_income := collector_income + territory_income
	var lines: PackedStringArray = []
	lines.append("TIME %s    TERRITORY %d / %d" % [
		_format_duration(float(summary.get("duration_seconds", 0.0))),
		int(summary.get("player_territory", 0)),
		int(summary.get("territory_total", 0)),
	])
	lines.append("INCOME +%d C    FIELD %d C    TERRITORY +%d C/S" % [
		total_income,
		collector_income,
		int(round(float(summary.get("player_income_per_second", 0.0)))),
	])
	lines.append("LOSSES  YOU %d    ENEMY %d    FORCE %d / %d" % [
		int(summary.get("player_units_lost", 0)),
		int(summary.get("enemy_units_lost", 0)),
		int(summary.get("player_current_force", 0)),
		int(summary.get("player_max_force", 0)),
	])
	lines.append("OUTPUT  YOU %d    ENEMY %d    DAMAGE %d" % [
		int(summary.get("player_units_produced", 0)),
		int(summary.get("enemy_units_produced", 0)),
		int(round(float(summary.get("player_damage_dealt", 0.0)))),
	])
	if str(summary.get("scenario_objective_type", "")) == "defend_network":
		lines.append("NETWORK %s / %s    SEVER %s / %s" % [
			_format_duration(float(summary.get("scenario_progress_seconds", 0.0))),
			_format_duration(float(summary.get("scenario_target_seconds", 0.0))),
			_format_duration(float(summary.get("scenario_disruption_seconds", 0.0))),
			_format_duration(float(summary.get("scenario_sever_seconds", 0.0))),
		])
	elif float(summary.get("scenario_hold_seconds", 0.0)) > 0.0:
		lines.append("NETWORK HOLD %s / %s" % [
			_format_duration(float(summary.get("scenario_progress_seconds", 0.0))),
			_format_duration(float(summary.get("scenario_hold_seconds", 0.0))),
		])
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
	var queue_count: int = min(queue.size(), queue_buttons.size())
	var viewport_width: float = get_viewport().get_visible_rect().size.x
	var queue_width: float = clamp(28.0 + float(queue_count) * 123.0, 360.0, max(360.0, viewport_width - 60.0))
	queue_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	queue_panel.offset_left = -queue_width * 0.5
	queue_panel.offset_right = queue_width * 0.5
	queue_panel.offset_top = -236.0
	queue_panel.offset_bottom = -122.0
	queue_title_label.text = "QUEUE  //  %s  //  CANCEL + REFUND" % str(building["display_name"]).to_upper()
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
		button.visible = true
		button.disabled = simulation.match_over
		button.modulate = Color(1.0, 0.95, 0.82, 1.0) if index == 0 else Color(0.88, 0.96, 0.98, 1.0)
		queue_card_icons[index].set_icon(unit_type, Color("#ffd36a") if index == 0 else Color("#8cebf3"))
		_set_card_label(queue_card_titles[index], display_name, 10, 7, 12)
		if index == 0:
			_set_card_label(queue_card_progress[index], "ACTIVE  %d%% · %ds" % [progress, remaining], 9, 7, 16)
		else:
			_set_card_label(queue_card_progress[index], "QUEUE %d  ·  %d%% · %ds" % [index, progress, remaining], 9, 7, 16)
		_set_card_label(queue_card_refunds[index], "REFUND %d C" % refund, 10, 7, 12)
		queue_card_titles[index].tooltip_text = display_name
		queue_card_progress[index].tooltip_text = "%d%% complete — %d seconds remaining" % [progress, remaining]
		queue_card_refunds[index].tooltip_text = "Cancel and refund %d credits." % refund
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
	var role_hint := "GENERAL"
	if simulation.unit_definitions.has(unit_type):
		var definition = simulation.unit_definitions[unit_type]
		display_name = str(definition.display_name).to_upper()
		force_slots = max(1, int(definition.force_slots))
		var tags: PackedStringArray = definition.role_tags
		if not tags.is_empty():
			role_hint = str(tags[0])
			if tags.size() > 1:
				role_hint += " · " + str(tags[1])
	return "%s %s [%dF]\n%s · %s" % [_unit_card_icon(unit_type), display_name, force_slots, role_hint, value_text]


func _unit_card_icon(unit_type: String) -> String:
	match unit_type:
		"ranger":
			return "RIFLE"
		"warden":
			return "ARMOR"
		"bulwark":
			return "MISSILE"
		"raider":
			return "FAST"
		"collector":
			return "CARGO"
		"command_carrier":
			return "CONVOY"
		_:
			return "UNIT"


func _upgrade_context_state(building: Dictionary) -> Dictionary:
	var definition = simulation.building_definitions.get(str(building.get("kind", "")))
	if definition == null or str(definition.upgrade_id).is_empty():
		return {"visible": false}
	if bool(building.get("upgrade_complete", false)) or not str(building.get("completed_upgrade_id", "")).is_empty():
		return {"visible": false}
	if not simulation.is_upgrade_available(str(definition.upgrade_id)):
		return {"visible": true, "disabled": true, "reason": "Building upgrades unlock in later levels."}
	var active_id := str(building.get("upgrade_id", ""))
	if not active_id.is_empty():
		var total: float = max(0.1, float(building.get("upgrade_total", definition.upgrade_time)))
		var remaining: float = float(building.get("upgrade_remaining", total))
		var progress: int = int(clamp(1.0 - remaining / total, 0.0, 1.0) * 100.0)
		return {"visible": true, "disabled": true, "reason": "Upgrade in progress (%d%%)." % progress, "label_suffix": "%d%%" % progress}
	var disabled := false
	var reason := ""
	if str(definition.upgrade_id) == "refining_efficiency":
		reason = "Refining Efficiency: Collector recovery and deposit transfer are 30% faster."
	elif str(definition.upgrade_id) == "fabrication_systems":
		reason = "Fabrication Systems: Assembly Bay production is 20% faster."
	if simulation.player_credits < float(definition.upgrade_cost):
		disabled = true
		reason += " Need %d more credits." % int(float(definition.upgrade_cost) - simulation.player_credits)
	return {"visible": true, "disabled": disabled, "reason": reason}


func _research_context_state(building: Dictionary, requested_technology_id: String = "") -> Dictionary:
	var definition = simulation.building_definitions.get(str(building.get("kind", "")))
	if definition == null:
		return {"visible": false}
	var research_options: Array = []
	for option in str(definition.can_research).split(","):
		var option_id := str(option).strip_edges()
		if not option_id.is_empty():
			research_options.append(option_id)
	var technology_id := requested_technology_id
	if technology_id.is_empty():
		for option_id in research_options:
			if simulation.technology_definitions.has(option_id) and not simulation.is_technology_unlocked("player", option_id):
				technology_id = option_id
				break
	if technology_id.is_empty() or not technology_id in research_options or not simulation.technology_definitions.has(technology_id):
		return {"visible": false}
	if simulation.is_technology_unlocked("player", technology_id):
		return {"visible": false}
	if not simulation.is_technology_allowed(technology_id):
		return {"visible": true, "disabled": true, "reason": "Research unlocks in a later campaign mission."}
	var active_id := str(building.get("research_id", ""))
	if not active_id.is_empty():
		if active_id != technology_id:
			var active_name := active_id.replace("_", " ").capitalize()
			if simulation.technology_definitions.has(active_id):
				active_name = str(simulation.technology_definitions[active_id].display_name)
			return {"visible": true, "disabled": true, "reason": "%s is researching %s." % [str(building.get("display_name", "Tech Centre")), active_name]}
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


func _repair_context_state() -> Dictionary:
	if selected_ids.size() != 1 or not simulation.buildings.has(selected_ids[0]):
		return {"visible": false}
	var building_id := str(selected_ids[0])
	var status: Dictionary = simulation.get_building_repair_status("player", building_id)
	if not bool(status.get("available", false)):
		return {"visible": false}
	var nearby_unit_ids: Array = status.get("nearby_unit_ids", [])
	var active_unit_ids: Array = status.get("active_unit_ids", [])
	var building_damaged: bool = bool(status.get("building_damaged", false))
	var building_active: bool = bool(status.get("building_repair_active", false))
	if not building_damaged and nearby_unit_ids.is_empty():
		return {"visible": false}
	if building_active or not active_unit_ids.is_empty():
		return {"action": "repair", "label": "REPAIRING\nACTIVE", "visible": true, "disabled": true, "reason": "This building is already repairing its own structure and/or nearby damaged units."}
	var required_cost := 45.0 if building_damaged else float(status.get("unit_cost", 30.0))
	if simulation.player_credits < required_cost:
		return {"action": "repair", "label": "REPAIR\n%d" % int(required_cost), "visible": true, "disabled": true, "reason": "Need %d credits for the next repair pulse." % int(required_cost - simulation.player_credits)}
	var target_label := "BUILDING + UNITS" if building_damaged and not nearby_unit_ids.is_empty() else "BUILDING" if building_damaged else "NEARBY UNITS"
	return {"action": "repair", "label": "REPAIR %s\n%d" % [target_label, int(required_cost)], "visible": true, "disabled": false, "reason": "Click once. The selected building repairs itself and all damaged units inside its green circle."}


func _context_card_title(action: String, label: String) -> String:
	if action.begins_with("produce:"):
		var unit_type := action.trim_prefix("produce:")
		return unit_type.replace("_", " ").to_upper()
	if action.begins_with("build:"):
		var building_type := action.trim_prefix("build:")
		if simulation.building_definitions.has(building_type):
			return str(simulation.building_definitions[building_type].display_name).to_upper()
		return building_type.replace("_", " ").to_upper()
	if action.begins_with("research:"):
		var technology_id := action.trim_prefix("research:")
		if simulation.technology_definitions.has(technology_id):
			return str(simulation.technology_definitions[technology_id].display_name).to_upper()
		return technology_id.replace("_", " ").to_upper()
	match action:
		"upgrade":
			var upgrade_line := str(label).split("\n")[0].replace("▲", "").strip_edges()
			return upgrade_line
		"research":
			return "TARGETING"
		"deploy":
			return "DEPLOY BASE"
		"repair":
			return "REPAIR"
		"collector_route":
			return "ROUTE"
		"unit_guard":
			return "GUARD"
		"unit_attack_move":
			return "ATTACK-MOVE"
		"unit_stop":
			return "STOP"
		_:
			var first_line := str(label).split("\n")[0].strip_edges()
			if first_line == "MULTI-UNIT":
				return "ORDERS"
			if first_line == "SELECT":
				return "SELECT"
			return first_line.replace("◈", "").strip_edges()


func _context_card_price(action: String, label: String) -> String:
	if action == "repair":
		if selected_ids.size() == 1 and simulation.buildings.has(selected_ids[0]):
			var repair_status: Dictionary = simulation.get_building_repair_status("player", str(selected_ids[0]))
			if bool(repair_status.get("building_damaged", false)):
				return "45 C/PULSE"
			return "%d C/PULSE" % int(repair_status.get("unit_cost", 30.0))
		return "30 C/PULSE"
	if action == "collector_route":
		return "FREE"
	if action == "deploy":
		return "FREE"
	if action == "unit_guard":
		return "[G]"
	if action == "unit_attack_move":
		return "[T]"
	if action == "unit_stop":
		return "[X]"
	var lines := str(label).split("\n")
	if lines.size() < 2:
		return "—"
	var value := str(lines[lines.size() - 1]).strip_edges()
	if value.contains("·"):
		var parts := value.split("·")
		value = str(parts[parts.size() - 1]).strip_edges()
	if value.is_valid_int():
		return "%s C" % value
	return value


func _context_card_icon(action: String, label: String) -> String:
	if action.begins_with("produce:"):
		return action.trim_prefix("produce:")
	if action.begins_with("build:"):
		return action.trim_prefix("build:")
	if action.begins_with("research:"):
		return "targeting"
	match action:
		"upgrade":
			return "fabrication" if str(label).find("FABRICATION") >= 0 else "refining"
		"research":
			return "targeting"
		"repair":
			return "repair"
		"collector_route":
			return "route"
		"deploy":
			return "forward_base"
		"unit_guard":
			return "guard"
		"unit_attack_move":
			return "attack_move"
		"unit_stop":
			return "stop"
		_:
			return "mixed" if str(label).find("MULTI") >= 0 else "unit"


func _context_card_accent(icon_key: String) -> Color:
	match icon_key:
		"guard":
			return Color("#7cf1ad")
		"attack_move":
			return Color("#ffd36a")
		"stop":
			return Color("#ff7b7b")
		"bulwark", "warden", "fabrication", "bastion_turret", "fire_support_battery":
			return Color("#ff9f43")
		"repair", "collector", "refinery", "refining", "field_repair_station":
			return Color("#7cf1ad")
		"targeting", "tech_centre", "relay", "forward_relay", "route", "forward_base", "sensor_mast":
			return Color("#8cebf3")
		"ranger", "raider", "assembly_bay":
			return Color("#d6fbff")
		_:
			return Color("#8cebf3")


func _update_context_cards() -> void:
	var buttons: Array = [build_button, queue_button, heavy_queue_button, research_button, repair_button, collector_button, repair_overflow_button]
	context_actions = ["", "", "", "", "", "", ""]
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
					var relay_state := _building_context_state("relay")
					if bool(relay_state.get("visible", false)):
						cards[3] = {"action": "build:relay", "label": "◈ FORWARD RELAY\n%d" % int(simulation.building_definitions["relay"].cost), "visible": true, "disabled": relay_state.get("disabled", false), "reason": relay_state.get("reason", "")}
					var sensor_state := _building_context_state("sensor_mast", "command_hub")
					if bool(sensor_state.get("visible", false)):
						cards[4] = {"action": "build:sensor_mast", "label": "◈ SENSOR MAST\n%d" % int(simulation.building_definitions["sensor_mast"].cost), "visible": true, "disabled": sensor_state.get("disabled", false), "reason": sensor_state.get("reason", "")}
					var bastion_state := _building_context_state("bastion_turret", "command_hub")
					if bool(bastion_state.get("visible", false)):
						cards[5] = {"action": "build:bastion_turret", "label": "◈ BASTION TURRET\n%d" % int(simulation.building_definitions["bastion_turret"].cost), "visible": true, "disabled": bastion_state.get("disabled", false), "reason": bastion_state.get("reason", "")}
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
					var research_ids: Array = ["advanced_targeting", "hardened_chassis", "field_optics", "breach_package"]
					for research_index in research_ids.size():
						var research_id: String = str(research_ids[research_index])
						var research_state: Dictionary = _research_context_state(building, research_id)
						if not bool(research_state.get("visible", false)):
							continue
						var research_suffix := str(research_state.get("label_suffix", ""))
						var research_label := "▲ %s\n%d" % [str(simulation.technology_definitions[research_id].display_name).to_upper(), int(simulation.technology_definitions[research_id].cost)]
						if not research_suffix.is_empty():
							research_label = "▲ %s\n%s" % [str(simulation.technology_definitions[research_id].display_name).to_upper(), research_suffix]
						cards[research_index] = {"action": "research:%s" % research_id, "label": research_label, "visible": true, "disabled": research_state.get("disabled", false), "reason": research_state.get("reason", "")}
					var battery_state := _building_context_state("fire_support_battery", "tech_centre")
					if bool(battery_state.get("visible", false)):
						cards[5] = {"action": "build:fire_support_battery", "label": "◈ FIRE SUPPORT\n%d" % int(simulation.building_definitions["fire_support_battery"].cost), "visible": true, "disabled": battery_state.get("disabled", false), "reason": battery_state.get("reason", "")}
				"forward_base":
					var forward_build_options: Array = ["sensor_mast", "field_repair_station", "bastion_turret"]
					for forward_index in forward_build_options.size():
						var forward_kind: String = str(forward_build_options[forward_index])
						var forward_state: Dictionary = _building_context_state(forward_kind, "")
						if not bool(forward_state.get("visible", false)):
							continue
						var forward_definition = simulation.building_definitions[forward_kind]
						cards[forward_index] = {"action": "build:%s" % forward_kind, "label": "◈ %s\n%d" % [str(forward_definition.display_name).to_upper(), int(forward_definition.cost)], "visible": true, "disabled": forward_state.get("disabled", false), "reason": forward_state.get("reason", "")}
			var repair_state := _repair_context_state()
			if bool(repair_state.get("visible", false)):
				# Keep the building's ordinary production/research cards stable. A
				# seventh slot is used only when the normal repair slot is occupied.
				var repair_slot := 4 if not bool(cards[4].get("visible", false)) else 6
				cards[repair_slot] = repair_state
		elif simulation.units.has(entity_id):
			var selected_unit: Dictionary = simulation.units[entity_id]
			if str(selected_unit.get("kind", "")) == "collector":
				cards[0] = {"action": "collector_route", "label": "ROUTE [U]", "visible": true, "disabled": false, "reason": "Assign this Collector to an Energy Field and Processor."}
			elif str(selected_unit.get("kind", "")) == "command_carrier":
				var campaign: Dictionary = simulation.get_campaign_state()
				if bool(campaign.get("active", false)) and str(campaign.get("objective_type", "")) == "deploy":
					var deployment_ready: bool = bool(campaign.get("deployment_ready", false))
					cards[0] = {"action": "deploy", "label": "◈ DEPLOY BASE\nREADY" if deployment_ready else "◈ DEPLOY BASE\nMOVE TO PAD", "visible": true, "disabled": not deployment_ready, "reason": "Deploy the Forward Base at the marked eastern site." if deployment_ready else "Move the Mobile Command Unit inside the marked deployment zone."}
	elif not selected_ids.is_empty():
		var combat_ids := _selected_combat_unit_ids()
		if selected_ids.size() > 1 and not combat_ids.is_empty():
			var group_reason := "Commands apply to %d armed selected unit%s." % [combat_ids.size(), "" if combat_ids.size() == 1 else "s"]
			cards[0] = {"action": "unit_guard", "label": "GUARD\n[G]", "visible": true, "disabled": false, "reason": "%s Hold position and engage enemies inside the guard radius." % group_reason}
			cards[1] = {"action": "unit_attack_move", "label": "ATTACK-MOVE\n[T]", "visible": true, "disabled": false, "reason": "%s Right-click a destination to move and engage along the route." % group_reason}
			cards[2] = {"action": "unit_stop", "label": "STOP\n[X]", "visible": true, "disabled": false, "reason": "%s Cancel movement, attack-move, patrol, and pursuit orders." % group_reason}
		else:
			cards[0] = {"action": "", "label": "MULTI-UNIT\nORDERS", "visible": true, "disabled": true, "reason": "Select at least two armed units to show group commands."}
	else:
		cards[0] = {"action": "", "label": "SELECT\nSTRUCTURE", "visible": true, "disabled": true, "reason": "Select a Command Hub, Processor, Assembly Bay, or Tech Centre."}
	for index in range(buttons.size()):
		var button: Button = buttons[index]
		var card: Dictionary = cards[index]
		var action := str(card.get("action", ""))
		context_actions[index] = action
		button.visible = bool(card.get("visible", false))
		button.disabled = bool(card.get("disabled", true)) or simulation.match_over
		var reason := str(card.get("reason", ""))
		var label := str(card.get("label", ""))
		if index < action_card_icons.size():
			var icon_key := _context_card_icon(action, label)
			action_card_icons[index].set_icon(icon_key, _context_card_accent(icon_key))
			_set_card_label(action_card_titles[index], _context_card_title(action, label), 10, 7, 12)
			_set_card_label(action_card_prices[index], _context_card_price(action, label), 11, 8, 10)
		button.tooltip_text = reason if not reason.is_empty() else label.replace("\n", " ")

func _selection_detail(data: Dictionary) -> String:
	var supply_text := ""
	if data.has("supply_state"):
		supply_text = "   SUPPLY %s" % str(data["supply_state"]).to_upper()
		if str(data.get("supply_reason", "")).is_empty() == false:
			supply_text += " — %s" % str(data.get("supply_reason", ""))
	var force_text := ""
	var role_text := ""
	if data.has("kind") and simulation.unit_definitions.has(str(data["kind"])):
		var selected_definition = simulation.unit_definitions[str(data["kind"])]
		force_text = "   FORCE %d" % max(1, int(selected_definition.force_slots))
		var role_hint := str(selected_definition.role_summary).to_upper()
		var tags: PackedStringArray = selected_definition.role_tags
		if not tags.is_empty():
			role_hint = str(tags[0])
			if tags.size() > 1:
				role_hint += " · " + str(tags[1])
			var effective_range: float = simulation.get_effective_attack_range(str(data.get("team", "player")), str(data["kind"]))
			var targeting_text := "  TARGETING +18%%" if simulation.is_technology_unlocked(str(data.get("team", "player")), "advanced_targeting") else ""
			role_text = "\nROLE %s  DMG %d  RANGE %.1f  ARM %d%s" % [role_hint, int(selected_definition.attack_damage), effective_range, int(selected_definition.armour), targeting_text]
			var guidance := _selection_guidance(data)
			if not guidance.is_empty():
				role_text += "\nGUIDANCE  " + guidance
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
		elif data["collector_state"] == "loading":
			collector_route_label = "RECOVERING ENERGY"
		elif data["collector_state"] == "unloading":
			collector_route_label = "DEPOSITING ENERGY"
		elif data["collector_state"] == "awaiting_source":
			collector_route_label = "WAITING — NO FIELD WITHIN 6 BLOCKS"
		elif data["collector_state"] == "unassigned":
			collector_route_label = "UNASSIGNED — PRESS U"
		elif data["collector_state"] == "depleted":
			collector_route_label = "SOURCE DEPLETED — PRESS U"
		elif data["collector_state"] == "storage_full":
			collector_route_label = "STORAGE FULL — BUILD SILO OR SPEND"
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
	var storage_text := ""
	var local_storage_capacity: float = maxf(0.0, float(data.get("storage_capacity", 0.0)))
	if local_storage_capacity > simulation.RESOURCE_EPSILON:
		var network_storage: Dictionary = simulation.get_storage_summary(str(data.get("team", "player")))
		storage_text = "   STORAGE %d/%d" % [int(network_storage.get("credits", 0.0)), int(network_storage.get("capacity", local_storage_capacity))]
	var repair_text := ""
	if bool(data.get("repair_active", false)):
		repair_text = "   REPAIRING — AUTOMATIC"
	elif data.has("order") and float(data.get("health", 0.0)) < float(data.get("max_health", 0.0)):
		if simulation.get_repair_station_id("player", data["position"]).is_empty():
			repair_text = "   REPAIR: MOVE INTO GREEN BUILDING CIRCLE"
		else:
			repair_text = "   REPAIR READY — SELECT THE BUILDING"
	elif not data.has("order") and float(data.get("health", 0.0)) < float(data.get("max_health", 0.0)):
		repair_text = "   REPAIR READY — SELECT THE BUILDING (45 C/PULSE)"
	elif float(data.get("repair_radius", 0.0)) > 0.0:
		repair_text = "   GREEN REPAIR CIRCLE %.1f BLOCKS" % float(data["repair_radius"])
	if data.has("order"):
		return "HP %d/%d   ORDER %s%s%s%s%s%s%s%s%s%s" % [int(data["health"]), int(data["max_health"]), str(data["order"]).to_upper(), force_text, supply_text, collector_text, research_text, queue_text, rally_text, role_text, storage_text, repair_text]
	return "HP %d/%d   %s%s%s%s%s%s%s%s%s%s" % [int(data["health"]), int(data["max_health"]), "ONLINE" if data["complete"] else "BUILDING", force_text, supply_text, collector_text, research_text, queue_text, rally_text, role_text, storage_text, repair_text]


func _selection_icon_key(data: Dictionary, enemy := false) -> String:
	if enemy:
		return "enemy"
	var kind := str(data.get("kind", "unit"))
	if data.has("order"):
		return kind if ["ranger", "warden", "bulwark", "raider", "collector", "command_carrier"].has(kind) else "unit"
	return kind if ["command_hub", "assembly_bay", "refinery", "tech_centre", "storage_silo", "relay", "forward_relay", "forward_base", "sensor_mast", "field_repair_station", "bastion_turret", "fire_support_battery"].has(kind) else "unit"


func _selection_card_text(data: Dictionary) -> String:
	var display_name := _selection_title()
	var health := int(data.get("health", 0.0))
	var maximum := int(data.get("max_health", 0.0))
	var state := "ONLINE" if bool(data.get("complete", true)) else "BUILDING"
	if data.has("order"):
		state = "ORDER " + str(data.get("order", "awaiting")).to_upper()
		if not str(data.get("collector_state", "")).is_empty():
			state = str(data.get("collector_state", "")).replace("_", " ").to_upper()
	var guidance := _selection_guidance(data)
	if not guidance.is_empty():
		state = guidance
	if selected_ids.size() > 1:
		return "%s\nHP %d/%d\n%s" % [display_name, health, maximum, _selection_composition()]
	return "%s\nHP %d/%d\n%s" % [display_name, health, maximum, state]


func _selection_guidance(data: Dictionary) -> String:
	if not play_hints_enabled:
		return ""
	if bool(data.get("under_fire", false)):
		return "UNDER FIRE — RETREAT / REPAIR"
	var health_ratio: float = float(data.get("health", 0.0)) / max(1.0, float(data.get("max_health", 1.0)))
	if health_ratio < 0.72 and data.has("order"):
		if simulation.get_repair_station_id("player", data.get("position", Vector3.ZERO)).is_empty():
			return "DAMAGED — MOVE TO GREEN REPAIR CIRCLE"
		return "DAMAGED — SELECT THE REPAIR BUILDING"
	if str(data.get("kind", "")) == "bulwark":
		return "SIEGE — HOLD RANGE / FLANK LAUNCHERS"
	return ""


func _selection_title() -> String:
	if selected_ids.is_empty():
		return "NO SELECTION"
	var kinds: Dictionary = {}
	for entity_id in selected_ids:
		if simulation.units.has(entity_id):
			var kind := str(simulation.units[entity_id].get("kind", "unit"))
			kinds[kind] = int(kinds.get(kind, 0)) + 1
		elif simulation.buildings.has(entity_id):
			var building_kind := str(simulation.buildings[entity_id].get("kind", "structure"))
			kinds[building_kind] = int(kinds.get(building_kind, 0)) + 1
	if kinds.size() == 1:
		var only_kind := str(kinds.keys()[0])
		var definition = simulation.unit_definitions.get(only_kind)
		var display_name := str(definition.display_name) if definition else only_kind.replace("_", " ").capitalize()
		return "%s  x%d" % [display_name.to_upper(), selected_ids.size()]
	return "MIXED FORCE  x%d" % selected_ids.size()


func _selection_composition() -> String:
	var counts: Dictionary = {}
	for entity_id in selected_ids:
		if not simulation.units.has(entity_id):
			continue
		var kind := str(simulation.units[entity_id].get("kind", "unit"))
		var definition = simulation.unit_definitions.get(kind)
		var display_name := str(definition.display_name).to_upper() if definition else kind.to_upper()
		counts[display_name] = int(counts.get(display_name, 0)) + 1
	var parts: PackedStringArray = []
	for display_name in counts:
		parts.append("%s %d" % [display_name, int(counts[display_name])])
	return " · ".join(parts)


func _clear_combat_feedback() -> void:
	damage_feedback_last_tick.clear()


func _append_event_log(message: String, tick := -1) -> void:
	if not game_log_enabled or message.is_empty() or not event_log_label:
		return
	var lines: PackedStringArray = event_log_label.text.split("\n")
	var event_tick := int(simulation.current_tick) if tick < 0 and simulation else tick
	lines.append("[%03d] %s" % [event_tick, message])
	while lines.size() > 5:
		lines.remove_at(0)
	event_log_label.text = "EVENT LOG\n" + "\n".join(lines.slice(1))


func _feedback_entity_name(payload: Dictionary, prefix: String, fallback: String) -> String:
	var display_name := str(payload.get("%s_display_name" % prefix, ""))
	if not display_name.is_empty():
		return display_name
	var kind := str(payload.get("%s_kind" % prefix, ""))
	if not kind.is_empty():
		if simulation and simulation.unit_definitions.has(kind):
			return str(simulation.unit_definitions[kind].display_name)
		if simulation and simulation.building_definitions.has(kind):
			return str(simulation.building_definitions[kind].display_name)
	return fallback


func _combat_feedback_message(event_type: String, payload: Dictionary) -> String:
	if event_type != "UnitDamaged" and event_type != "BuildingDamaged":
		return ""
	if str(payload.get("team", "")) != "player" or str(payload.get("attacker_team", "")) != "enemy":
		return ""
	var target_id := str(payload.get("target_id", payload.get("building_id", "")))
	var last_tick := int(damage_feedback_last_tick.get(target_id, -1000))
	var event_tick := int(payload.get("tick", simulation.current_tick if simulation else 0))
	if event_tick - last_tick < 12:
		return ""
	damage_feedback_last_tick[target_id] = event_tick
	var attacker_name := _feedback_entity_name(payload, "attacker", "Enemy weapon")
	var target_name := _feedback_entity_name(payload, "target", "Friendly unit")
	var splash_text := " — SPLASH" if bool(payload.get("is_splash", false)) else ""
	var health_ratio: float = float(payload.get("health", 0.0)) / max(1.0, float(payload.get("max_health", 1.0)))
	var response := "RETREAT / REPAIR" if health_ratio <= 0.45 else "SPREAD OUT / BREAK CONTACT"
	var prefix := "BASE UNDER FIRE" if event_type == "BuildingDamaged" else "UNDER FIRE"
	return "%s — %s hit %s for %d HP%s. %s." % [prefix, attacker_name, target_name, int(round(float(payload.get("damage", 0.0)))), splash_text, response]


func _on_simulation_event(event_type: String, payload: Dictionary) -> void:
	if audio_manager:
		audio_manager.handle_simulation_event(simulation, event_type, payload)
	if combat_effects:
		combat_effects.present(self, simulation, event_type, payload)
	if not status_label or not event_log_label:
		return
	var feedback_message: String = str(payload.get("message", payload.get("reason", "")))
	if event_type == "LauncherThreatWarning":
		feedback_message = str(payload.get("message", "ENEMY LAUNCHER FIRE — spread out, flank, or break its range."))
		if play_hints_enabled:
			status_label.text = "THREAT WARNING — %s" % feedback_message
			status_label.modulate = Color("#ff7b86")
		_append_event_log(feedback_message, int(payload.get("tick", simulation.current_tick)))
		return
	if event_type == "AIIntentDeclared" or event_type == "AIPhaseChanged" or event_type == "AIPostureChanged":
		if play_hints_enabled and not feedback_message.is_empty():
			status_label.text = "OPPONENT INTEL — %s" % feedback_message
		return
	if not _is_player_event(event_type, payload):
		return
	var combat_message := _combat_feedback_message(event_type, payload)
	if not combat_message.is_empty():
		feedback_message = combat_message
		if play_hints_enabled:
			status_label.text = feedback_message
			status_label.modulate = Color("#ff7b86")
	elif event_type == "UnitDestroyed" and str(payload.get("team", "")) == "player":
		if play_hints_enabled:
			feedback_message = "UNIT LOST — %s Reinforce from an Assembly Bay; pull damaged survivors back to repair." % feedback_message
			status_label.text = feedback_message
			status_label.modulate = Color("#ffbf6a")
	elif event_type == "BuildingDestroyed" and str(payload.get("team", "")) == "player":
		if play_hints_enabled:
			feedback_message = "STRUCTURE LOST — %s Rebuild the supply or production link before committing another push." % feedback_message
			status_label.text = feedback_message
			status_label.modulate = Color("#ff7b86")
	if not feedback_message.is_empty():
		if play_hints_enabled:
			status_label.text = feedback_message
	if event_type == "MatchWon" or event_type == "MatchLost":
		if play_hints_enabled:
			status_label.text = "[ %s ] %s" % ["VICTORY" if event_type == "MatchWon" else "DEFEAT", payload.get("message", "Match complete")]
			status_label.modulate = Color("#ffd36a") if event_type == "MatchWon" else Color("#ff7b86")
		_show_match_result(event_type, payload)
	if event_type == "MatchWon" and campaign_progress and simulation.get_match_mode() == "campaign":
		var completed_level_id: String = simulation.get_level_id()
		var unlocked_id: String = campaign_progress.mark_complete(completed_level_id, payload)
		var reward_text: String = campaign_progress.get_mission_reward_text(completed_level_id)
		var receipt_lines: PackedStringArray = []
		if not reward_text.is_empty():
			receipt_lines.append("CAMPAIGN RECEIPT")
			receipt_lines.append(reward_text)
		if not unlocked_id.is_empty():
			receipt_lines.append("NEXT OPERATION  %s" % str(campaign_progress.get_mission(unlocked_id).get("display_name", unlocked_id)))
			if play_hints_enabled:
				status_label.text = "LEVEL COMPLETE — %s unlocked. Press F2 to deploy." % campaign_progress.get_mission(unlocked_id).get("display_name", unlocked_id)
		if result_receipt_label and not receipt_lines.is_empty():
			result_receipt_label.text = "\n".join(receipt_lines)
			result_receipt_label.visible = true
	_append_event_log(feedback_message, int(payload.get("tick", simulation.current_tick)))


func _is_player_event(event_type: String, payload: Dictionary) -> bool:
	if event_type == "MatchWon" or event_type == "MatchLost":
		return true
	if payload.has("attacker_team"):
		return str(payload.get("team", "")) == "player" or str(payload.get("attacker_team", "")) == "player"
	if payload.has("target_team"):
		return str(payload.get("target_team", "")) == "player"
	if payload.has("team"):
		return str(payload.get("team", "")) == "player"
	return event_type == "MatchStarted" or event_type == "MatchWon" or event_type == "MatchLost"


func _update_selection_marquee() -> void:
	var rectangle := Rect2(drag_start, drag_current - drag_start).abs()
	selection_marquee.position = rectangle.position
	selection_marquee.size = rectangle.size


func _pointer_over_ui() -> bool:
	if not pointer_inside_viewport or not get_viewport().get_visible_rect().has_point(pointer_position):
		return true
	if _is_dialog_open():
		return true
	var hovered_control := get_viewport().gui_get_hovered_control()
	if hovered_control and hovered_control.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		return true
	for control in [bottom_panel, queue_panel, minimap]:
		if control and control.visible and control.get_global_rect().has_point(pointer_position):
			return true
	return false


func _is_dialog_open() -> bool:
	if start_menu_visible or result_visible or objective_briefing_visible or pause_menu_visible:
		return true
	if start_menu_overlay and start_menu_overlay.visible:
		return true
	if objective_briefing_overlay and objective_briefing_overlay.visible:
		return true
	if pause_menu_overlay and pause_menu_overlay.visible:
		return true
	return result_overlay != null and result_overlay.visible


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


func _card_style(background: Color, border: Color) -> StyleBoxFlat:
	var style := _panel_style(background, border)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.content_margin_left = 4.0
	style.content_margin_right = 4.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	return style


func _create_status_chip(chip_name: String, label: Label, minimum_width: float, accent: Color, icon_key := "") -> PanelContainer:
	var chip := PanelContainer.new()
	chip.name = chip_name
	chip.custom_minimum_size = Vector2(minimum_width, 32.0)
	chip.add_theme_stylebox_override("panel", _card_style(Color(0.035, 0.105, 0.13, 0.92), Color(accent.r, accent.g, accent.b, 0.42)))
	var content := HBoxContainer.new()
	content.name = "StatusContent"
	content.add_theme_constant_override("separation", 6)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(content)
	if not str(icon_key).is_empty():
		var icon := HudIconScript.new()
		icon.name = "%sIcon" % chip_name
		icon.custom_minimum_size = Vector2(28.0, 24.0)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.set_icon(str(icon_key), accent)
		content.add_child(icon)
		top_status_icons[chip_name] = icon
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(label)
	return chip


func _create_queue_card(slot: int) -> Button:
	var button := Button.new()
	button.name = "ProductionQueueCard_%d" % slot
	button.custom_minimum_size = Vector2(116.0, 76.0)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.text = ""
	button.add_theme_stylebox_override("normal", _card_style(Color(0.035, 0.105, 0.13, 0.96), Color(0.96, 0.68, 0.28, 0.68)))
	button.add_theme_stylebox_override("hover", _card_style(Color(0.10, 0.20, 0.22, 0.99), Color(1.0, 0.78, 0.36, 1.0)))
	button.add_theme_stylebox_override("pressed", _card_style(Color(0.16, 0.28, 0.28, 1.0), Color(1.0, 0.92, 0.68, 1.0)))
	button.add_theme_stylebox_override("disabled", _card_style(Color(0.035, 0.065, 0.075, 0.92), Color(0.22, 0.31, 0.34, 0.72)))

	var content := VBoxContainer.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 5.0
	content.offset_right = -5.0
	content.offset_top = 3.0
	content.offset_bottom = -3.0
	content.add_theme_constant_override("separation", 0)
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(content)

	var icon := HudIconScript.new()
	icon.name = "QueueIcon"
	icon.custom_minimum_size = Vector2(46.0, 30.0)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(icon)
	var title := _label("", 10, Color("#d6fbff"))
	title.custom_minimum_size = Vector2(104.0, 16.0)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(title)
	var progress := _label("", 9, Color("#8cebf3"))
	progress.custom_minimum_size = Vector2(104.0, 14.0)
	progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	progress.clip_text = true
	progress.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(progress)
	var refund := _label("", 10, Color("#ffd36a"))
	refund.custom_minimum_size = Vector2(104.0, 14.0)
	refund.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	refund.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	refund.clip_text = true
	refund.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	refund.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(refund)
	queue_card_icons.append(icon)
	queue_card_titles.append(title)
	queue_card_progress.append(progress)
	queue_card_refunds.append(refund)
	return button


func _create_action_card(slot: int) -> Button:
	var button := Button.new()
	button.name = "ContextActionCard_%d" % slot
	button.custom_minimum_size = Vector2(92.0, 76.0)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.text = ""
	button.add_theme_stylebox_override("normal", _card_style(Color(0.035, 0.105, 0.13, 0.96), Color(0.16, 0.53, 0.60, 0.82)))
	button.add_theme_stylebox_override("hover", _card_style(Color(0.08, 0.22, 0.25, 0.98), Color(0.45, 0.93, 0.95, 1.0)))
	button.add_theme_stylebox_override("pressed", _card_style(Color(0.12, 0.28, 0.30, 1.0), Color(0.84, 0.98, 0.98, 1.0)))
	button.add_theme_stylebox_override("disabled", _card_style(Color(0.035, 0.065, 0.075, 0.92), Color(0.22, 0.31, 0.34, 0.72)))
	button.pressed.connect(_run_context_action.bind(slot))

	var content := VBoxContainer.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 5.0
	content.offset_right = -5.0
	content.offset_top = 4.0
	content.offset_bottom = -3.0
	content.add_theme_constant_override("separation", 0)
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(content)

	var icon := HudIconScript.new()
	icon.custom_minimum_size = Vector2(42.0, 34.0)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(icon)
	var title := _label("", 10, Color("#d6fbff"))
	title.custom_minimum_size = Vector2(80.0, 16.0)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(title)
	var price := _label("", 11, Color("#ffd36a"))
	price.custom_minimum_size = Vector2(80.0, 16.0)
	price.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price.clip_text = true
	price.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	price.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(price)
	action_card_icons.append(icon)
	action_card_titles.append(title)
	action_card_prices.append(price)
	return button


func _label(text_value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_override("font", ThemeDB.fallback_font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.72))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


func _compact_card_font_size(value: String, base_size: int, minimum_size: int = 7, comfortable_chars: int = 12) -> int:
	var compact_value: String = value.replace(" ", "").replace("-", "")
	var character_count: int = maxi(1, compact_value.length())
	var scaled_size: int = int(floor(float(base_size) * float(comfortable_chars) / float(character_count)))
	return clampi(scaled_size, minimum_size, base_size)


func _set_card_label(label: Label, value: String, base_size: int, minimum_size: int = 7, comfortable_chars: int = 12) -> void:
	label.text = value
	label.add_theme_font_size_override("font_size", _compact_card_font_size(value, base_size, minimum_size, comfortable_chars))
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.tooltip_text = value
