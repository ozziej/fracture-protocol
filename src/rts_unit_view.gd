class_name RtsUnitView
extends Node3D

const AssetLibraryScript = preload("res://src/presentation/rts_asset_library.gd")
const BillboardHelperScript = preload("res://src/presentation/rts_billboard_helper.gd")

var entity_id := ""
var team := "neutral"
var kind := ""

var body_mesh: MeshInstance3D
var selection_disc: MeshInstance3D
var target_flash_disc: MeshInstance3D
var attack_range_ring: MeshInstance3D
var minimum_range_ring: MeshInstance3D
var under_fire_ring: MeshInstance3D
var order_line: MeshInstance3D
var order_target: MeshInstance3D
var health_back: MeshInstance3D
var health_front: MeshInstance3D
var cargo_back: MeshInstance3D
var cargo_front: MeshInstance3D
var name_label: Label3D
var under_fire_marker: Label3D
var status_billboard: Node3D
var asset_visual: Node3D
var team_marker: MeshInstance3D
var visual_initialized := false
var last_authoritative_position := Vector3.ZERO


func setup(data: Dictionary) -> void:
	entity_id = data["id"]
	team = data["team"]
	kind = data["kind"]
	_build_visuals()
	sync(data, false)


func sync(data: Dictionary, selected: bool, frame_delta: float = 0.0) -> void:
	var desired_position: Vector3 = data["position"]
	var was_initialized := visual_initialized
	var travel_direction := desired_position - last_authoritative_position if was_initialized else Vector3.ZERO
	travel_direction.y = 0.0
	if not was_initialized or frame_delta <= 0.0 or global_position.distance_to(desired_position) > 8.0:
		global_position = desired_position
		visual_initialized = true
	else:
		var position_blend: float = 1.0 - exp(-frame_delta * 24.0)
		global_position = global_position.lerp(desired_position, position_blend)
	var movement_order: bool = data["order"] == "move" or data["order"] == "attack_move" or data["order"] == "patrol"
	if travel_direction.length_squared() <= 0.0004 and movement_order:
		travel_direction = data["target_position"] - desired_position
		travel_direction.y = 0.0
	_update_facing(travel_direction, frame_delta)
	_sync_status_billboard()
	last_authoritative_position = desired_position
	selection_disc.visible = selected
	var attack_range := float(data.get("attack_range", 0.0))
	var minimum_attack_range := float(data.get("minimum_attack_range", 0.0))
	var show_attack_range := selected and team == "player" and kind != "collector" and attack_range > 0.0
	if attack_range_ring:
		attack_range_ring.visible = show_attack_range
		attack_range_ring.scale = Vector3.ONE * max(0.1, attack_range)
	if minimum_range_ring:
		minimum_range_ring.visible = show_attack_range and minimum_attack_range > 0.0
		minimum_range_ring.scale = Vector3.ONE * max(0.1, minimum_attack_range)
	var under_fire := bool(data.get("under_fire", false))
	if under_fire_ring:
		under_fire_ring.visible = under_fire
	if under_fire_marker:
		under_fire_marker.visible = under_fire
	var health_ratio: float = clamp(float(data["health"]) / max(1.0, float(data["max_health"])), 0.0, 1.0)
	_set_progress_bar(health_front, health_ratio, 1.58, 1.42)
	if cargo_front and cargo_back:
		var cargo_capacity: float = max(1.0, float(data.get("collector_capacity", 0.0)))
		var cargo_ratio: float = clamp(float(data.get("collector_cargo", 0.0)) / cargo_capacity, 0.0, 1.0)
		cargo_back.visible = kind == "collector"
		cargo_front.visible = kind == "collector"
		_set_progress_bar(cargo_front, cargo_ratio, 1.58, 1.42)
	var supply_state: String = str(data.get("supply_state", "connected"))
	var order: String = str(data.get("order", "idle"))
	var label_text: String = data["display_name"]
	if order != "idle":
		label_text += "\n" + order.replace("_", "-").to_upper()
	var queued_waypoint_count: int = data.get("command_waypoints", []).size()
	if queued_waypoint_count > 0:
		label_text += "\nQUEUE " + str(queued_waypoint_count)
	if supply_state == "unsupplied":
		label_text += "\n! UNSUPPLIED"
	if under_fire:
		label_text += "\n! UNDER FIRE"
	var collector_state: String = str(data.get("collector_state", ""))
	if not collector_state.is_empty():
		var collector_route_label := collector_state.replace("_", "-").to_upper()
		if collector_state == "to_source":
			collector_route_label = "SOURCE " + str(data.get("collector_source_name", ""))
		elif collector_state == "to_destination":
			collector_route_label = "TO " + str(data.get("collector_destination_name", ""))
		elif collector_state == "retreating":
			collector_route_label = "RETREAT TO BASE"
		elif collector_state == "loading":
			collector_route_label = "RECOVERING ENERGY"
		elif collector_state == "unloading":
			collector_route_label = "DEPOSITING ENERGY"
		elif collector_state == "awaiting_source":
			collector_route_label = "WAITING FOR NEARBY FIELD"
		label_text += "\n" + collector_route_label
		if float(data.get("collector_capacity", 0.0)) > 0.0:
			label_text += " %d/%d" % [int(data.get("collector_cargo", 0.0)), int(data.get("collector_capacity", 0.0))]
	name_label.text = label_text
	name_label.modulate = Color("#ffbf6a") if supply_state == "unsupplied" else _team_palette(team).lightened(0.45)
	_update_order_marker(data, selected)


