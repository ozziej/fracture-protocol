class_name RtsUnitView
extends Node3D

var entity_id := ""
var team := "neutral"
var kind := ""

var body_mesh: MeshInstance3D
var selection_disc: MeshInstance3D
var order_line: MeshInstance3D
var order_target: MeshInstance3D
var health_back: MeshInstance3D
var health_front: MeshInstance3D
var cargo_back: MeshInstance3D
var cargo_front: MeshInstance3D
var name_label: Label3D
var visual_initialized := false


func setup(data: Dictionary) -> void:
	entity_id = data["id"]
	team = data["team"]
	kind = data["kind"]
	_build_visuals()
	sync(data, false)


func sync(data: Dictionary, selected: bool, frame_delta: float = 0.0) -> void:
	var desired_position: Vector3 = data["position"]
	if not visual_initialized or frame_delta <= 0.0 or global_position.distance_to(desired_position) > 8.0:
		global_position = desired_position
		visual_initialized = true
	else:
		var position_blend: float = 1.0 - exp(-frame_delta * 24.0)
		global_position = global_position.lerp(desired_position, position_blend)
	var movement_order: bool = data["order"] == "move" or data["order"] == "attack_move"
	if movement_order and data["target_position"].distance_to(desired_position) > 0.2:
		var previous_rotation := rotation
		look_at(Vector3(data["target_position"].x, global_position.y, data["target_position"].z), Vector3.UP)
		var desired_yaw := rotation.y
		rotation = previous_rotation
		if frame_delta <= 0.0:
			rotation.y = desired_yaw
		else:
			rotation.y = lerp_angle(previous_rotation.y, desired_yaw, 1.0 - exp(-frame_delta * 20.0))
	selection_disc.visible = selected
	var health_ratio: float = clamp(float(data["health"]) / max(1.0, float(data["max_health"])), 0.0, 1.0)
	_set_progress_bar(health_front, health_ratio, 1.35, 1.35)
	if cargo_front and cargo_back:
		var cargo_capacity: float = max(1.0, float(data.get("collector_capacity", 0.0)))
		var cargo_ratio: float = clamp(float(data.get("collector_cargo", 0.0)) / cargo_capacity, 0.0, 1.0)
		cargo_back.visible = kind == "collector"
		cargo_front.visible = kind == "collector"
		_set_progress_bar(cargo_front, cargo_ratio, 1.35, 1.35)
	var supply_state: String = str(data.get("supply_state", "connected"))
	var order: String = str(data.get("order", "idle"))
	var label_text: String = data["display_name"]
	if order != "idle":
		label_text += "\n" + order.replace("_", "-").to_upper()
	if supply_state == "unsupplied":
		label_text += "\n! UNSUPPLIED"
	var collector_state: String = str(data.get("collector_state", ""))
	if not collector_state.is_empty():
		var collector_route_label := collector_state.replace("_", "-").to_upper()
		if collector_state == "to_source":
			collector_route_label = "SOURCE " + str(data.get("collector_source_name", ""))
		elif collector_state == "to_destination":
			collector_route_label = "TO " + str(data.get("collector_destination_name", ""))
		elif collector_state == "retreating":
			collector_route_label = "RETREAT TO BASE"
		label_text += "\n" + collector_route_label
		if float(data.get("collector_capacity", 0.0)) > 0.0:
			label_text += " %d/%d" % [int(data.get("collector_cargo", 0.0)), int(data.get("collector_capacity", 0.0))]
	name_label.text = label_text
	name_label.modulate = Color("#ffbf6a") if supply_state == "unsupplied" else _team_palette(team).lightened(0.45)
	_update_order_marker(data, selected)

