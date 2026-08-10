class_name RtsCombatEffects
extends RefCounted

## Presentation-only listener for simulation combat events. It never changes
## match state; the deterministic simulation has already resolved the outcome.
var _sequence := 0


func present(parent: Node3D, simulation, event_type: String, payload: Dictionary) -> void:
	if not _event_visible_to_player(simulation, event_type, payload):
		return
	match event_type:
		"ProjectileLaunched":
			spawn_missile_arc(parent, payload)
		"ProjectileImpact":
			spawn_impact(parent, payload.get("position", Vector3.ZERO) + Vector3.UP * 0.55, Color("#ff9f43"), "")
		"UnitDamaged", "BuildingDamaged":
			spawn_damage_feedback(parent, simulation, payload, event_type == "BuildingDamaged")
		"UnitDestroyed", "BuildingDestroyed":
			spawn_destruction_feedback(parent, payload)


func spawn_missile_arc(parent: Node3D, payload: Dictionary) -> void:
	var start: Vector3 = payload.get("launch_position", Vector3.ZERO)
	var finish: Vector3 = payload.get("impact_position", start)
	var effect := Node3D.new()
	effect.name = _next_name("MissileArc")
	const SEGMENT_COUNT := 8
	for segment_index in range(SEGMENT_COUNT):
		var t0: float = float(segment_index) / float(SEGMENT_COUNT)
		var t1: float = float(segment_index + 1) / float(SEGMENT_COUNT)
		var height: float = max(2.0, start.distance_to(finish) * 0.12)
		var point_a: Vector3 = start.lerp(finish, t0) + Vector3.UP * (sin(t0 * PI) * height)
		var point_b: Vector3 = start.lerp(finish, t1) + Vector3.UP * (sin(t1 * PI) * height)
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.16, 0.16, max(0.2, point_a.distance_to(point_b)))
		var segment := MeshInstance3D.new()
		segment.mesh = mesh
		segment.material_override = _material(Color("#ff9f43"), 0.15, 0.45)
		segment.position = (point_a + point_b) * 0.5
		effect.add_child(segment)
		segment.look_at_from_position(segment.position, point_b, Vector3.UP)
	parent.add_child(effect)
	var tween := effect.create_tween()
	tween.tween_interval(float(payload.get("travel_time", 0.5)))
	tween.tween_callback(Callable(effect, "queue_free"))


func spawn_damage_feedback(parent: Node3D, simulation, payload: Dictionary, building_hit: bool) -> void:
	var attacker_position: Vector3 = payload.get("attacker_position", payload.get("target_position", Vector3.ZERO))
	var target_position: Vector3 = payload.get("target_position", Vector3.ZERO)
	var attacker_kind := str(payload.get("attacker_kind", ""))
	var effect_color := Color("#ff9f43") if attacker_kind == "bulwark" else Color("#c7dcff") if attacker_kind == "warden" else Color("#ffb347") if building_hit else Color("#ffd36a")
	var attacker_id := str(payload.get("attacker_id", ""))
	var is_missile: bool = simulation.units.has(attacker_id) and str(simulation.units[attacker_id].get("kind", "")) == "bulwark"
	var attacker_visible: bool = simulation.is_entity_visible_to_team("player", attacker_id) if not attacker_id.is_empty() else simulation.is_position_visible_to_team("player", attacker_position)
	if not is_missile and attacker_visible:
		spawn_tracer(parent, attacker_position + Vector3.UP * 0.75, target_position + Vector3.UP * (1.0 if building_hit else 0.55), effect_color)
	var damage: int = int(round(float(payload.get("damage", 0.0))))
	spawn_impact(parent, target_position + Vector3.UP * (1.0 if building_hit else 0.55), effect_color, "-%d" % damage)


