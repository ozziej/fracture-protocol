class_name RtsAudioManager
extends Node

## Presentation-only audio layer. Simulation events select sounds, but this
## node never changes match state or issues gameplay commands.

const SFX_PATHS := {
	"laser": "res://audio/sfx/laser.ogg",
	# There is no dedicated missile-launch recording in the supplied pack. Use
	# the heavier impact-plate sound as a restrained launch thunk and reserve the
	# laser for direct beam fire.
	"missile_launch": "res://audio/impactPlate_heavy_000.ogg",
	"hit": "res://audio/sfx/hit_damage.ogg",
	"explosion": "res://audio/sfx/explosion_large.ogg",
	"heavy_impact": "res://audio/impactPlate_heavy_000.ogg",
	"mining": "res://audio/sfx/mining.ogg",
	"repair": "res://audio/sfx/repair.ogg",
	"ui_hover": "res://audio/ui/rollover2.ogg",
	"ui_click": "res://audio/ui/switch1.ogg",
}

const MUSIC_DIRECTORY := "res://audio/music"
const MUSIC_EXTENSIONS := ["ogg", "wav", "mp3"]
const SFX_PLAYER_COUNT := 12

var master_volume := 1.0
var sfx_volume := 0.85
var music_volume := 0.7
var music_track_loaded := false
var sfx_streams: Dictionary = {}
var sfx_players: Array[AudioStreamPlayer] = []
var music_player: AudioStreamPlayer
var sfx_play_counts: Dictionary = {}
var last_played_sfx := ""
var wired_ui_count := 0
var _last_played_msec: Dictionary = {}
var _next_player_index := 0


func _ready() -> void:
	_ensure_bus("Music")
	_ensure_bus("SFX")
	for sound_id in SFX_PATHS:
		var stream := load(str(SFX_PATHS[sound_id])) as AudioStream
		if stream != null:
			sfx_streams[sound_id] = stream
	_load_optional_music()
	_apply_volumes()


func _exit_tree() -> void:
	# Release active Ogg playback before the node leaves the tree. This keeps
	# headless tests and scene reloads from retaining decoded audio resources.
	for player in sfx_players:
		if is_instance_valid(player):
			player.stop()
			player.stream = null
	if music_player != null and is_instance_valid(music_player):
		music_player.stop()
		music_player.stream = null
	sfx_streams.clear()
	sfx_players.clear()
	music_player = null


func set_master_volume(normalized: float) -> void:
	master_volume = clamp(normalized, 0.0, 1.0)
	_apply_bus_volume("Master", master_volume)


func set_sfx_volume(normalized: float) -> void:
	sfx_volume = clamp(normalized, 0.0, 1.0)
	_apply_bus_volume("SFX", sfx_volume)


func set_music_volume(normalized: float) -> void:
	music_volume = clamp(normalized, 0.0, 1.0)
	_apply_bus_volume("Music", music_volume)


func has_sfx(sound_id: String) -> bool:
	return sfx_streams.has(sound_id)


func play_sfx(sound_id: String, volume_db := 0.0, pitch_scale := 1.0, throttle_msec := 0) -> void:
	if not sfx_streams.has(sound_id):
		return
	if throttle_msec > 0:
		var now := Time.get_ticks_msec()
		var last_played := int(_last_played_msec.get(sound_id, -1000000))
		if now - last_played < throttle_msec:
			return
		_last_played_msec[sound_id] = now
	var player: AudioStreamPlayer = null
	for offset in range(sfx_players.size()):
		var candidate_index := (_next_player_index + offset) % sfx_players.size()
		var candidate: AudioStreamPlayer = sfx_players[candidate_index]
		if not candidate.playing:
			player = candidate
			_next_player_index = (candidate_index + 1) % sfx_players.size()
			break
	if player == null:
		if sfx_players.size() >= SFX_PLAYER_COUNT:
			return
		player = _create_sfx_player(sfx_players.size())
	player.stream = sfx_streams[sound_id]
	player.volume_db = volume_db
	player.pitch_scale = pitch_scale
	player.play()
	last_played_sfx = sound_id
	sfx_play_counts[sound_id] = int(sfx_play_counts.get(sound_id, 0)) + 1


