extends SceneTree

const UnitViewScript = preload("res://src/rts_unit_view.gd")
const BuildingViewScript = preload("res://src/rts_building_view.gd")
const ResourceViewScript = preload("res://src/presentation/rts_resource_view.gd")
const AssetLibraryScript = preload("res://src/presentation/rts_asset_library.gd")

const UNIT_KINDS := ["collector", "ranger", "raider", "warden", "bulwark"]
const BUILDING_KINDS := ["command_hub", "refinery", "assembly_bay", "tech_centre", "storage_silo", "relay"]


func _initialize() -> void:
	await process_frame
	var failures: Array[String] = []
	var root_node := Node3D.new()
	root.add_child(root_node)

	for kind in UNIT_KINDS:
		var view = UnitViewScript.new()
		root_node.add_child(view)
		view.setup({
			"id": "asset_%s" % kind,
			"team": "player",
			"kind": kind,
			"position": Vector3.ZERO,
			"target_position": Vector3.ZERO,
			"order": "idle",
			"health": 100.0,
			"max_health": 100.0,
			"display_name": kind.capitalize(),
			"supply_state": "connected",
			"collector_state": "" if kind != "collector" else "unassigned",
			"collector_cargo": 0.0,
			"collector_capacity": 75.0 if kind == "collector" else 0.0,
		})
		if view.asset_visual == null:
			failures.append("%s should load its Kenney runtime asset" % kind)
		elif not _has_visible_mesh(view.asset_visual):
			failures.append("%s asset should contain a visible mesh" % kind)

	for kind in BUILDING_KINDS:
		var view = BuildingViewScript.new()
		root_node.add_child(view)
		view.setup({
			"id": "asset_%s" % kind,
			"team": "enemy",
			"kind": kind,
			"position": Vector3.ZERO,
			"construction_progress": 0.25,
			"health": 300.0,
			"max_health": 300.0,
			"complete": false,
			"display_name": kind.capitalize(),
			"research_id": "",
			"research_remaining": 0.0,
			"research_total": 0.0,
		})
		if view.asset_visual == null:
			failures.append("%s should load its Kenney runtime asset" % kind)
		elif not _has_visible_mesh(view.asset_visual):
			failures.append("%s asset should contain a visible mesh" % kind)

	_test_unit_movement_facing(root_node, failures)
	_test_resource_depletion_visual(root_node, failures)
	_test_asset_variants(root_node, failures)
	_test_environment_assets(root_node, failures)
	_test_source_palette(root_node, failures)
	root_node.queue_free()
	await process_frame

	if failures.is_empty():
		print("ART_ASSET_SMOKE_PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("ART_ASSET_SMOKE_FAIL")
		quit(1)


func _has_visible_mesh(node: Node) -> bool:
	if node is MeshInstance3D and node.visible:
		return true
	for child in node.get_children():
		if _has_visible_mesh(child):
			return true
	return false


func _test_unit_movement_facing(root_node: Node3D, failures: Array[String]) -> void:
	var view = UnitViewScript.new()
	root_node.add_child(view)
	var unit_data := {
		"id": "facing_collector",
		"team": "player",
		"kind": "collector",
		"position": Vector3.ZERO,
		"target_position": Vector3(8.0, 0.0, 0.0),
		"order": "move",
		"health": 100.0,
		"max_health": 100.0,
		"display_name": "Collector",
		"supply_state": "connected",
		"collector_state": "to_source",
		"collector_cargo": 0.0,
		"collector_capacity": 75.0,
	}
	view.setup(unit_data)
	unit_data["position"] = Vector3(1.0, 0.0, 0.0)
	view.sync(unit_data, false, 0.1)
	var forward: Vector3 = -view.global_transform.basis.z
	if forward.dot(Vector3.RIGHT) < 0.75:
		failures.append("moving units should rotate toward their measured travel direction")


func _test_resource_depletion_visual(root_node: Node3D, failures: Array[String]) -> void:
	var view = ResourceViewScript.new()
	root_node.add_child(view)
	var resource := {
		"id": "visual_resource",
		"display_name": "Visual Resource",
		"position": Vector3.ZERO,
		"remaining": 800.0,
		"initial_remaining": 800.0,
		"depleted": false,
		"visibility_state": "visible",
	}
	view.setup(resource)
	var full_count: int = view.visible_cluster_count()
	resource["remaining"] = 100.0
	view.sync(resource, false)
	var low_count: int = view.visible_cluster_count()
	resource["remaining"] = 0.0
	resource["depleted"] = true
	view.sync(resource, false)
	if full_count != 8 or low_count >= full_count or view.visible_cluster_count() != 0:
		failures.append("resource crystals should disappear progressively as a field depletes")


func _test_asset_variants(root_node: Node3D, failures: Array[String]) -> void:
	for kind in ["command_hub", "storage_silo"]:
		var view = BuildingViewScript.new()
		root_node.add_child(view)
		var building_data := {
			"id": "upgraded_%s" % kind,
			"team": "player",
			"kind": kind,
			"position": Vector3.ZERO,
			"construction_progress": 1.0,
			"health": 300.0,
			"max_health": 300.0,
			"complete": true,
			"display_name": kind.capitalize(),
			"research_id": "",
			"research_remaining": 0.0,
			"research_total": 0.0,
			"completed_upgrade_id": "visual_upgrade",
		}
		view.setup(building_data)
		if view.asset_variant != "upgraded" or view.asset_visual == null:
			failures.append("%s should support its upgraded visual variant" % kind)


func _test_environment_assets(root_node: Node3D, failures: Array[String]) -> void:
	for kind in ["resource_cluster_a", "resource_cluster_b", "scenery_rock_a", "scenery_rock_b"]:
		var visual := AssetLibraryScript.attach_asset(root_node, kind, "neutral")
		if visual == null or not _has_visible_mesh(visual):
			failures.append("%s should load as a visible environment asset" % kind)


func _test_source_palette(root_node: Node3D, failures: Array[String]) -> void:
	for expectation in [
		{"kind": "ranger", "minimum_colors": 4},
		{"kind": "refinery", "minimum_colors": 4},
		{"kind": "resource_cluster_a", "minimum_colors": 3},
	]:
		var visual := AssetLibraryScript.attach_asset(root_node, str(expectation["kind"]), "player")
		var colors: Dictionary = {}
		_collect_material_colors(visual, colors)
		if colors.size() < int(expectation["minimum_colors"]):
			failures.append("%s should preserve the original Kenney multi-colour palette" % expectation["kind"])


func _collect_material_colors(node: Node, colors: Dictionary) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh:
			for surface_index in mesh_instance.mesh.get_surface_count():
				var material := mesh_instance.get_surface_override_material(surface_index)
				if material == null:
					material = mesh_instance.mesh.surface_get_material(surface_index)
				if material is BaseMaterial3D:
					colors[(material as BaseMaterial3D).albedo_color.to_html(false)] = true
	for child in node.get_children():
		_collect_material_colors(child, colors)
