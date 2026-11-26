extends SceneTree
## Optional real mixer + rendered UI smoke test; run without --headless.

var failures = 0
var results: Array = []
var app
var capture: AudioEffectCapture

func _initialize() -> void:
	call_deferred("run")

func measure(name: String, should_sound: bool) -> void:
	await create_timer(0.12).timeout
	capture.clear_buffer()
	await create_timer(0.35).timeout
	var frames = capture.get_buffer(capture.get_frames_available())
	var peak = 0.0
	var energy = 0.0
	for frame in frames:
		peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
		energy += frame.length_squared()
	var rms = sqrt(energy / maxf(2 * frames.size(), 1))
	var valid = not frames.is_empty() and (rms > 0.0001 if should_sound else peak < 0.0001) and peak < 0.99
	results.append({"name":name, "frames":frames.size(), "peak":peak, "rms":rms, "valid":valid})
	if not valid:
		failures += 1
	print("AUDIO_OUTPUT: ", results[-1])
	if should_sound and not frames.is_empty():
		var wav = AudioStreamWAV.new()
		wav.format = AudioStreamWAV.FORMAT_16_BITS
		wav.stereo = true
		wav.mix_rate = int(AudioServer.get_mix_rate())
		var bytes = PackedByteArray()
		bytes.resize(frames.size() * 4)
		for i in frames.size():
			bytes.encode_s16(i * 4, int(clampf(frames[i].x, -1, 1) * 32767))
			bytes.encode_s16(i * 4 + 2, int(clampf(frames[i].y, -1, 1) * 32767))
		wav.data = bytes
		wav.save_to_wav("res://test-results/audio-output-" + name + ".wav")

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test-results"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://screenshots"))
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	app.sound.master_volume = 0.65
	app.sound.effects_volume = 0.8
	app.sound.trains_volume = 0.8
	app.sound.muted = false
	app.sound.apply_settings()
	capture = AudioEffectCapture.new()
	capture.buffer_length = 2.0
	AudioServer.add_bus_effect(0, capture)
	app.sound.play_effect("turnout")
	await measure("turnout", true)
	app.make_demo()
	for train in app.simulation.trains:
		train.velocity = 5.0
		train.target = 18.0
	await measure("running", true)
	app.toggle_pause()
	await measure("paused", false)
	app.command_horn()
	await measure("horn", true)
	app.sound.set_muted(true)
	app.sound.settings_timer.stop()
	await measure("muted", false)
	app.sound.set_muted(false)
	app.sound.settings_timer.stop()
	app.sound.stop_all()
	app.make_demo()
	app.simulation.trains[0].cars[0] = "core:steam"
	app.simulation.trains[0].velocity = 4.0
	app.simulation.trains[0].target = 14.4
	await measure("steam", true)
	app.toggle_pause()
	app.command_horn()
	await measure("whistle", true)
	app.sound.stop_all()
	for dimensions in [Vector2i(1600, 1000), Vector2i(800, 600)]:
		root.size = dimensions
		for i in 12:
			await process_frame
		app.sound_dialog.popup_centered()
		for i in 8:
			await process_frame
		var visible = root.get_visible_rect()
		var rect = Rect2(Vector2(app.sound_dialog.position), Vector2(app.sound_dialog.size))
		var valid = visible.encloses(rect)
		for child in app.top_panel.get_child(0).get_children():
			valid = valid and app.top_panel.get_global_rect().encloses(child.get_global_rect())
		if not valid:
			failures += 1
		print("AUDIO_UI: ", dimensions, " fits=", valid)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://screenshots/audio-%dx%d.png" % [dimensions.x, dimensions.y])
		app.sound_dialog.hide()
	AudioServer.remove_bus_effect(0, AudioServer.get_bus_effect_count(0) - 1)
	app.sound.stop_all()
	await create_timer(0.15).timeout
	var report = FileAccess.open("res://test-results/audio-output.json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"failures":failures, "results":results}, "  "))
	print("AUDIO_OUTPUT_RESULT failures=", failures)
	quit(1 if failures else 0)
