class_name RtsResourceView
extends Node3D

const AssetLibraryScript = preload("res://src/presentation/rts_asset_library.gd")

const CLUSTER_OFFSETS := [
	Vector3(-2.15, 0.0, -1.20),
	Vector3(-0.70, 0.0, -1.58),
	Vector3(0.95, 0.0, -1.42),
	Vector3(2.20, 0.0, -0.35),
	Vector3(-2.30, 0.0, 0.48),
	Vector3(-0.82, 0.0, 0.52),
	Vector3(0.72, 0.0, 0.88),
	Vector3(1.88, 0.0, 1.28),
]
const CLUSTER_SCALES := [0.62, 0.48, 0.56, 0.44, 0.50, 0.67, 0.46, 0.52]

var resource_id := ""
var resource_ring: MeshInstance3D
var selection_ring: MeshInstance3D
var resource_label: Label3D
var cluster_visuals: Array[Node3D] = []


func setup(resource: Dictionary) -> void:
	resource_id = str(resource.get("id", ""))
	position = resource.get("position", Vector3.ZERO)
	_build_visuals()
	sync(resource, false)


func sync(resource: Dictionary, selected: bool) -> void:
	var visibility_state := str(resource.get("visibility_state", "visible"))
	visible = visibility_state != "hidden"
	if not visible:
		return
	var remaining: float = max(0.0, float(resource.get("remaining", 0.0)))
	var initial_remaining: float = max(0.0, float(resource.get("initial_remaining", remaining)))
	var depleted := bool(resource.get("depleted", remaining <= 0.01))
	var remaining_ratio: float = 0.0 if initial_remaining <= 0.01 else clampf(remaining / initial_remaining, 0.0, 1.0)
	var visible_cluster_total: int = 0 if depleted else maxi(1, int(ceil(remaining_ratio * cluster_visuals.size())))
	for index in range(cluster_visuals.size()):
		cluster_visuals[index].visible = index < visible_cluster_total
	resource_ring.material_override = _material(Color("#323536") if depleted else Color(0.34, 0.27, 0.16, 0.50), 0.78, 0.02)
	selection_ring.visible = selected
	var display_name := str(resource.get("display_name", "Energy Field"))
	if depleted:
		resource_label.text = "%s\nDEPLETED" % display_name
		resource_label.modulate = Color("#9e9488")
	else:
		resource_label.text = "%s\nENERGY %d / %d" % [display_name, int(remaining), int(initial_remaining)]
		resource_label.modulate = Color("#e1b55d")


func visible_cluster_count() -> int:
	var count := 0
	for cluster in cluster_visuals:
		if cluster.visible:
			count += 1
	return count


func _build_visuals() -> void:
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 3.15
	ring_mesh.outer_radius = 3.35
	ring_mesh.rings = 32
	ring_mesh.ring_segments = 8
	resource_ring = MeshInstance3D.new()
	resource_ring.name = "ResourceRing"
	resource_ring.mesh = ring_mesh
	resource_ring.position.y = 0.04
	add_child(resource_ring)

	var selection_mesh := TorusMesh.new()
	selection_mesh.inner_radius = 3.48
	selection_mesh.outer_radius = 3.70
	selection_mesh.rings = 36
	selection_mesh.ring_segments = 8
	selection_ring = MeshInstance3D.new()
	selection_ring.name = "ResourceSelectionRing"
	selection_ring.mesh = selection_mesh
	selection_ring.position.y = 0.08
	selection_ring.material_override = _material(Color(0.92, 0.72, 0.30, 0.70), 0.38, 0.08)
	selection_ring.visible = false
	add_child(selection_ring)

	for index in range(CLUSTER_OFFSETS.size()):
		var asset_key := "resource_cluster_a" if index % 2 == 0 else "resource_cluster_b"
		var cluster := AssetLibraryScript.attach_asset(self, asset_key, "neutral")
		if cluster == null:
			continue
		cluster.position = CLUSTER_OFFSETS[index]
		cluster.rotation.y = deg_to_rad(float(index * 47 + 12))
		cluster.scale *= float(CLUSTER_SCALES[index])
		cluster_visuals.append(cluster)

	resource_label = Label3D.new()
	resource_label.name = "ResourceLabel"
	resource_label.position.y = 2.8
	resource_label.font_size = 27
	resource_label.outline_size = 7
	resource_label.outline_modulate = Color(0.02, 0.03, 0.05, 0.9)
	resource_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	resource_label.no_depth_test = true
	add_child(resource_label)


func _material(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	if color.a < 0.99:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = roughness
	material.metallic = metallic
	return material
