extends Node3D
## Shared original samples, bounded voices and independent user preferences.

const SAMPLE_NAMES = ["click", "place", "connect", "remove", "turnout", "couple", "alert", "confirm", "brake", "horn", "whistle", "diesel", "electric", "rolling", "steam"]
const LOOPS = ["diesel", "electric", "rolling", "steam"]
const SETTINGS_PATH = "user://audio.cfg"
const MASTER_BUS = "RailAudio"
const EFFECTS_BUS = "RailEffects"
const TRAINS_BUS = "RailTrains"
const MAX_TRAINS = 8
const MAX_EFFECTS = 8
const MAX_SPATIAL_EFFECTS = 8
const STEAM_CIRCUMFERENCE = TAU * preload("res://scripts/steam_locomotive.gd").DRIVER_RADIUS

var samples: Dictionary = {}
var voices: Dictionary = {}
var effects: Array[AudioStreamPlayer] = []
var spatial_effects: Array[AudioStreamPlayer3D] = []
var cooldowns: Dictionary = {}
var master_volume = 0.65
var effects_volume = 0.8
var trains_volume = 0.8
var muted = false
var settings_timer: Timer

func _ready() -> void:
	for bus_name in [MASTER_BUS, EFFECTS_BUS, TRAINS_BUS]:
		if AudioServer.get_bus_index(bus_name) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)
		AudioServer.set_bus_send(AudioServer.get_bus_index(bus_name), "Master" if bus_name == MASTER_BUS else MASTER_BUS)
	for sample_name in SAMPLE_NAMES:
		# Read PCM directly: the standalone launcher also works without a new
		# editor import when these assets are added to an existing installation.
		var data = FileAccess.get_file_as_bytes("res://assets/audio/" + sample_name + ".wav")
		var stream = AudioStreamWAV.new()
		stream.format = AudioStreamWAV.FORMAT_16_BITS
		stream.mix_rate = 24000
		stream.data = data.slice(44)
		if sample_name in LOOPS:
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			stream.loop_end = stream.data.size() / 2
		samples[sample_name] = stream
	for i in MAX_EFFECTS:
		var player = AudioStreamPlayer.new()
		player.bus = EFFECTS_BUS
		add_child(player)
		effects.append(player)
	for i in MAX_SPATIAL_EFFECTS:
		spatial_effects.append(new_spatial_player())
	settings_timer = Timer.new()
	settings_timer.one_shot = true
	settings_timer.wait_time = 0.3
	settings_timer.timeout.connect(save_settings)
	add_child(settings_timer)
	load_settings()
	apply_settings()

func new_spatial_player() -> AudioStreamPlayer3D:
	var player = AudioStreamPlayer3D.new()
	player.bus = TRAINS_BUS
	player.unit_size = 22.0
	player.max_distance = 180.0
	player.max_db = 0.0
	player.panning_strength = 0.7
	add_child(player)
	return player

func load_settings(path: String = SETTINGS_PATH) -> void:
	var config = ConfigFile.new()
	if config.load(path) != OK:
		return
	master_volume = read_volume(config, "master", master_volume)
	effects_volume = read_volume(config, "effects", effects_volume)
	trains_volume = read_volume(config, "trains", trains_volume)
	var stored_mute = config.get_value("audio", "muted", false)
	muted = stored_mute if stored_mute is bool else false

func read_volume(config: ConfigFile, key: String, fallback: float) -> float:
	var value = config.get_value("audio", key, fallback)
	if (value is float or value is int) and is_finite(float(value)):
		return clampf(float(value), 0.0, 1.0)
	return fallback

func save_settings(path: String = SETTINGS_PATH) -> void:
	var config = ConfigFile.new()
	config.set_value("audio", "master", master_volume)
	config.set_value("audio", "effects", effects_volume)
	config.set_value("audio", "trains", trains_volume)
	config.set_value("audio", "muted", muted)
	if config.save(path) != OK:
		push_warning("无法保存音量设置")

func set_volume(channel: String, value: float) -> void:
	if not is_finite(value):
		return
	match channel:
		"master": master_volume = clampf(value, 0.0, 1.0)
		"effects": effects_volume = clampf(value, 0.0, 1.0)
		"trains": trains_volume = clampf(value, 0.0, 1.0)
	apply_settings()
	settings_timer.start()

func set_muted(value: bool) -> void:
	muted = value
	apply_settings()
	settings_timer.start()

func apply_settings() -> void:
	for pair in [[MASTER_BUS, master_volume], [EFFECTS_BUS, effects_volume], [TRAINS_BUS, trains_volume]]:
		var index = AudioServer.get_bus_index(pair[0])
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(pair[1], 0.0001)))
		AudioServer.set_bus_mute(index, pair[1] <= 0.0 or (pair[0] == MASTER_BUS and muted))
	if muted or master_volume <= 0.0:
		stop_all()
	elif trains_volume <= 0.0:
		stop_trains()
	if effects_volume <= 0.0:
		for player in effects:
			player.stop()

func audible(channel: String) -> bool:
	return not muted and master_volume > 0.0 and (effects_volume > 0.0 if channel == EFFECTS_BUS else trains_volume > 0.0)

