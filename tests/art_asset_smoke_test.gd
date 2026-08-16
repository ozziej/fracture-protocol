extends SceneTree

const UnitViewScript = preload("res://src/rts_unit_view.gd")
const BuildingViewScript = preload("res://src/rts_building_view.gd")
const ResourceViewScript = preload("res://src/presentation/rts_resource_view.gd")
const AssetLibraryScript = preload("res://src/presentation/rts_asset_library.gd")
const WorldBuilderScript = preload("res://src/presentation/rts_world_builder.gd")
const TerrainDecoratorScript = preload("res://src/presentation/rts_terrain_decorator.gd")
const SimulationScript = preload("res://src/rts_simulation.gd")

const UNIT_KINDS := ["collector", "ranger", "raider", "warden", "bulwark", "command_carrier"]
const BUILDING_KINDS := [
	"command_hub", "refinery", "assembly_bay", "tech_centre", "storage_silo", "relay",
	"forward_base", "field_repair_station", "sensor_mast", "bastion_turret", "fire_support_battery",
]
const TERRAIN_KINDS := [
	"terrain_ramp", "terrain_ramp_large", "terrain_ramp_large_detailed",
	"terrain_road_corner", "terrain_road_cross", "terrain_road_end",
	"terrain_road_split", "terrain_road_straight", "terrain_side",
	"terrain_side_cliff", "terrain_side_corner", "terrain_side_corner_inner",
	"terrain_side_end",
]
const NATURE_KINDS := [
	"vegetation_cactus_short", "vegetation_cactus_tall", "vegetation_bush",
	"vegetation_bush_small", "vegetation_bush_large", "vegetation_grass",
	"vegetation_grass_leafy", "vegetation_flat_tall", "vegetation_flower_yellow",
	"vegetation_flower_purple", "vegetation_tree", "vegetation_tree_cone",
	"vegetation_tree_fall", "vegetation_tree_palm", "vegetation_tree_tall",
]


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
			"repair_radius": 7.5 if kind == "command_hub" or kind == "assembly_bay" else 0.0,
		})
		if view.asset_visual == null:
			failures.append("%s should load its Kenney runtime asset" % kind)
		elif not _has_visible_mesh(view.asset_visual):
			failures.append("%s asset should contain a visible mesh" % kind)

	_test_unit_movement_facing(root_node, failures)
	_test_command_carrier_alignment(root_node, failures)
	_test_resource_depletion_visual(root_node, failures)
	_test_asset_variants(root_node, failures)
	_test_environment_assets(root_node, failures)
	_test_source_palette(root_node, failures)
	_test_status_billboards(root_node, failures)
	_test_obstacle_set_pieces(root_node, failures)
	_test_authored_terrain_pass(root_node, failures)
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


func _test_command_carrier_alignment(root_node: Node3D, failures: Array[String]) -> void:
	var view = UnitViewScript.new()
	root_node.add_child(view)
	view.setup({
		"id": "aligned_carrier", "team": "player", "kind": "command_carrier",
		"position": Vector3.ZERO, "target_position": Vector3.ZERO, "order": "idle",
		"health": 500.0, "max_health": 500.0, "display_name": "Mobile Command Unit",
		"supply_state": "connected",
	})
	var bounds: AABB = view._node_bounds(view.asset_visual, Transform3D.IDENTITY, AABB())
	if absf(bounds.get_center().x) > 0.1 or absf(bounds.get_center().z) > 0.1:
		failures.append("The monorail consist should be centred on its simulation and interaction origin")
	if view.selection_disc.scale.z < 3.0:
		failures.append("The Mobile Command Unit selection marker should cover the rendered train footprint")


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
	for kind in [
		"resource_cluster_a", "resource_cluster_b", "scenery_rock_a", "scenery_rock_b",
	"terrain_rock_a", "terrain_rock_b", "industrial_platform", "industrial_train",
		"industrial_tower", "industrial_support", "monorail_train_front", "monorail_train_flat",
		"monorail_train_passenger", "monorail_train_cargo", "monorail_train_box", "monorail_train_end",
		"terrain_mesa_small_a", "terrain_mesa_small_b",
		"terrain_ground",
	]:
		var visual := AssetLibraryScript.attach_asset(root_node, kind, "neutral")
		if visual == null or not _has_visible_mesh(visual):
			failures.append("%s should load as a visible environment asset" % kind)
	for kind in TERRAIN_KINDS + NATURE_KINDS:
		var visual := AssetLibraryScript.attach_asset(root_node, kind, "neutral")
		if visual == null or not _has_visible_mesh(visual):
			failures.append("%s should load as a visible environment asset" % kind)