func spawn_tracer(parent: Node3D, start: Vector3, finish: Vector3, color: Color) -> void:
	var effect := Node3D.new()
	effect.name = _next_name("CombatEffect")
	var beam_mesh := BoxMesh.new()
	beam_mesh.size = Vector3(0.075, 0.075, max(0.25, start.distance_to(finish)))
	var beam := MeshInstance3D.new()
	beam.mesh = beam_mesh
	beam.material_override = _material(Color(color.r, color.g, color.b, 0.9), 0.22, 0.35)
	effect.add_child(beam)
	effect.position = (start + finish) * 0.5
	parent.add_child(effect)
	effect.look_at(finish, Vector3.UP)
	var tween := effect.create_tween()
	tween.tween_interval(0.1)
	tween.tween_callback(Callable(effect, "queue_free"))


func spawn_impact(parent: Node3D, position: Vector3, color: Color, label_text: String) -> void:
	var effect := Node3D.new()
	effect.name = _next_name("CombatEffect")
	effect.position = position
	var flash_mesh := SphereMesh.new()
	flash_mesh.radius = 0.25
	flash_mesh.height = 0.5
	flash_mesh.radial_segments = 12
	flash_mesh.rings = 6
	var flash := MeshInstance3D.new()
	flash.mesh = flash_mesh
	flash.material_override = _material(Color(color.r, color.g, color.b, 0.88), 0.18, 0.15)
	effect.add_child(flash)
	var label := _feedback_label(label_text, color, 30, 7)
	label.position.y = 0.35
	effect.add_child(label)
	parent.add_child(effect)
	var tween := effect.create_tween()
	tween.set_parallel()
	tween.tween_property(effect, "scale", Vector3.ONE * 1.7, 0.28)
	tween.tween_property(effect, "position", effect.position + Vector3.UP * 0.8, 0.35)
	tween.set_parallel(false)
	tween.tween_callback(Callable(effect, "queue_free"))


func spawn_destruction_feedback(parent: Node3D, payload: Dictionary) -> void:
	var effect := Node3D.new()
	effect.name = _next_name("CombatEffect")
	effect.position = payload.get("position", Vector3.ZERO) + Vector3.UP * 0.65
	var burst_mesh := SphereMesh.new()
	burst_mesh.radius = 0.45
	burst_mesh.height = 0.9
	burst_mesh.radial_segments = 14
	burst_mesh.rings = 7
	var burst := MeshInstance3D.new()
	burst.mesh = burst_mesh
	burst.material_override = _material(Color(1.0, 0.35, 0.12, 0.9), 0.18, 0.1)
	effect.add_child(burst)
	var label := _feedback_label("DESTROYED", Color("#ff8066"), 30, 8)
	label.position.y = 0.7
	effect.add_child(label)
	parent.add_child(effect)
	var tween := effect.create_tween()
	tween.set_parallel()
	tween.tween_property(effect, "scale", Vector3.ONE * 2.4, 0.42)
	tween.tween_property(effect, "position", effect.position + Vector3.UP * 1.4, 0.48)
	tween.set_parallel(false)
	tween.tween_callback(Callable(effect, "queue_free"))


func _next_name(prefix: String) -> String:
	_sequence += 1
	return "%s_%03d" % [prefix, _sequence]


func _event_visible_to_player(simulation, event_type: String, payload: Dictionary) -> bool:
	if str(payload.get("attacker_team", "")) == "player" or str(payload.get("team", "")) == "player":
		return true
	var attacker_id := str(payload.get("attacker_id", ""))
	if event_type == "ProjectileLaunched":
		return simulation.is_position_visible_to_team("player", payload.get("launch_position", Vector3.ZERO))
	if not attacker_id.is_empty() and simulation.is_entity_visible_to_team("player", attacker_id):
		return true
	var target_id := str(payload.get("target_id", payload.get("unit_id", payload.get("building_id", ""))))
	if not target_id.is_empty() and simulation.is_entity_visible_to_team("player", target_id):
		return true
	var event_position: Vector3 = payload.get("position", payload.get("target_position", Vector3.ZERO))
	return simulation.is_position_visible_to_team("player", event_position)


func _feedback_label(text: String, color: Color, font_size: int, outline_size: int) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = font_size
	label.modulate = color
	label.outline_size = outline_size
	label.outline_modulate = Color(0.01, 0.02, 0.04, 0.9)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	return label


func _material(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	if color.a < 0.99:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = roughness
	material.metallic = metallic
	return material
