class_name RtsFogOfWarView
extends Node3D

## Renders the simulation-owned visibility grid as two lightweight translucent
## surfaces. Entity filtering remains the authority for what can be selected or
## targeted; this node only communicates the explored/hidden map state.
var fog_mesh: ImmediateMesh
var fog_surface: MeshInstance3D
var hidden_material: StandardMaterial3D
var explored_material: StandardMaterial3D
var map_bounds := Vector2(60.0, 40.0)
var tile_size := 8.0


func configure(bounds: Vector2, next_tile_size: float) -> void:
	map_bounds = bounds
	tile_size = max(2.0, next_tile_size)
	if fog_surface != null and is_instance_valid(fog_surface):
		return
	fog_mesh = ImmediateMesh.new()
	fog_surface = MeshInstance3D.new()
	fog_surface.name = "FogOverlay"
	fog_surface.mesh = fog_mesh
	fog_surface.position.y = 0.08
	add_child(fog_surface)
	hidden_material = _fog_material(Color(0.008, 0.009, 0.01, 0.91))
	explored_material = _fog_material(Color(0.055, 0.06, 0.06, 0.48))


func sync(visibility: Dictionary) -> void:
	if fog_mesh == null:
		return
	fog_mesh.clear_surfaces()
	var explored: PackedVector3Array = visibility.get("explored_cells", PackedVector3Array())
	var hidden: PackedVector3Array = visibility.get("hidden_cells", PackedVector3Array())
	if not explored.is_empty():
		fog_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, explored_material)
		for center in explored:
			_add_cell(center)
		fog_mesh.surface_end()
	if not hidden.is_empty():
		fog_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, hidden_material)
		for center in hidden:
			_add_cell(center)
		fog_mesh.surface_end()


func _add_cell(center: Vector3) -> void:
	var half_size := tile_size * 0.5
	var y := 0.0
	var north_west := Vector3(center.x - half_size, y, center.z - half_size)
	var north_east := Vector3(center.x + half_size, y, center.z - half_size)
	var south_east := Vector3(center.x + half_size, y, center.z + half_size)
	var south_west := Vector3(center.x - half_size, y, center.z + half_size)
	fog_mesh.surface_add_vertex(north_west)
	fog_mesh.surface_add_vertex(north_east)
	fog_mesh.surface_add_vertex(south_east)
	fog_mesh.surface_add_vertex(north_west)
	fog_mesh.surface_add_vertex(south_east)
	fog_mesh.surface_add_vertex(south_west)


func _fog_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return material
