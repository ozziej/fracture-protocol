extends SceneTree

const SimulationScript = preload("res://src/rts_simulation.gd")
const WorldSynchronizerScript = preload("res://src/presentation/rts_world_view_synchronizer.gd")


func _initialize() -> void:
	await process_frame
	var simulation: Node = SimulationScript.new()
	root.add_child(simulation)
	simulation.start_match("relay_crossroads")
	var unit_types: Array[String] = ["ranger", "warden", "raider", "bulwark", "collector"]
	for index in range(100):
		var team := "player" if index % 2 == 0 else "enemy"
		var kind: String = unit_types[index % unit_types.size()]
		var base_x: float = -52.0 if team == "player" else 5.0
		var position := Vector3(base_x + float(index % 10) * 4.0, 0.0, -30.0 + float(index / 10) * 6.0)
		var entity_id: String = simulation._add_unit(team, kind, position)
		simulation.units[entity_id]["target_position"] = position + Vector3(2.0 if team == "player" else -2.0, 0.0, 1.0)
		simulation.units[entity_id]["order"] = "move"

	var world := Node3D.new()
	root.add_child(world)
	var unit_views: Dictionary = {}
	var building_views: Dictionary = {}
	var control_views: Dictionary = {}
	var resource_views: Dictionary = {}
	var snapshot: Dictionary = simulation.get_state()
	WorldSynchronizerScript.sync(world, snapshot, [], unit_views, building_views, control_views, resource_views, "", [], null, 1.0 / 60.0)
	await process_frame
	if unit_views.size() < 100:
		push_error("The visual benchmark should instantiate all 100 active unit views")
		quit(1)
		return

	# Warm up asset-backed node creation and the first presentation update before
	# measuring repeated frame synchronization.
	for _index in range(30):
		WorldSynchronizerScript.sync(world, simulation.get_state(), [], unit_views, building_views, control_views, resource_views, "", [], null, 1.0 / 60.0)
	var start_usec := Time.get_ticks_usec()
	for _index in range(120):
		WorldSynchronizerScript.sync(world, simulation.get_state(), [], unit_views, building_views, control_views, resource_views, "", [], null, 1.0 / 60.0)
	var elapsed_usec: int = Time.get_ticks_usec() - start_usec
	var average_usec: float = float(elapsed_usec) / 120.0
	print("VISUAL_PERFORMANCE_SMOKE_PASS units=%d views=%d average_sync_us=%.1f" % [simulation.units.size(), unit_views.size(), average_usec])
	if average_usec > 20000.0:
		push_error("100 active unit views should stay below the 20ms average presentation-sync budget")
		quit(1)
	else:
		quit(0)