func apply_terrain_height(height: float, frame_delta: float = 0.0) -> void:
	var target_position := global_position
	if frame_delta <= 0.0:
		target_position.y = height
	else:
		target_position.y = lerpf(global_position.y, height, 1.0 - exp(-frame_delta * 18.0))
	global_position = target_position
	_sync_status_billboard()


func flash_target() -> void:
	if target_flash_disc == null:
		return
	target_flash_disc.visible = true
	target_flash_disc.scale = Vector3.ONE * 0.72
	var tween := create_tween()
	tween.tween_property(target_flash_disc, "scale", Vector3.ONE * 1.42, 0.14)
	tween.tween_interval(0.2)
	tween.tween_callback(Callable(self, "_hide_target_flash"))


func _hide_target_flash() -> void:
	if target_flash_disc:
		target_flash_disc.visible = false

func _build_visuals() -> void:
	var palette := _team_palette(team)
	var definition_height := 1.0
	if kind == "warden" or kind == "bulwark":
		definition_height = 0.8
	elif kind == "command_carrier":
		definition_height = 1.15
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
	elif kind == "command_carrier":
		var carrier_body := BoxMesh.new()
		carrier_body.size = Vector3(1.55, 0.46, 2.15)
		var carrier_instance := MeshInstance3D.new()
		carrier_instance.mesh = carrier_body
		carrier_instance.material_override = _material(palette.lightened(0.12))
		carrier_instance.position = Vector3(0.0, definition_height * 0.78, 0.0)
		add_child(carrier_instance)
		var carrier_beacon := CylinderMesh.new()
		carrier_beacon.top_radius = 0.12
		carrier_beacon.bottom_radius = 0.16
		carrier_beacon.height = 0.48
		carrier_beacon.radial_segments = 10
		var beacon_instance := MeshInstance3D.new()
		beacon_instance.mesh = carrier_beacon
		beacon_instance.material_override = _material(Color("#ffd36a"))
		beacon_instance.position = Vector3(0.0, definition_height + 0.35, 0.0)
		add_child(beacon_instance)

	_attach_asset_visual()
	var marker_mesh := BoxMesh.new()
	var marker_width := 0.48 if kind == "warden" or kind == "bulwark" else 0.34
	if kind == "command_carrier":
		marker_width = 0.58
	marker_mesh.size = Vector3(marker_width, 0.075, marker_width * 0.62)
	team_marker = MeshInstance3D.new()
	team_marker.name = "TeamMarker"
	team_marker.mesh = marker_mesh
	team_marker.material_override = _material(palette)
	var marker_height := 0.92
	if kind == "warden":
		marker_height = 1.18
	elif kind == "bulwark":
		marker_height = 1.31
	elif kind == "command_carrier":
		marker_height = 1.66
	team_marker.position = Vector3(0.0, marker_height, 0.12)
	add_child(team_marker)

	var disc := TorusMesh.new()
	disc.inner_radius = 0.70
	disc.outer_radius = 0.88
	disc.rings = 24
	disc.ring_segments = 8
	selection_disc = MeshInstance3D.new()
	selection_disc.mesh = disc
	selection_disc.material_override = _material(Color(0.22, 0.68, 0.78, 0.62))
	selection_disc.position.y = 0.06
	if kind == "command_carrier":
		# Match the selectable marker to the composed train footprint instead of
		# leaving a tiny unit-sized ring at one point beneath a long vehicle.
		selection_disc.scale = Vector3(1.35, 1.0, 3.4)
	selection_disc.visible = false
	add_child(selection_disc)

	var flash_ring := TorusMesh.new()
	flash_ring.inner_radius = 0.92
	flash_ring.outer_radius = 1.12
	flash_ring.rings = 24
	flash_ring.ring_segments = 8
	target_flash_disc = MeshInstance3D.new()
	target_flash_disc.name = "TargetFlash"
	target_flash_disc.mesh = flash_ring
	target_flash_disc.material_override = _material(Color("#ff6b5f"))
	target_flash_disc.position.y = 0.08
	target_flash_disc.visible = false
	add_child(target_flash_disc)

	var range_disc := TorusMesh.new()
	range_disc.inner_radius = 0.98
	range_disc.outer_radius = 1.03
	range_disc.rings = 48
	range_disc.ring_segments = 8
	attack_range_ring = MeshInstance3D.new()
	attack_range_ring.name = "AttackRange"
	attack_range_ring.mesh = range_disc
	attack_range_ring.material_override = _material(Color(0.98, 0.72, 0.28, 0.28))
	attack_range_ring.position.y = 0.065
	attack_range_ring.visible = false
	add_child(attack_range_ring)

	var minimum_disc := TorusMesh.new()
	minimum_disc.inner_radius = 0.98
	minimum_disc.outer_radius = 1.04
	minimum_disc.rings = 48
	minimum_disc.ring_segments = 8
	minimum_range_ring = MeshInstance3D.new()
	minimum_range_ring.name = "MinimumAttackRange"
	minimum_range_ring.mesh = minimum_disc
	minimum_range_ring.material_override = _material(Color(1.0, 0.35, 0.30, 0.48))
	minimum_range_ring.position.y = 0.07
	minimum_range_ring.visible = false
	add_child(minimum_range_ring)

	var threat_disc := TorusMesh.new()
	threat_disc.inner_radius = 1.03
	threat_disc.outer_radius = 1.18
	threat_disc.rings = 28
	threat_disc.ring_segments = 8
	under_fire_ring = MeshInstance3D.new()
	under_fire_ring.name = "UnderFire"
	under_fire_ring.mesh = threat_disc
	under_fire_ring.material_override = _material(Color(1.0, 0.28, 0.24, 0.9))
	under_fire_ring.position.y = 0.1
	under_fire_ring.visible = false
	add_child(under_fire_ring)

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

	status_billboard = Node3D.new()
	status_billboard.name = "StatusBillboard"
	status_billboard.top_level = true
	add_child(status_billboard)

	health_back = _health_bar(Color(0.025, 0.035, 0.045, 1.0), Vector3(1.58, 0.17, 0.055))
	health_back.position = Vector3(0.0, definition_height + 0.4, 0.0)
	status_billboard.add_child(health_back)
	health_front = _health_bar(Color(0.28, 0.94, 0.55, 1.0), Vector3(1.42, 0.105, 0.06))
	health_front.position = Vector3(0.0, definition_height + 0.4, 0.04)
	status_billboard.add_child(health_front)

	if kind == "collector":
		cargo_back = _health_bar(Color(0.025, 0.035, 0.045, 1.0), Vector3(1.58, 0.15, 0.055))
		cargo_back.position = Vector3(0.0, definition_height + 0.22, 0.0)
		status_billboard.add_child(cargo_back)
		cargo_front = _health_bar(Color("#f3bd52"), Vector3(1.42, 0.09, 0.06))
		cargo_front.position = Vector3(0.0, definition_height + 0.22, 0.04)
		status_billboard.add_child(cargo_front)

	name_label = Label3D.new()
	name_label.position = Vector3(0.0, definition_height + 0.76, 0.0)
	name_label.font_size = 32
	name_label.modulate = palette.lightened(0.45)
	name_label.outline_size = 8
	name_label.outline_modulate = Color(0.01, 0.02, 0.04, 0.9)
	name_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	name_label.no_depth_test = true
	status_billboard.add_child(name_label)
	under_fire_marker = Label3D.new()
	under_fire_marker.name = "UnderFireMarker"
	under_fire_marker.text = "! UNDER FIRE"
	under_fire_marker.position = Vector3(0.0, definition_height + 1.08, 0.0)
	under_fire_marker.font_size = 28
	under_fire_marker.modulate = Color("#ff7b86")
	under_fire_marker.outline_size = 8
	under_fire_marker.outline_modulate = Color(0.01, 0.02, 0.04, 0.92)
	under_fire_marker.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	under_fire_marker.no_depth_test = true
	under_fire_marker.visible = false
	status_billboard.add_child(under_fire_marker)


