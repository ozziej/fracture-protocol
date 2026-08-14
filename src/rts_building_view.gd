class_name RtsBuildingView
extends Node3D

const AssetLibraryScript = preload("res://src/presentation/rts_asset_library.gd")
const BillboardHelperScript = preload("res://src/presentation/rts_billboard_helper.gd")

var entity_id := ""
var team := "neutral"
var kind := ""
var repair_radius := 0.0
var body_mesh: MeshInstance3D
var cap_mesh: MeshInstance3D
var antenna_mesh: MeshInstance3D
var rally_marker: MeshInstance3D
var selection_disc: MeshInstance3D
var target_flash_disc: MeshInstance3D
var under_fire_ring: MeshInstance3D
var repair_zone: MeshInstance3D
var repair_zone_ring: MeshInstance3D
var visual_body_height := 0.0
var visual_antenna_height := 0.0
var health_back: MeshInstance3D
var health_front: MeshInstance3D
var name_label: Label3D
var under_fire_marker: Label3D
var status_billboard: Node3D
var asset_visual: Node3D
var asset_variant := ""
var team_marker: MeshInstance3D
var visual_marker_height := 2.0


func setup(data: Dictionary) -> void:
	entity_id = data["id"]
	team = data["team"]
	kind = data["kind"]
	repair_radius = float(data.get("repair_radius", 0.0))
	_build_visuals()
	sync(data, false)


func sync(data: Dictionary, selected: bool) -> void:
	global_position = data["position"]
	_sync_status_billboard()
	selection_disc.visible = selected
	var under_fire := bool(data.get("under_fire", false))
	if under_fire_ring:
		under_fire_ring.visible = under_fire
	if under_fire_marker:
		under_fire_marker.visible = under_fire
	if repair_zone:
		var zone_visible := repair_radius > 0.0 and team == "player" and bool(data.get("complete", false))
		repair_zone.visible = zone_visible
		repair_zone_ring.visible = zone_visible
	if rally_marker:
		var rally_position: Vector3 = data.get("rally_position", data["position"])
		rally_marker.position = Vector3(rally_position.x - data["position"].x, 0.08, rally_position.z - data["position"].z)
		rally_marker.visible = selected and bool(data.get("rally_enabled", false)) and not bool(data.get("rally_suspended", false))
	var construction_progress: float = clamp(float(data["construction_progress"]), 0.0, 1.0)
	var body_scale: float = 0.3 + construction_progress * 0.7
	body_mesh.scale.y = body_scale
	body_mesh.position.y = visual_body_height * body_scale * 0.5
	if cap_mesh:
		cap_mesh.scale.y = body_scale
		cap_mesh.position.y = visual_body_height * body_scale + 0.12 * body_scale
	if antenna_mesh:
		antenna_mesh.visible = construction_progress >= 0.95
		antenna_mesh.position.y = visual_body_height * body_scale + visual_antenna_height * 0.5 + 0.2
	var desired_variant := "upgraded" if bool(data.get("upgrade_complete", false)) or not str(data.get("completed_upgrade_id", "")).is_empty() else ""
	if desired_variant != asset_variant and AssetLibraryScript.has_variant(kind, desired_variant):
		_replace_asset_visual(desired_variant)
	if asset_visual:
		var asset_scale := AssetLibraryScript.scale_for(kind)
		asset_visual.scale = Vector3(asset_scale.x, asset_scale.y * body_scale, asset_scale.z)
	if team_marker:
		team_marker.position.y = visual_marker_height * body_scale
	var occupied_height: float = visual_body_height * body_scale
	health_back.position.y = occupied_height + 2.65
	health_front.position.y = occupied_height + 2.65
	name_label.position.y = occupied_height + 3.02
	var health_ratio: float = clamp(float(data["health"]) / max(1.0, float(data["max_health"])), 0.0, 1.0)
	_set_progress_bar(health_front, health_ratio, 2.9, 2.68)
	var label_text: String = data["display_name"] if data["complete"] else "CONSTRUCTING %d%%" % int(construction_progress * 100.0)
	var research_id: String = str(data.get("research_id", ""))
	if data["complete"] and not research_id.is_empty():
		var research_total: float = max(0.1, float(data.get("research_total", 0.0)))
		var research_progress: float = clamp(1.0 - float(data.get("research_remaining", 0.0)) / research_total, 0.0, 1.0)
		label_text += "\nRESEARCH %s %d%%" % [research_id.replace("_", "-").to_upper(), int(research_progress * 100.0)]
	if under_fire:
		label_text += "\n! UNDER FIRE"
	name_label.text = label_text