func take_cooldown(key: String, seconds: float) -> bool:
	var now = Time.get_ticks_msec()
	if now < cooldowns.get(key, 0):
		return false
	cooldowns[key] = now + int(seconds * 1000.0)
	return true

func play_effect(effect: String) -> void:
	if not audible(EFFECTS_BUS) or not samples.has(effect) or not take_cooldown(effect, 0.06 if effect != "alert" else 0.5):
		return
	for player in effects:
		if not player.playing:
			player.stream = samples[effect]
			player.volume_db = -9.0
			player.play()
			return

func play_at(effect: String, point: Vector3, key: String = "") -> void:
	if not audible(TRAINS_BUS) or not samples.has(effect) or not take_cooldown(key if not key.is_empty() else effect, 1.7 if effect in ["horn", "whistle"] else 0.3):
		return
	for player in spatial_effects:
		if not player.playing:
			player.stream = samples[effect]
			player.position = point
			player.volume_db = -7.0
			player.play()
			return

func engine_kind(cars: Array) -> String:
	# Existing Mod locomotives use the diesel fallback without a schema change.
	if "core:steam" in cars:
		return "steam"
	if "core:diesel" in cars:
		return "diesel"
	return "electric" if "core:electric" in cars else "diesel"

func horn(train: Dictionary, point: Vector3) -> void:
	play_at("whistle" if engine_kind(train.cars) == "steam" else "horn", point, "horn:" + str(train.id))

func sync_trains(trains: Array, nodes: Dictionary, listener: Vector3, paused: bool, dt: float) -> void:
	if not audible(TRAINS_BUS):
		stop_trains()
		return
	if paused:
		for voice in voices.values():
			voice.motor.stop()
			voice.rolling.stop()
		return
	var candidates: Array = []
	for train in trains:
		if train.fault or train.has("derailed_cars") or not nodes.has(train.id) or nodes[train.id].is_empty():
			continue
		var point: Vector3 = nodes[train.id][0].global_position
		candidates.append({"train":train, "point":point, "distance":point.distance_squared_to(listener)})
	candidates.sort_custom(func(a, b): return a.distance < b.distance)
	var active: Dictionary = {}
	for candidate in candidates.slice(0, MAX_TRAINS):
		var train: Dictionary = candidate.train
		var id: int = train.id
		active[id] = true
		var kind = engine_kind(train.cars)
		if voices.has(id) and voices[id].kind != kind:
			remove_voice(id)
		if not voices.has(id):
			var motor = new_spatial_player()
			motor.stream = samples[kind]
			var rolling = new_spatial_player()
			rolling.stream = samples.rolling
			voices[id] = {"motor":motor, "rolling":rolling, "kind":kind, "braking":false}
		var voice: Dictionary = voices[id]
		var speed = absf(train.velocity)
		var motor_gain = 0.13 + minf(speed / 25.0, 1.0) * 0.18
		var motor_pitch = 0.72 + minf(speed / 30.0, 1.0) * 0.8
		if kind == "steam":
			motor_gain = minf(speed / 1.0, 1.0) * 0.4
			motor_pitch = clampf(speed / STEAM_CIRCUMFERENCE, 0.05, 6.0)
		elif kind == "electric":
			motor_gain = minf(speed / 2.0, 1.0) * 0.24
		var mix_gain = 1.0 / sqrt(float(mini(candidates.size(), MAX_TRAINS)))
		update_loop(voice.motor, candidate.point, motor_gain * mix_gain, motor_pitch, dt)
		update_loop(voice.rolling, candidate.point, minf(speed / 12.0, 1.0) * 0.3 * mix_gain, clampf(speed / 8.0, 0.25, 3.0), dt)
		var braking: bool = speed > 0.5 and (train.get("emergency", false) or train.target / 3.6 < speed - 0.5)
		if braking and not voice.braking:
			play_at("brake", candidate.point, "brake:" + str(id))
		voice.braking = braking
	for id in voices.keys():
		if not active.has(id):
			remove_voice(id)

func update_loop(player: AudioStreamPlayer3D, point: Vector3, gain: float, pitch: float, dt: float) -> void:
	player.position = point
	player.pitch_scale = lerpf(player.pitch_scale, pitch, minf(dt * 8.0, 1.0))
	var target_db = linear_to_db(maxf(gain, 0.0001))
	if not player.playing:
		if gain <= 0.001:
			return
		player.volume_db = -60.0
		player.pitch_scale = pitch
		player.play()
	player.volume_db = lerpf(player.volume_db, target_db, minf(dt * 8.0, 1.0))
	if gain <= 0.001 and player.volume_db < -55.0:
		player.stop()

func remove_voice(id: int) -> void:
	for player in [voices[id].motor, voices[id].rolling]:
		player.stop()
		player.queue_free()
	voices.erase(id)

func stop_trains() -> void:
	for voice in voices.values():
		voice.motor.stop()
		voice.rolling.stop()
	for player in spatial_effects:
		player.stop()

func stop_all() -> void:
	stop_trains()
	for player in effects:
		player.stop()

func clear_trains() -> void:
	stop_trains()
	for id in voices.keys():
		remove_voice(id)
	# Train IDs are reused after scene load / undo.
	cooldowns.clear()

func _exit_tree() -> void:
	if settings_timer and not settings_timer.is_stopped():
		save_settings()