func _sync_status_billboard() -> void:
	BillboardHelperScript.sync_to_camera(status_billboard, global_position, get_viewport())


func _attach_asset_visual() -> void:
	if kind == "command_carrier":
		asset_visual = _build_command_carrier_consist()
	else:
		asset_visual = AssetLibraryScript.attach_asset(self, kind, team)
	if asset_visual == null:
		return
	# Keep the procedural meshes in the node as a deterministic fallback and
	# preserve their references for smoke tests, but let the authored asset own
	# the visible silhouette when its export is available.
	for child in get_children():
		if child is MeshInstance3D:
			child.visible = false


func _build_command_carrier_consist() -> Node3D:
	var consist := Node3D.new()
	consist.name = "KenneyAsset_command_carrier"
	add_child(consist)
	var pieces := [
		"monorail_train_front",
		"monorail_train_box",
		"monorail_train_passenger",
		"monorail_train_end",
	]
	var piece_scale := 1.5
	var piece_spacing := 1.46
	var centre_offset := float(pieces.size() - 1) * 0.5
	for piece_index in pieces.size():
		var piece := AssetLibraryScript.attach_asset(consist, str(pieces[piece_index]), team)
		if piece == null:
			continue
		piece.scale = Vector3.ONE * piece_scale
		piece.position = Vector3(0.0, 0.04, (float(piece_index) - centre_offset) * piece_spacing)
	var bounds := _node_bounds(consist, Transform3D.IDENTITY, AABB())
	if bounds.size != Vector3.ZERO:
		# Kenney train cars use an end-biased authored origin. Centre the complete
		# consist on the simulation entity so the model, health label, ring and
		# pointer hit target all refer to the same world position.
		consist.position = Vector3(-bounds.get_center().x, -bounds.position.y, -bounds.get_center().z)
	return consist if consist.get_child_count() > 0 else null


