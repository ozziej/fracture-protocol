class_name RtsWorldViewSynchronizer
extends RefCounted

const UnitViewScript = preload("res://src/rts_unit_view.gd")
const BuildingViewScript = preload("res://src/rts_building_view.gd")

## Translates immutable-ish simulation snapshots into scene nodes. This is the
## presentation boundary: it may create or tween nodes, but cannot issue rules.
static func sync(parent: Node3D, state: Dictionary, selected_ids: Array, unit_views: Dictionary, building_views: Dictionary, control_views: Dictionary, resource_views: Dictionary, objective_target_point_id: String, minimap, frame_delta: float) -> void:
	for entity_id in state["units"]:
		if not unit_views.has(entity_id):
			var view = UnitViewScript.new()
			parent.add_child(view)
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
			parent.add_child(view)
			view.setup(state["buildings"][entity_id])
			building_views[entity_id] = view
		building_views[entity_id].sync(state["buildings"][entity_id], selected_ids.has(entity_id))
	for entity_id in building_views.keys():
		if not state["buildings"].has(entity_id):
			building_views[entity_id].queue_free()
			building_views.erase(entity_id)

	for point_id in state["control_points"]:
		if not control_views.has(point_id):
			control_views[point_id] = create_control_view(parent, state["control_points"][point_id])
		update_control_view(control_views[point_id], state["control_points"][point_id], objective_target_point_id)
	for node_id in state["resource_nodes"]:
		if not resource_views.has(node_id):
			resource_views[node_id] = create_resource_view(parent, state["resource_nodes"][node_id])

	if minimap:
		minimap.set_snapshot(state)


static func create_control_view(parent: Node3D, point: Dictionary) -> Node3D:
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
	var objective_beam := MeshInstance3D.new()
	objective_beam.name = "ObjectiveBeam"
	var objective_beam_mesh := BoxMesh.new()
	objective_beam_mesh.size = Vector3(0.15, 5.5, 0.15)
	objective_beam.mesh = objective_beam_mesh
	objective_beam.position.y = 2.8
	objective_beam.material_override = _emissive_material(Color("#ffd36a"), 2.4)
	objective_beam.visible = false
	root.add_child(objective_beam)
	var objective_marker := Label3D.new()
	objective_marker.name = "ObjectiveMarker"
	objective_marker.text = "OBJECTIVE"
	objective_marker.position.y = 6.0
	objective_marker.font_size = 26
	objective_marker.outline_size = 7
	objective_marker.modulate = Color("#ffd36a")
	objective_marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	objective_marker.no_depth_test = true
	objective_marker.visible = false
	root.add_child(objective_marker)

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
	parent.add_child(root)
	return root


static func update_control_view(view: Node3D, point: Dictionary, objective_target_point_id: String) -> void:
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
	var objective_beam := view.get_node_or_null("ObjectiveBeam") as MeshInstance3D
	var objective_marker := view.get_node_or_null("ObjectiveMarker") as Label3D
	var is_objective := str(point["id"]) == objective_target_point_id
	if objective_beam:
		objective_beam.visible = is_objective
	if objective_marker:
		objective_marker.visible = is_objective
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


static func create_resource_view(parent: Node3D, resource: Dictionary) -> Node3D:
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
	parent.add_child(root)
	return root


static func _material(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	if color.a < 0.99:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = roughness
	material.metallic = metallic
	return material


static func _emissive_material(color: Color, energy: float) -> StandardMaterial3D:
	var material := _material(color, 0.3, 0.1)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	return material
