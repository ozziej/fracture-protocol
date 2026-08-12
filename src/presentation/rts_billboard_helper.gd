class_name RtsBillboardHelper
extends RefCounted

## Keeps world-space status UI parallel to the active camera plane. Copying the
## camera basis avoids the mirrored/back-facing result produced by look_at().

static func sync_to_camera(node: Node3D, world_position: Vector3, viewport: Viewport) -> void:
	if node == null or not node.is_inside_tree():
		return
	var next_transform := node.global_transform
	next_transform.origin = world_position
	var camera := viewport.get_camera_3d()
	if camera:
		next_transform.basis = camera.global_transform.basis.orthonormalized()
	node.global_transform = next_transform
