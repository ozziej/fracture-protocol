class_name RtsBuildingView
extends Node3D

var entity_id := ""
var team := "neutral"
var kind := ""
var body_mesh: MeshInstance3D
var cap_mesh: MeshInstance3D
var antenna_mesh: MeshInstance3D
var rally_marker: MeshInstance3D
var selection_disc: MeshInstance3D
var visual_body_height := 0.0
var visual_antenna_height := 0.0
var health_back: MeshInstance3D
var health_front: MeshInstance3D
var name_label: Label3D


func setup(data: Dictionary) -> void:
	entity_id = data["id"]
	team = data["team"]
	kind = data["kind"]
	_build_visuals()
	sync(data, false)


func sync(data: Dictionary, selected: bool) -> void:
	global_position = data["position"]
	selection_disc.visible = selected
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
	var occupied_height: float = visual_body_height * body_scale
	health_back.position.y = occupied_height + 2.65
	health_front.position.y = occupied_height + 2.65
	name_label.position.y = occupied_height + 3.02
	var health_ratio: float = clamp(float(data["health"]) / max(1.0, float(data["max_health"])), 0.0, 1.0)
	_set_progress_bar(health_front, health_ratio, 2.5, 2.5)
	var label_text: String = data["display_name"] if data["complete"] else "CONSTRUCTING %d%%" % int(construction_progress * 100.0)
	var research_id: String = str(data.get("research_id", ""))
	if data["complete"] and not research_id.is_empty():
		var research_total: float = max(0.1, float(data.get("research_total", 0.0)))
		var research_progress: float = clamp(1.0 - float(data.get("research_remaining", 0.0)) / research_total, 0.0, 1.0)
		label_text += "\nRESEARCH %s %d%%" % [research_id.replace("_", "-").to_upper(), int(research_progress * 100.0)]
	name_label.text = label_text


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

	var disc := CylinderMesh.new()
	disc.top_radius = max(body_size.x, body_size.z) * 0.68
	disc.bottom_radius = disc.top_radius
	disc.height = 0.045
	disc.radial_segments = 28
	selection_disc = MeshInstance3D.new()
	selection_disc.mesh = disc
	selection_disc.material_override = _material(Color(0.38, 0.92, 1.0, 0.8))
	selection_disc.position.y = 0.04
	selection_disc.visible = false
	add_child(selection_disc)

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

	health_back = _health_bar(Color(0.06, 0.08, 0.11, 1.0), Vector3(2.5, 0.1, 0.1))
	health_back.position = Vector3(0.0, body_size.y + 2.65, 0.0)
	add_child(health_back)
	health_front = _health_bar(Color(0.28, 0.94, 0.55, 1.0), Vector3(2.5, 0.12, 0.12))
	health_front.position = Vector3(0.0, body_size.y + 2.65, 0.04)
	add_child(health_front)

	name_label = Label3D.new()
	name_label.position = Vector3(0.0, body_size.y + 3.02, 0.0)
	name_label.font_size = 36
	name_label.modulate = palette.lightened(0.45)
	name_label.outline_size = 9
	name_label.outline_modulate = Color(0.01, 0.02, 0.04, 0.9)
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_label.no_depth_test = true
	add_child(name_label)


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
	material.roughness = 0.43
	material.metallic = 0.3
	return material


func _team_palette(team_name: String) -> Color:
	if team_name == "player":
		return Color("#2ec8e6")
	if team_name == "enemy":
		return Color("#f05c67")
	return Color("#a7b7c8")

