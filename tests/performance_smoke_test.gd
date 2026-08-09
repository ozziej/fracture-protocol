extends SceneTree

const SimulationScript = preload("res://src/rts_simulation.gd")


func _initialize() -> void:
	var simulation = SimulationScript.new()
	root.add_child(simulation)
	simulation.start_match("relay_crossroads")
	var unit_types: Array[String] = ["ranger", "warden", "raider", "bulwark"]
	for index in range(100):
		var team := "player" if index % 2 == 0 else "enemy"
		var kind: String = unit_types[index % unit_types.size()]
		var base_x: float = -52.0 if team == "player" else 5.0
		var position := Vector3(base_x + float(index % 10) * 4.0, 0.0, -30.0 + float(index / 10) * 6.0)
		var entity_id: String = simulation._add_unit(team, kind, position)
		simulation.units[entity_id]["target_position"] = position + Vector3(2.0 if team == "player" else -2.0, 0.0, 1.0)
		simulation.units[entity_id]["order"] = "move"

	var start_usec := Time.get_ticks_usec()
	for _index in range(300):
		simulation._ai_timer = 0.0
		simulation.step_fixed()
	var elapsed_usec: int = Time.get_ticks_usec() - start_usec
	var average_usec: float = float(elapsed_usec) / 300.0
	print("PERFORMANCE_SMOKE_PASS units=%d ticks=300 average_tick_us=%.1f" % [simulation.units.size(), average_usec])
	if average_usec > 8000.0:
		push_error("100 active combat units should stay below the 8ms average simulation budget")
		quit(1)
	else:
		quit(0)