func flash_target() -> void:
	if target_flash_disc == null:
		return
	target_flash_disc.visible = true
	target_flash_disc.scale = Vector3.ONE * 0.72
	var tween := create_tween()
	tween.tween_property(target_flash_disc, "scale", Vector3.ONE * 1.38, 0.14)
	tween.tween_interval(0.2)
	tween.tween_callback(Callable(self, "_hide_target_flash"))


func _hide_target_flash() -> void:
	if target_flash_disc:
		target_flash_disc.visible = false


func _build_visuals() -> void:
	var palette := _team_palette(team)
	var body_size := Vector3(3.4, 1.6, 3.4)
	if kind == "command_hub":
		body_size = Vector3(5.2, 2.8, 4.5)
	elif kind == "relay":
		body_size = Vector3(2.5, 2.2, 2.5)
	elif kind == "assembly_bay":
		body_size = Vector3(3.6, 2.0, 3.1)
	elif kind == "tech_centre":
		body_size = Vector3(3.1, 2.4, 3.1)
	elif kind == "storage_silo":
		body_size = Vector3(2.2, 2.8, 2.2)
	visual_marker_height = body_size.y + 0.16
	if kind == "command_hub":
		visual_marker_height = 3.15
	elif kind == "refinery":
		visual_marker_height = 2.55
	elif kind == "assembly_bay":
		visual_marker_height = 3.45
	elif kind == "tech_centre":
		visual_marker_height = 2.52
	elif kind == "storage_silo":
		visual_marker_height = 2.38
	elif kind == "relay":
		visual_marker_height = 2.85

	visual_body_height = body_size.y
	var body := BoxMesh.new()
	body.size = body_size
	body_mesh = MeshInstance3D.new()
	body_mesh.mesh = body
	body_mesh.material_override = _material(palette.darkened(0.2))
	body_mesh.position.y = body_size.y * 0.5
	add_child(body_mesh)

	var cap := BoxMesh.new()
	cap.size = Vector3(body_size.x * 0.68, 0.22, body_size.z * 0.68)
	cap_mesh = MeshInstance3D.new()
	cap_mesh.mesh = cap
	cap_mesh.material_override = _material(palette.lightened(0.12))
	cap_mesh.position.y = body_size.y + 0.12
	add_child(cap_mesh)

	if kind == "command_hub" or kind == "relay":
		var antenna := CylinderMesh.new()
		antenna.top_radius = 0.07
		antenna.bottom_radius = 0.11
		antenna.height = 2.2 if kind == "command_hub" else 1.6
		antenna.radial_segments = 8
		visual_antenna_height = antenna.height
		antenna_mesh = MeshInstance3D.new()
		antenna_mesh.mesh = antenna
		antenna_mesh.material_override = _material(Color("#d9fbff"))
		antenna_mesh.position.y = body_size.y + antenna.height * 0.5 + 0.2
		add_child(antenna_mesh)

	_attach_asset_visual()
	if repair_radius > 0.0:
		var zone_mesh := CylinderMesh.new()
		zone_mesh.top_radius = repair_radius
		zone_mesh.bottom_radius = repair_radius
		zone_mesh.height = 0.025
		zone_mesh.radial_segments = 64
		repair_zone = MeshInstance3D.new()
		repair_zone.name = "RepairInfluence"
		repair_zone.mesh = zone_mesh
		repair_zone.material_override = _material(Color(0.22, 0.95, 0.48, 0.075))
		repair_zone.position.y = 0.025
		repair_zone.visible = false
		add_child(repair_zone)
		var ring_mesh := TorusMesh.new()
		ring_mesh.outer_radius = repair_radius
		ring_mesh.inner_radius = max(0.1, repair_radius - 0.16)
		ring_mesh.rings = 64
		ring_mesh.ring_segments = 8
		repair_zone_ring = MeshInstance3D.new()
		repair_zone_ring.name = "RepairInfluenceRing"
		repair_zone_ring.mesh = ring_mesh
		repair_zone_ring.material_override = _material(Color(0.3, 1.0, 0.58, 0.82))
		repair_zone_ring.position.y = 0.07
		repair_zone_ring.visible = false
		add_child(repair_zone_ring)
	var marker_mesh := BoxMesh.new()
	marker_mesh.size = Vector3(minf(body_size.x * 0.22, 1.05), 0.10, 0.28)
	team_marker = MeshInstance3D.new()
	team_marker.name = "TeamMarker"
	team_marker.mesh = marker_mesh
	team_marker.material_override = _material(palette)
	team_marker.position = Vector3(0.0, visual_marker_height, -body_size.z * 0.18)
	add_child(team_marker)

	var disc := TorusMesh.new()
	disc.outer_radius = max(body_size.x, body_size.z) * 0.68
	disc.inner_radius = max(0.2, disc.outer_radius - 0.2)
	disc.rings = 32
	disc.ring_segments = 8
	selection_disc = MeshInstance3D.new()
	selection_disc.mesh = disc
	selection_disc.material_override = _material(Color(0.22, 0.68, 0.78, 0.58))
	selection_disc.position.y = 0.07
	selection_disc.visible = false
	add_child(selection_disc)

	var target_disc := TorusMesh.new()
	target_disc.outer_radius = max(body_size.x, body_size.z) * 0.82
	target_disc.inner_radius = max(0.2, target_disc.outer_radius - 0.22)
	target_disc.rings = 32
	target_disc.ring_segments = 8
	target_flash_disc = MeshInstance3D.new()
	target_flash_disc.name = "TargetFlash"
	target_flash_disc.mesh = target_disc
	target_flash_disc.material_override = _material(Color("#ff6b5f"))
	target_flash_disc.position.y = 0.09
	target_flash_disc.visible = false
	add_child(target_flash_disc)

	var threat_disc := TorusMesh.new()
	threat_disc.inner_radius = max(body_size.x, body_size.z) * 0.76
	threat_disc.outer_radius = max(body_size.x, body_size.z) * 0.86
	threat_disc.rings = 40
	threat_disc.ring_segments = 8
	under_fire_ring = MeshInstance3D.new()
	under_fire_ring.name = "UnderFire"
	under_fire_ring.mesh = threat_disc
	under_fire_ring.material_override = _material(Color(1.0, 0.28, 0.24, 0.9))
	under_fire_ring.position.y = 0.1
	under_fire_ring.visible = false
	add_child(under_fire_ring)

	if kind == "assembly_bay":
		var rally_mesh := CylinderMesh.new()
		rally_mesh.top_radius = 0.82
		rally_mesh.bottom_radius = 0.82
		rally_mesh.height = 0.055
		rally_mesh.radial_segments = 24
		rally_marker = MeshInstance3D.new()
		rally_marker.name = "RallyMarker"
		rally_marker.mesh = rally_mesh
		rally_marker.material_override = _material(Color("#ffd36a"))
		rally_marker.visible = false
		add_child(rally_marker)

	status_billboard = Node3D.new()
	status_billboard.name = "StatusBillboard"
	status_billboard.top_level = true
	add_child(status_billboard)

	health_back = _health_bar(Color(0.025, 0.035, 0.045, 1.0), Vector3(2.9, 0.22, 0.07))
	health_back.position = Vector3(0.0, body_size.y + 2.65, 0.0)
	status_billboard.add_child(health_back)
	health_front = _health_bar(Color(0.28, 0.94, 0.55, 1.0), Vector3(2.68, 0.135, 0.075))
	health_front.position = Vector3(0.0, body_size.y + 2.65, 0.05)
	status_billboard.add_child(health_front)

	name_label = Label3D.new()
	name_label.position = Vector3(0.0, body_size.y + 3.02, 0.0)
	name_label.font_size = 36
	name_label.modulate = palette.lightened(0.45)
	name_label.outline_size = 9
	name_label.outline_modulate = Color(0.01, 0.02, 0.04, 0.9)
	name_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	name_label.no_depth_test = true
	status_billboard.add_child(name_label)
	under_fire_marker = Label3D.new()
	under_fire_marker.name = "UnderFireMarker"
	under_fire_marker.text = "! UNDER FIRE"
	under_fire_marker.position = Vector3(0.0, body_size.y + 3.45, 0.0)
	under_fire_marker.font_size = 30
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
	asset_visual = AssetLibraryScript.attach_asset(self, kind, team, asset_variant)
	if asset_visual == null:
		return
	# Construction, selection, rally, health, and labels remain owned by this
	# view. Only the old procedural body meshes are hidden behind the asset.
	for child in get_children():
		if child is MeshInstance3D:
			child.visible = false


func _replace_asset_visual(variant: String) -> void:
	if asset_visual:
		asset_visual.queue_free()
	asset_variant = variant
	asset_visual = AssetLibraryScript.attach_asset(self, kind, team, asset_variant)


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
	material.roughness = 0.43
	material.metallic = 0.3
	return material


func _team_palette(team_name: String) -> Color:
	if team_name == "player":
		return Color("#2aa8b8")
	if team_name == "enemy":
		return Color("#c95764")
	return Color("#a7b7c8")
