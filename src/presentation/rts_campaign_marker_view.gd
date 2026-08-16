class_name RtsCampaignMarkerView
extends Node3D

## Presentation-only marker for authored campaign objectives. It is deliberately
## generic so mission data can identify recovery, relay, route, and deployment
## locations without introducing simulation-side scene nodes.

var marker_id := ""
var marker_type := "objective"
var elapsed := 0.0
var ring_scale := 1.0
var ring: MeshInstance3D
var beacon: MeshInstance3D
var beacon_cap: MeshInstance3D
var base_disc: MeshInstance3D
var label: Label3D


func setup(marker_data: Dictionary) -> void:
	_build_visuals()
	sync(marker_data)


func sync(marker_data: Dictionary) -> void:
	marker_id = str(marker_data.get("id", marker_id))
	marker_type = str(marker_data.get("type", "objective"))
	var marker_position: Vector3 = marker_data.get("position", Vector3.ZERO)
	position = marker_position
	var marker_color: Color = marker_data.get("color", Color("#ffd36a"))
	var radius := float(marker_data.get("radius", 3.0))
	var active := bool(marker_data.get("active", true))
	visible = active
	if ring:
		ring_scale = maxf(0.65, radius / 3.0)
		ring.scale = Vector3.ONE * ring_scale
		ring.material_override = _emissive_material(marker_color, 1.65)
	if beacon:
		beacon.material_override = _emissive_material(marker_color.lightened(0.18), 1.25)
	if beacon_cap:
		beacon_cap.material_override = _emissive_material(marker_color.lightened(0.35), 1.6)
	if base_disc:
		base_disc.material_override = _material(Color(marker_color.r, marker_color.g, marker_color.b, 0.16), 0.45, 0.05)
	if label:
		label.text = str(marker_data.get("label", "OBJECTIVE"))
		label.modulate = marker_color.lightened(0.2)
		label.position.y = 5.6 if marker_type == "route" else 5.0


func _process(delta: float) -> void:
	if not visible:
		return
	elapsed += delta
	var pulse := 1.0 + sin(elapsed * 3.1) * 0.08
	if ring:
		ring.scale = Vector3.ONE * ring_scale * pulse
		ring.rotation.y += delta * 0.35
	if beacon:
		beacon.scale.y = 0.92 + sin(elapsed * 2.4) * 0.08


func _build_visuals() -> void:
	base_disc = MeshInstance3D.new()
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 2.6
	base_mesh.bottom_radius = 2.6
	base_mesh.height = 0.06
	base_mesh.radial_segments = 32
	base_disc.mesh = base_mesh
	base_disc.position.y = 0.04
	add_child(base_disc)

	ring = MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 2.55
	ring_mesh.outer_radius = 3.0
	ring_mesh.rings = 36
	ring_mesh.ring_segments = 8
	ring.mesh = ring_mesh
	ring.position.y = 0.16
	add_child(ring)

	beacon = MeshInstance3D.new()
	var beacon_mesh := BoxMesh.new()
	beacon_mesh.size = Vector3(0.14, 4.6, 0.14)
	beacon.mesh = beacon_mesh
	beacon.position.y = 2.3
	add_child(beacon)

	beacon_cap = MeshInstance3D.new()
	var cap_mesh := SphereMesh.new()
	cap_mesh.radius = 0.28
	cap_mesh.height = 0.56
	cap_mesh.radial_segments = 12
	cap_mesh.rings = 6
	beacon_cap.mesh = cap_mesh
	beacon_cap.position.y = 4.7
	add_child(beacon_cap)

	label = Label3D.new()
	label.font_size = 24
	label.outline_size = 7
	label.outline_modulate = Color(0.01, 0.02, 0.04, 0.92)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	add_child(label)
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
