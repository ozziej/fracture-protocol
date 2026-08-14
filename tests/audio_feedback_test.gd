extends SceneTree

const MainScript = preload("res://src/main.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	var main = MainScript.new()
	root.add_child(main)
	await process_frame

	if main.audio_manager == null:
		failures.append("Main should create the presentation audio manager")
	else:
		for sound_id in ["laser", "hit", "explosion", "heavy_impact", "mining", "repair", "ui_hover", "ui_click"]:
			if not main.audio_manager.has_sfx(sound_id):
				failures.append("provided SFX should load: %s" % sound_id)
		if AudioServer.get_bus_index("SFX") < 0 or AudioServer.get_bus_index("Music") < 0:
			failures.append("SFX and Music buses should be available")
		if main.audio_manager.wired_ui_count <= 0:
			failures.append("pause and deployment controls should receive UI audio wiring")

	var pause_menu = main.pause_menu_overlay
	main._show_pause_menu()
	if pause_menu == null or not pause_menu.visible:
		failures.append("pause menu should remain available for audio settings")
	if main.master_volume_slider == null or main.sfx_volume_slider == null or main.music_volume_slider == null:
		failures.append("pause menu should expose Master, Effects, and Music controls")
	else:
		main.master_volume_slider.value = 55.0
		main.sfx_volume_slider.value = 35.0
		main.music_volume_slider.value = 20.0
		if abs(float(main.audio_manager.master_volume) - 0.55) > 0.01 or abs(float(main.audio_manager.sfx_volume) - 0.35) > 0.01 or abs(float(main.audio_manager.music_volume) - 0.20) > 0.01:
			failures.append("pause audio sliders should update the corresponding audio buses")
		if main.sfx_volume_value_label.text != "35%" or main.music_volume_value_label.text != "20%":
			failures.append("pause audio sliders should show their current percentages")

	main._hide_pause_menu()
	main._on_simulation_event("ProjectileLaunched", {
		"attacker_team": "player",
		"launch_position": Vector3.ZERO,
		"impact_position": Vector3(4.0, 0.0, 0.0),
	})
	main._on_simulation_event("UnitDamaged", {
		"team": "enemy",
		"attacker_team": "player",
		"attacker_position": Vector3.ZERO,
		"target_position": Vector3(4.0, 0.0, 0.0),
		"damage": 10.0,
	})
	main._on_simulation_event("UnitDestroyed", {
		"team": "enemy",
		"attacker_team": "player",
		"position": Vector3(4.0, 0.0, 0.0),
	})
	main._on_simulation_event("ResourceCollected", {"team": "player", "amount": 75.0})
	main._on_simulation_event("RepairStarted", {"team": "player", "message": "Repair started."})
	for sound_id in ["laser", "hit", "explosion", "mining", "repair"]:
		if int(main.audio_manager.sfx_play_counts.get(sound_id, 0)) <= 0:
			failures.append("simulation event should play the mapped %s SFX" % sound_id)

	main.queue_free()
	await process_frame
	if failures.is_empty():
		print("AUDIO_FEEDBACK_PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("AUDIO_FEEDBACK_FAIL")
		quit(1)