func _node_bounds(node: Node, parent_transform: Transform3D, current: AABB) -> AABB:
	var transform := parent_transform
	if node is Node3D:
		transform = parent_transform * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh:
		var next_bounds := transform * (node as MeshInstance3D).mesh.get_aabb()
		current = next_bounds if current.size == Vector3.ZERO else current.merge(next_bounds)
	for child in node.get_children():
		current = _node_bounds(child, transform, current)
	return current


func _update_facing(direction: Vector3, frame_delta: float) -> void:
	if direction.length_squared() <= 0.0004:
		return
	var previous_rotation := rotation
	var look_target := global_position + direction.normalized()
	look_at(Vector3(look_target.x, global_position.y, look_target.z), Vector3.UP)
	var desired_yaw := rotation.y
	rotation = previous_rotation
	if frame_delta <= 0.0:
		rotation.y = desired_yaw
	else:
		rotation.y = lerp_angle(previous_rotation.y, desired_yaw, 1.0 - exp(-frame_delta * 20.0))


func _update_order_marker(data: Dictionary, selected: bool) -> void:
	var order: String = str(data.get("order", "idle"))
	var show_marker := selected and (order == "move" or order == "attack_move" or order == "patrol")
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


func _set_progress_bar(instance: MeshInstance3D, ratio: float, _background_width: float, foreground_width: float) -> void:
	var visible_ratio: float = max(0.02, ratio)
	instance.scale.x = visible_ratio
	instance.position.x = -foreground_width * 0.5 + foreground_width * 0.5 * visible_ratio


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
		return Color("#2aa8b8")
	if team_name == "enemy":
		return Color("#c95764")
	return Color("#a7b7c8")