func _test_status_billboards(root_node: Node3D, failures: Array[String]) -> void:
	var camera := Camera3D.new()
	camera.position = Vector3(8.0, 12.0, 10.0)
	camera.current = true
	root_node.add_child(camera)
	var unit = UnitViewScript.new()
	root_node.add_child(unit)
	var unit_data := {
		"id": "billboard_unit", "team": "player", "kind": "collector",
		"position": Vector3(2.0, 0.0, 1.0), "target_position": Vector3(8.0, 0.0, 1.0),
		"order": "move", "health": 100.0, "max_health": 100.0,
		"display_name": "Collector", "supply_state": "connected",
		"collector_state": "to_source", "collector_cargo": 30.0, "collector_capacity": 75.0,
	}
	unit.setup(unit_data)
	unit.apply_terrain_height(0.5)
	if absf(unit.global_position.y - 0.5) > 0.001:
		failures.append("unit presentation should raise onto an authored walkable terrain height")
	var billboard_basis: Basis = unit.status_billboard.global_transform.basis
	unit.rotation.y += 1.4
	unit.sync(unit_data, false, 0.1)
	if not unit.status_billboard.top_level or unit.health_back.get_parent() != unit.status_billboard or unit.cargo_back.get_parent() != unit.status_billboard:
		failures.append("unit health and cargo bars should live in a top-level camera-facing status root")
	elif not unit.status_billboard.global_transform.basis.is_equal_approx(billboard_basis):
		failures.append("unit status bars should not inherit chassis rotation")
	elif not unit.status_billboard.global_transform.basis.is_equal_approx(camera.global_transform.basis.orthonormalized()):
		failures.append("status UI should copy the camera basis so labels are not mirrored")
	var unit_back_mesh := unit.health_back.mesh as BoxMesh
	var unit_front_mesh := unit.health_front.mesh as BoxMesh
	if unit_back_mesh == null or unit_front_mesh == null or unit_back_mesh.size.y <= unit_front_mesh.size.y or absf(unit.health_front.position.x) > 0.001:
		failures.append("a full unit health bar should be centred inside a visible dark frame")

	var building = BuildingViewScript.new()
	root_node.add_child(building)
	building.setup({
		"id": "billboard_building", "team": "player", "kind": "refinery",
		"position": Vector3(-2.0, 0.0, 1.0), "construction_progress": 1.0,
		"health": 300.0, "max_health": 300.0, "complete": true,
		"display_name": "Resource Processor", "research_id": "",
		"research_remaining": 0.0, "research_total": 0.0,
	})
	if not building.status_billboard.top_level or building.health_back.get_parent() != building.status_billboard:
		failures.append("building health bars should live in a top-level camera-facing status root")
	var building_back_mesh := building.health_back.mesh as BoxMesh
	var building_front_mesh := building.health_front.mesh as BoxMesh
	if building_back_mesh == null or building_front_mesh == null or building_back_mesh.size.y <= building_front_mesh.size.y or absf(building.health_front.position.x) > 0.001:
		failures.append("a full building health bar should be centred inside a visible dark frame")


func _test_obstacle_set_pieces(root_node: Node3D, failures: Array[String]) -> void:
	var before := root_node.get_child_count()
	WorldBuilderScript.create_obstacle(root_node, Vector3.ZERO, Vector3(12.0, 1.4, 3.0), "north_block")
	var obstacle := root_node.get_child(before) as Node3D
	if obstacle == null or not obstacle.has_meta("fog_sensitive_scenery") or not _has_visible_mesh(obstacle):
		failures.append("navigation obstacles should render as fog-aware Kenney set-piece clusters")
	elif _contains_box_mesh(obstacle):
		failures.append("navigation obstacles should not expose legacy procedural grey blocks")
	elif not _contains_collision_shape(obstacle):
		failures.append("navigation set pieces should expose a collision shape")
	var scenery := WorldBuilderScript.create_scenery(root_node, "scenery_rock_a", Vector3(8.0, 0.0, 8.0), Vector3.ONE, 0.0, true, Vector3(3.0, 2.0, 3.0))
	if not _contains_collision_shape(scenery):
		failures.append("blocking background rocks should expose a collision shape")