func _build_visuals() -> void:
	var palette := _team_palette(team)
	var definition_height := 1.0
	if kind == "warden" or kind == "bulwark":
		definition_height = 0.8
	var body := CylinderMesh.new()
	body.top_radius = 0.58 if kind == "ranger" else 0.78
	body.bottom_radius = body.top_radius * 1.08
	body.height = definition_height
	body.radial_segments = 12
	body_mesh = MeshInstance3D.new()
	body_mesh.mesh = body
	body_mesh.material_override = _material(palette)
	body_mesh.position.y = definition_height * 0.5
	add_child(body_mesh)

	if kind == "raider" or kind == "bulwark":
		var chassis := BoxMesh.new()
		chassis.size = Vector3(1.05, 0.24, 1.6 if kind == "bulwark" else 1.2)
		var chassis_mesh := MeshInstance3D.new()
		chassis_mesh.mesh = chassis
		chassis_mesh.material_override = _material(palette.lightened(0.12))
		chassis_mesh.position = Vector3(0.0, definition_height * 0.78, -0.15)
		add_child(chassis_mesh)
		if kind == "bulwark":
			for side in [-0.58, 0.58]:
				var track := BoxMesh.new()
				track.size = Vector3(0.32, 0.28, 1.65)
				var track_mesh := MeshInstance3D.new()
				track_mesh.mesh = track
				track_mesh.material_override = _material(Color("#314453"))
				track_mesh.position = Vector3(side, 0.24, 0.0)
				add_child(track_mesh)
			var pod := BoxMesh.new()
			pod.size = Vector3(0.82, 0.34, 0.68)
			var pod_mesh := MeshInstance3D.new()
			pod_mesh.mesh = pod
			pod_mesh.material_override = _material(Color("#ff9f43"))
			pod_mesh.position = Vector3(0.0, definition_height + 0.16, 0.12)
			add_child(pod_mesh)
	elif kind == "warden":
		var armour_plate := BoxMesh.new()
		armour_plate.size = Vector3(1.35, 0.26, 1.0)
		var armour_mesh := MeshInstance3D.new()
		armour_mesh.mesh = armour_plate
		armour_mesh.material_override = _material(palette.lightened(0.08))
		armour_mesh.position = Vector3(0.0, definition_height * 0.88, 0.0)
		add_child(armour_mesh)
		var cannon := BoxMesh.new()
		cannon.size = Vector3(0.2, 0.2, 1.25)
		var cannon_mesh := MeshInstance3D.new()
		cannon_mesh.mesh = cannon
		cannon_mesh.material_override = _material(Color("#d9fbff"))
		cannon_mesh.position = Vector3(0.0, definition_height * 1.05, -0.52)
		add_child(cannon_mesh)
	elif kind == "ranger":
		var rifle := BoxMesh.new()
		rifle.size = Vector3(0.16, 0.16, 1.15)
		var rifle_mesh := MeshInstance3D.new()
		rifle_mesh.mesh = rifle
		rifle_mesh.material_override = _material(Color("#d9fbff"))
		rifle_mesh.position = Vector3(0.22, definition_height * 0.8, -0.42)
		add_child(rifle_mesh)
	elif kind == "collector":
		var cargo_mesh := BoxMesh.new()
		cargo_mesh.size = Vector3(0.85, 0.38, 0.72)
		var cargo_instance := MeshInstance3D.new()
		cargo_instance.mesh = cargo_mesh
		cargo_instance.material_override = _material(Color("#d7a44a"))
		cargo_instance.position = Vector3(0.0, definition_height * 0.78, 0.0)
		add_child(cargo_instance)

	var disc := CylinderMesh.new()
	disc.top_radius = 0.9
	disc.bottom_radius = 0.9
	disc.height = 0.035
	disc.radial_segments = 24
	selection_disc = MeshInstance3D.new()
	selection_disc.mesh = disc
	selection_disc.material_override = _material(Color(0.38, 0.92, 1.0, 0.8))
	selection_disc.position.y = 0.03
	selection_disc.visible = false
	add_child(selection_disc)

	var order_beam := BoxMesh.new()
	order_beam.size = Vector3(0.09, 0.04, 1.0)
	order_line = MeshInstance3D.new()
	order_line.mesh = order_beam
	order_line.material_override = _material(Color(palette.r, palette.g, palette.b, 0.72))
	order_line.visible = false
	add_child(order_line)

	var target_disc := CylinderMesh.new()
	target_disc.top_radius = 0.28
	target_disc.bottom_radius = 0.28
	target_disc.height = 0.04
	target_disc.radial_segments = 16
	order_target = MeshInstance3D.new()
	order_target.mesh = target_disc
	order_target.material_override = _material(Color("#ffd36a"))
	order_target.visible = false
	add_child(order_target)

	health_back = _health_bar(Color(0.06, 0.08, 0.11, 1.0), Vector3(1.35, 0.08, 0.08))
	health_back.position = Vector3(0.0, definition_height + 0.4, 0.0)
	add_child(health_back)
	health_front = _health_bar(Color(0.28, 0.94, 0.55, 1.0), Vector3(1.35, 0.095, 0.095))
	health_front.position = Vector3(0.0, definition_height + 0.4, 0.03)
	add_child(health_front)

	if kind == "collector":
		cargo_back = _health_bar(Color(0.06, 0.08, 0.11, 1.0), Vector3(1.35, 0.07, 0.07))
		cargo_back.position = Vector3(0.0, definition_height + 0.22, 0.0)
		add_child(cargo_back)
		cargo_front = _health_bar(Color("#f3bd52"), Vector3(1.35, 0.085, 0.085))
		cargo_front.position = Vector3(0.0, definition_height + 0.22, 0.035)
		add_child(cargo_front)

	name_label = Label3D.new()
	name_label.position = Vector3(0.0, definition_height + 0.76, 0.0)
	name_label.font_size = 32
	name_label.modulate = palette.lightened(0.45)
	name_label.outline_size = 8
	name_label.outline_modulate = Color(0.01, 0.02, 0.04, 0.9)
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_label.no_depth_test = true
	add_child(name_label)


func _update_order_marker(data: Dictionary, selected: bool) -> void:
	var order: String = str(data.get("order", "idle"))
	var show_marker := selected and (order == "move" or order == "attack_move")
	if not show_marker:
		order_line.visible = false
		order_target.visible = false
		return
	var world_delta: Vector3 = data["target_position"] - global_position
	world_delta.y = 0.0
	var delta: Vector3 = world_delta.rotated(Vector3.UP, -rotation.y)
	var length := Vector2(delta.x, delta.z).length()
	if length < 0.3:
		order_line.visible = false
		order_target.visible = false
		return
	order_line.visible = true
	order_target.visible = true
	order_line.position = delta * 0.5 + Vector3(0.0, 0.14, 0.0)
	order_line.rotation.y = atan2(delta.x, delta.z)
	order_line.scale = Vector3(1.0, 1.0, length)
	order_target.position = delta + Vector3(0.0, 0.14, 0.0)


func _set_progress_bar(instance: MeshInstance3D, ratio: float, background_width: float, foreground_width: float) -> void:
	var visible_ratio: float = max(0.02, ratio)
	instance.scale.x = visible_ratio
	instance.position.x = -background_width * 0.5 + foreground_width * 0.5 * visible_ratio


func _health_bar(color: Color, size: Vector3) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = _material(color)
	return instance


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	if color.a < 0.99:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.5
	material.metallic = 0.18
	return material


func _team_palette(team_name: String) -> Color:
	if team_name == "player":
		return Color("#2ec8e6")
	if team_name == "enemy":
		return Color("#f05c67")
	return Color("#a7b7c8")