func handle_simulation_event(simulation, event_type: String, payload: Dictionary) -> void:
	if not _event_visible_to_player(simulation, event_type, payload):
		return
	match event_type:
		"BeamWeaponFired":
			play_sfx("laser", -9.0, 1.0, 70)
		"ProjectileLaunched":
			play_sfx("missile_launch", -14.0, 0.82, 110)
		"ProjectileImpact":
			play_sfx("heavy_impact", -8.0, 1.0, 100)
		"UnitDamaged":
			play_sfx("hit", -14.0, 1.0, 75)
		"BuildingDamaged":
			play_sfx("heavy_impact", -12.0, 0.96, 110)
		"UnitDestroyed":
			play_sfx("explosion", -8.0, 1.0, 100)
		"BuildingDestroyed":
			play_sfx("explosion", -4.0, 0.88, 140)
		"ResourceCollected":
			play_sfx("mining", -14.0, 1.0, 250)
		"RepairStarted":
			play_sfx("repair", -9.0, 1.0, 180)
		"RepairCompleted":
			play_sfx("repair", -13.0, 1.12, 180)
		"BuildingCompleted", "ProductionCompleted", "TechnologyUnlocked", "UpgradeCompleted":
			play_sfx("ui_click", -10.0, 1.0, 140)
		"TerritoryCaptured", "ForwardStagingActivated":
			play_sfx("ui_click", -7.0, 0.94, 180)
		"ForwardStagingDeactivated":
			play_sfx("hit", -17.0, 0.86, 180)
		"SupplyStateChanged":
			play_sfx("ui_click" if str(payload.get("state", "")) == "connected" else "hit", -13.0, 1.0, 180)
		"ScenarioNetworkStateChanged":
			play_sfx("ui_click" if bool(payload.get("network_online", false)) else "heavy_impact", -8.0, 1.0, 220)
		"OrderRejected":
			play_sfx("hit", -19.0, 0.82, 120)
		"MatchWon":
			play_sfx("ui_click", -3.0, 1.08, 0)
		"MatchLost":
			play_sfx("heavy_impact", -4.0, 0.82, 0)


func wire_ui(root: Node) -> void:
	_wire_ui_node(root)


func _wire_ui_node(node: Node) -> void:
	for child in node.get_children():
		if child is BaseButton:
			child.mouse_entered.connect(_on_ui_hover)
			child.pressed.connect(_on_ui_pressed)
			wired_ui_count += 1
		_wire_ui_node(child)


func _on_ui_hover() -> void:
	play_sfx("ui_hover", -20.0, 1.0, 45)


func _on_ui_pressed() -> void:
	play_sfx("ui_click", -13.0, 1.0, 55)


func _load_optional_music() -> void:
	var directory := DirAccess.open(MUSIC_DIRECTORY)
	if directory == null:
		return
	directory.list_dir_begin()
	var filename := directory.get_next()
	while not filename.is_empty():
		if not directory.current_is_dir() and filename.get_extension().to_lower() in MUSIC_EXTENSIONS:
			var stream := load("%s/%s" % [MUSIC_DIRECTORY, filename]) as AudioStream
			if stream != null:
				_ensure_music_player()
				music_player.stream = stream
				music_track_loaded = true
				music_player.play()
				break
		filename = directory.get_next()
	directory.list_dir_end()


func _create_sfx_player(index: int) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = "SFXPlayer_%02d" % index
	player.bus = "SFX"
	add_child(player)
	sfx_players.append(player)
	return player


func _ensure_music_player() -> void:
	if music_player != null:
		return
	music_player = AudioStreamPlayer.new()
	music_player.name = "MusicPlayer"
	music_player.bus = "Music"
	add_child(music_player)


func _event_visible_to_player(simulation, event_type: String, payload: Dictionary) -> bool:
	if event_type == "MatchStarted" or event_type == "MatchWon" or event_type == "MatchLost":
		return true
	if str(payload.get("team", "")) == "player" or str(payload.get("attacker_team", "")) == "player":
		return true
	var attacker_id := str(payload.get("attacker_id", ""))
	if not attacker_id.is_empty() and simulation.is_entity_visible_to_team("player", attacker_id):
		return true
	var target_id := str(payload.get("target_id", payload.get("unit_id", payload.get("building_id", ""))))
	if not target_id.is_empty() and simulation.is_entity_visible_to_team("player", target_id):
		return true
	var event_position: Vector3 = payload.get("position", payload.get("target_position", payload.get("impact_position", Vector3.ZERO)))
	return simulation.is_position_visible_to_team("player", event_position)


func _ensure_bus(bus_name: String) -> void:
	var bus_index := AudioServer.get_bus_index(bus_name)
	if bus_index < 0:
		AudioServer.add_bus()
		bus_index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus_index, bus_name)
	AudioServer.set_bus_send(bus_index, "Master")


func _apply_volumes() -> void:
	_apply_bus_volume("Master", master_volume)
	_apply_bus_volume("SFX", sfx_volume)
	_apply_bus_volume("Music", music_volume)


func _apply_bus_volume(bus_name: String, normalized: float) -> void:
	var bus_index := AudioServer.get_bus_index(bus_name)
	if bus_index < 0:
		return
	AudioServer.set_bus_volume_db(bus_index, -80.0 if normalized <= 0.001 else linear_to_db(normalized))
