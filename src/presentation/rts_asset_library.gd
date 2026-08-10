class_name RtsAssetLibrary
extends RefCounted

## Presentation-only bridge between simulation kinds and the Kenney-based GLBs.
## Gameplay code never depends on these assets; a missing export falls back to
## the procedural view that owns the selection, health, and construction UI.

const ASSET_PATHS := {
	"collector": "res://art/fracture_protocol_assets/unit_collector.glb",
	"ranger": "res://art/fracture_protocol_assets/unit_ranger.glb",
	"raider": "res://art/fracture_protocol_assets/unit_raider.glb",
	"warden": "res://art/fracture_protocol_assets/unit_warden.glb",
	"bulwark": "res://art/fracture_protocol_assets/unit_bulwark.glb",
	"command_hub": "res://art/fracture_protocol_assets/building_command_hub.glb",
	"refinery": "res://art/fracture_protocol_assets/building_resource_processor.glb",
	"assembly_bay": "res://art/fracture_protocol_assets/building_assembly_bay.glb",
	"tech_centre": "res://art/fracture_protocol_assets/building_tech_centre.glb",
	"storage_silo": "res://art/fracture_protocol_assets/building_storage_silo.glb",
	"relay": "res://art/fracture_protocol_assets/building_forward_relay.glb",
	"resource_cluster_a": "res://art/fracture_protocol_assets/resource_cluster_a.glb",
	"resource_cluster_b": "res://art/fracture_protocol_assets/resource_cluster_b.glb",
	"scenery_rock_a": "res://art/fracture_protocol_assets/scenery_rock_a.glb",
	"scenery_rock_b": "res://art/fracture_protocol_assets/scenery_rock_b.glb",
}

const VARIANT_PATHS := {
	"command_hub:upgraded": "res://art/fracture_protocol_assets/building_command_hub_upgraded.glb",
	"storage_silo:upgraded": "res://art/fracture_protocol_assets/building_storage_silo_upgraded.glb",
}

const DISPLAY_SCALES := {
	"collector": Vector3(1.0, 1.0, 1.0),
	"ranger": Vector3(1.0, 1.0, 1.0),
	"raider": Vector3(1.0, 1.0, 1.0),
	"warden": Vector3(1.0, 1.0, 1.0),
	"bulwark": Vector3(1.0, 1.0, 1.0),
	"command_hub": Vector3(1.0, 1.0, 1.0),
	"refinery": Vector3(1.0, 1.0, 1.0),
	"assembly_bay": Vector3(1.0, 1.0, 1.0),
	"tech_centre": Vector3(1.0, 1.0, 1.0),
	"storage_silo": Vector3(1.0, 1.0, 1.0),
	"relay": Vector3(1.0, 1.0, 1.0),
}

const PLAYER_ACCENT := Color("#2a879a")
const ENEMY_ACCENT := Color("#a84658")
const NEUTRAL_ACCENT := Color("#7f8d95")
const BASE_MATERIAL := Color("#67727a")
const DARK_MATERIAL := Color("#1c2d36")
const ROCK_MATERIAL := Color("#4b5152")
const SKIN_MATERIAL := Color("#8a6655")
const ENERGY_MATERIAL := Color("#f3bd52")

static var _packed_assets: Dictionary = {}
static var _replacement_materials: Dictionary = {}


static func attach_asset(parent: Node3D, kind: String, team: String, variant: String = "") -> Node3D:
	var asset_path := path_for(kind, variant)
	if asset_path.is_empty():
		return null
	var packed: PackedScene = _load_asset(asset_path)
	if packed == null:
		return null
	var visual := packed.instantiate() as Node3D
	if visual == null:
		return null
	visual.name = "KenneyAsset_%s%s" % [kind, "_%s" % variant if not variant.is_empty() else ""]
	visual.scale = DISPLAY_SCALES.get(kind, Vector3.ONE)
	parent.add_child(visual)
	_apply_team_materials(visual, team)
	return visual


static func path_for(kind: String, variant: String = "") -> String:
	var variant_key := "%s:%s" % [kind, variant]
	if not variant.is_empty() and VARIANT_PATHS.has(variant_key):
		return VARIANT_PATHS[variant_key]
	return str(ASSET_PATHS.get(kind, ""))


static func has_variant(kind: String, variant: String) -> bool:
	return VARIANT_PATHS.has("%s:%s" % [kind, variant])


static func scale_for(kind: String) -> Vector3:
	return DISPLAY_SCALES.get(kind, Vector3.ONE)


static func _load_asset(path: String) -> PackedScene:
	if _packed_assets.has(path):
		return _packed_assets[path] as PackedScene
	var packed := load(path) as PackedScene
	if packed != null:
		_packed_assets[path] = packed
	return packed


static func _apply_team_materials(root: Node, team: String) -> void:
	var accent := _team_accent(team)
	for node in root.get_children():
		_apply_team_materials(node, team)
	if not root is MeshInstance3D:
		return
	var mesh_instance := root as MeshInstance3D
	if mesh_instance.mesh == null:
		return
	for surface_index in mesh_instance.mesh.get_surface_count():
		var source_material := mesh_instance.mesh.surface_get_material(surface_index)
		if source_material == null:
			continue
		var material_name := str(source_material.resource_name).to_lower()
		var replacement_color := Color.TRANSPARENT
		if material_name.contains("fp_accent"):
			replacement_color = accent
		elif material_name.contains("fp_base"):
			replacement_color = BASE_MATERIAL
		elif material_name.contains("fp_dark"):
			replacement_color = DARK_MATERIAL
		elif material_name.contains("fp_rock"):
			replacement_color = ROCK_MATERIAL
		elif material_name.contains("fp_skin"):
			replacement_color = SKIN_MATERIAL
		elif material_name.contains("fp_energy"):
			replacement_color = ENERGY_MATERIAL
		if replacement_color == Color.TRANSPARENT:
			continue
		var replacement := _replacement_material(source_material, material_name, replacement_color)
		mesh_instance.set_surface_override_material(surface_index, replacement)


static func _replacement_material(source_material: Material, material_name: String, replacement_color: Color) -> BaseMaterial3D:
	var cache_key := "%s:%s" % [material_name, replacement_color.to_html(true)]
	if _replacement_materials.has(cache_key):
		return _replacement_materials[cache_key] as BaseMaterial3D
	var replacement := source_material.duplicate() as BaseMaterial3D
	if replacement == null:
		replacement = StandardMaterial3D.new()
	replacement.albedo_color = replacement_color
	if material_name.contains("fp_energy"):
		replacement.emission_enabled = true
		replacement.emission = replacement_color
		replacement.emission_energy_multiplier = 0.55
	_replacement_materials[cache_key] = replacement
	return replacement


static func _team_accent(team: String) -> Color:
	if team == "player":
		return PLAYER_ACCENT
	if team == "enemy":
		return ENEMY_ACCENT
	return NEUTRAL_ACCENT