func _test_authored_terrain_pass(root_node: Node3D, failures: Array[String]) -> void:
	var simulation = SimulationScript.new()
	root_node.add_child(simulation)
	simulation.start_match("relay_divide")
	var world := Node3D.new()
	root_node.add_child(world)
	WorldBuilderScript.build_world_shell(world, simulation)
	var used_assets: Dictionary = {}
	var terrain_scales: Array[Vector3] = []
	var fog_sensitive_count := _collect_terrain_assets(world, used_assets, terrain_scales)
	if fog_sensitive_count < 40:
		failures.append("Relay Divide should build a substantial fog-aware terrain and vegetation dressing")
	if _count_named_children(world, "BoundaryOutcrop_") != 8:
		failures.append("Relay Divide should use eight sparse boundary outcrop clusters instead of mesa geometry")
	if _contains_named_node(world, "TerrainFeature_"):
		failures.append("terrain should not scatter isolated asset-showcase platforms across the battlefield")
	if used_assets.has("terrain_mesa_small_b") or used_assets.has("terrain_ramp"):
		failures.append("authored terrain should not use mesa or ramp geometry")
	if not used_assets.has("terrain_rock_a") or not used_assets.has("terrain_rock_b"):
		failures.append("authored terrain should use both rocky outcrop variants")
	var ground := world.get_node_or_null("TerrainGround")
	if ground == null or not _has_visible_mesh(ground) or _contains_box_mesh(ground):
		failures.append("map ground should use the authored terrain tile instead of a procedural BoxMesh")
	if _count_named_children(world, "Road_terrain_road_straight") < 1:
		failures.append("authored roads should use the Kenney straight road GLB")
	if _count_named_children(world, "Road_terrain_road_cross") < 1:
		failures.append("authored crossings should use the Kenney cross road GLB")
	if _count_named_children(world, "Road_terrain_road_end") < 2:
		failures.append("authored straight roads should use Kenney road-end caps")
	var terrain: Dictionary = simulation.get_level_terrain()
	var mesa_height := WorldBuilderScript.terrain_height_at(terrain, Vector3(-64.0, 0.0, 38.0))
	var outside_height := WorldBuilderScript.terrain_height_at(terrain, Vector3(-64.0, 0.0, 30.0))
	if absf(mesa_height) > 0.001 or absf(outside_height) > 0.001:
		failures.append("replaced mesa area should remain at ground height")
	var walkable_mesa := world.get_node_or_null("WalkableMesa_west_mesa_platform")
	if walkable_mesa != null:
		failures.append("authored level should not instantiate a walkable mesa")
	var boundary_outcrop := world.get_node_or_null("BoundaryOutcrop_00")
	if boundary_outcrop == null or not _contains_collision_shape(boundary_outcrop):
		failures.append("boundary outcrops should block movement at their authored footprint")
	for terrain_scale in terrain_scales:
		var smaller_horizontal := minf(absf(terrain_scale.x), absf(terrain_scale.z))
		var larger_horizontal := maxf(absf(terrain_scale.x), absf(terrain_scale.z))
		if smaller_horizontal > 0.001 and larger_horizontal / smaller_horizontal > 2.05:
			failures.append("terrain modules must be tiled at near-uniform scale instead of stretched into long slabs")
			break
	world.queue_free()
	simulation.queue_free()


func _collect_terrain_assets(node: Node, used_assets: Dictionary, terrain_scales: Array[Vector3]) -> int:
	var fog_sensitive_count := 1 if node.has_meta("fog_sensitive_scenery") else 0
	if node.has_meta("terrain_asset"):
		used_assets[str(node.get_meta("terrain_asset"))] = true
	if node.has_meta("terrain_scale") and str(node.get_meta("terrain_asset", "")).begins_with("terrain_"):
		terrain_scales.append(node.get_meta("terrain_scale"))
	for child in node.get_children():
		fog_sensitive_count += _collect_terrain_assets(child, used_assets, terrain_scales)
	return fog_sensitive_count


func _count_named_children(node: Node, prefix: String) -> int:
	var count := 1 if node.name.begins_with(prefix) else 0
	for child in node.get_children():
		count += _count_named_children(child, prefix)
	return count


func _contains_named_node(node: Node, prefix: String) -> bool:
	if node.name.begins_with(prefix):
		return true
	for child in node.get_children():
		if _contains_named_node(child, prefix):
			return true
	return false


func _contains_box_mesh(node: Node) -> bool:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh is BoxMesh:
		return true
	for child in node.get_children():
		if _contains_box_mesh(child):
			return true
	return false


func _contains_collision_shape(node: Node) -> bool:
	if node is CollisionShape3D and (node as CollisionShape3D).shape != null:
		return true
	for child in node.get_children():
		if _contains_collision_shape(child):
			return true
	return false


func _all_surfaces_two_sided(node: Node) -> bool:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh:
		var mesh_instance := node as MeshInstance3D
		for index in mesh_instance.mesh.get_surface_count():
			var surface_material := mesh_instance.get_surface_override_material(index)
			if surface_material is BaseMaterial3D and (surface_material as BaseMaterial3D).cull_mode != BaseMaterial3D.CULL_DISABLED:
				return false
	for child in node.get_children():
		if not _all_surfaces_two_sided(child):
			return false
	return true


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
