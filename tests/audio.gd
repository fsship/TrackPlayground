extends RefCounted

var checks = 0
var failures = 0

func check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + description)
	else:
		failures += 1
		push_error("FAIL: " + description)

func playing(players: Array) -> int:
	return players.filter(func(player): return player.playing).size()

func run(app) -> int:
	var sound = app.sound
	var previous = [sound.master_volume, sound.effects_volume, sound.trains_volume, sound.muted]
	sound.settings_timer.paused = true
	var was_processing: bool = app.is_processing()
	var was_physics: bool = app.is_physics_processing()
	app.set_process(false)
	app.set_physics_process(false)
	sound.master_volume = 0.65
	sound.effects_volume = 0.8
	sound.trains_volume = 0.8
	sound.muted = false
	sound.apply_settings()
	sound.stop_all()
	sound.cooldowns.clear()
	check(sound.samples.size() == 15, "15 个原创音效全部加载，无需导入缓存")
	for name in sound.samples:
		var stream: AudioStreamWAV = sound.samples[name]
		var peak = 0
		for i in range(0, stream.data.size(), 2):
			peak = maxi(peak, absi(stream.data.decode_s16(i)))
		check(stream.get_length() > 0.05 and peak > 1000 and peak < 30000, name + " PCM 有效、非静音且保留峰值余量")
		if name in sound.LOOPS:
			check(stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and stream.loop_end * 2 == stream.data.size(), name + " 循环覆盖全部采样")
	check(AudioServer.get_bus_send(AudioServer.get_bus_index(sound.TRAINS_BUS)) == sound.MASTER_BUS, "列车声音进入独立总音量总线")
	check(sound.effects.size() == 8 and sound.spatial_effects.size() == 8, "瞬时音效使用固定数量的播放器")
	sound.play_effect("place")
	sound.play_effect("place")
	check(playing(sound.effects) == 1, "操作音效可播放，快速重复触发不会叠加")
	sound.set_muted(true)
	sound.play_effect("click")
	check(playing(sound.effects) == 0 and AudioServer.is_bus_mute(AudioServer.get_bus_index(sound.MASTER_BUS)), "静音立即停止现有操作声并阻止后续声音")
	sound.set_muted(false)
	app.make_demo()
	var trains: Array = app.simulation.trains
	for train in trains:
		train.velocity = 3.0
		train.target = 30.0
	app.update_train_visuals()
	sound.sync_trains(trains, app.train_nodes, app.camera.position, false, 1.0)
	await app.get_tree().physics_frame
	check(sound.voices.size() == 2, "两列列车各自拥有独立运行声")
	var diesel: Dictionary = sound.voices[trains[0].id]
	var electric: Dictionary = sound.voices[trains[1].id]
	check(diesel.kind == "diesel" and electric.kind == "electric", "柴油与电力机车使用不同运行音色")
	check(diesel.motor.playing and diesel.rolling.playing, "运行时机车声与轮轨声同时播放")
	var slow_pitch: float = diesel.motor.pitch_scale
	trains[0].velocity = 12.0
	sound.sync_trains(trains, app.train_nodes, app.camera.position, false, 1.0)
	check(diesel.motor.pitch_scale > slow_pitch, "运行声随车速升高音调")
	trains[0].velocity = -3.0
	sound.sync_trains(trains, app.train_nodes, app.camera.position, false, 1.0)
	check(is_equal_approx(diesel.motor.pitch_scale, slow_pitch), "倒车使用绝对速度，不产生负音高")
	trains[0].velocity = 0.0
	trains[1].velocity = 0.0
	sound.sync_trains(trains, app.train_nodes, app.camera.position, false, 1.0)
	check(diesel.motor.playing and not diesel.rolling.playing and not electric.motor.playing, "停车保留柴油怠速，停止轮轨与电力牵引声")
	app.simulation.paused = false
	app.toggle_pause()
	check(not diesel.motor.playing and playing(sound.spatial_effects) == 0, "暂停立即停止列车声音")
	app.command_horn()
	await app.get_tree().physics_frame
	sound.sync_trains(trains, app.train_nodes, app.camera.position, true, 1.0)
	check(playing(sound.spatial_effects) == 1, "暂停时仍可手动鸣笛，帧更新不会截断汽笛")
	app.command_horn()
	check(playing(sound.spatial_effects) == 1, "连续按鸣笛不会堆叠声音")
	sound.stop_trains()
	sound.cooldowns.clear()
	var key = InputEventKey.new()
	key.keycode = KEY_H
	key.pressed = true
	app._input(key)
	await app.get_tree().physics_frame
	check(playing(sound.spatial_effects) == 1, "H 键触发选中列车鸣笛")
	sound.stop_trains()
	sound.cooldowns.clear()
	app.sound_dialog.show()
	app._input(key)
	await app.get_tree().physics_frame
	check(playing(sound.spatial_effects) == 0 and not app.over_canvas(), "声音设置弹窗阻止快捷键与沙盘操作穿透")
	app.sound_dialog.hide()
	var sliders = app.sound_dialog.find_children("*", "HSlider", true, false)
	if sliders.size() == 3:
		sliders[1].value = 25
		check(is_equal_approx(sound.effects_volume, 0.25) and is_equal_approx(sound.master_volume, 0.65) and is_equal_approx(sound.trains_volume, 0.8), "声音设置滑块只改变对应音量通道")
		sliders[1].value = 80
	else:
		check(false, "声音设置包含三个独立滑块")
	sound.set_volume("trains", 0.0)
	app.command_horn()
	check(playing(sound.spatial_effects) == 0, "列车音量为零时不播放鸣笛")
	sound.stop_all()
	sound.play_effect("turnout")
	check(playing(sound.effects) == 1, "关闭列车音量仍可播放操作音")
	sound.set_volume("trains", 0.8)
	trains[0].velocity = 4.0
	trains[0].target = 0.0
	sound.sync_trains(trains, app.train_nodes, app.camera.position, false, 1.0)
	await app.get_tree().physics_frame
	check(sound.voices[trains[0].id].braking and playing(sound.spatial_effects) == 1, "减速时触发一次制动放气声")
	sound.sync_trains(trains, app.train_nodes, app.camera.position, false, 1.0)
	check(playing(sound.spatial_effects) == 1, "持续制动不会每帧重复放气")
	trains[0].fault = true
	sound.sync_trains(trains, app.train_nodes, app.camera.position, false, 1.0)
	check(not sound.voices.has(trains[0].id), "故障或脱轨列车移除持续运行声")
	var saved: Dictionary = app.snapshot()
	app.empty_scene()
	check(sound.voices.is_empty() and playing(sound.spatial_effects) == 0, "新建场景清理运行声与鸣笛")
	check(app.apply_snapshot(saved) and app.simulation.paused and sound.voices.is_empty(), "载入场景暂停且没有旧声音残留")
	app.make_demo()
	trains = app.simulation.trains
	trains[0].cars[0] = "core:steam"
	trains[0].velocity = 5.0
	trains[0].target = 30.0
	sound.sync_trains(trains, app.train_nodes, app.camera.position, false, 1.0)
	var steam: Dictionary = sound.voices[trains[0].id]
	check(steam.kind == "steam" and is_equal_approx(steam.motor.pitch_scale, 5.0 / sound.STEAM_CIRCUMFERENCE), "蒸汽排气节奏按动轮周长与速度变化")
	sound.horn(trains[0], Vector3.ZERO)
	await app.get_tree().physics_frame
	check(sound.spatial_effects.any(func(player): return player.playing and player.stream == sound.samples.whistle), "蒸汽机车使用独立汽笛")
	# Exercise the mixer bound without constructing dozens of visual consists.
	var many: Array = []
	var many_nodes: Dictionary = {}
	for i in 64:
		var train: Dictionary = trains[0].duplicate(true)
		train.id = 100 + i
		many.append(train)
		many_nodes[train.id] = app.train_nodes[trains[0].id]
	sound.sync_trains(many, many_nodes, app.camera.position, false, 1.0)
	check(sound.voices.size() == sound.MAX_TRAINS, "64 编组场景只保留最近的 8 组运行声")
	sound.sync_trains([], {}, Vector3.ZERO, false, 1.0)
	check(sound.voices.is_empty(), "删除所有列车后释放持续声音节点")
	sound.set_volume("master", 0.37)
	sound.set_volume("effects", 0.42)
	sound.set_volume("trains", 0.51)
	sound.set_muted(true)
	sound.settings_timer.stop()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test-results"))
	var settings_path = "res://test-results/audio-settings.cfg"
	sound.save_settings(settings_path)
	sound.master_volume = 1.0
	sound.effects_volume = 1.0
	sound.trains_volume = 1.0
	sound.muted = false
	sound.load_settings(settings_path)
	sound.apply_settings()
	check(is_equal_approx(sound.master_volume, 0.37) and is_equal_approx(sound.effects_volume, 0.42) and is_equal_approx(sound.trains_volume, 0.51) and sound.muted, "音量与静音可持久保存并恢复")
	app.undo()
	check(is_equal_approx(sound.master_volume, 0.37) and sound.muted, "撤销场景编辑不改变声音偏好")
	var invalid = ConfigFile.new()
	invalid.set_value("audio", "master", "bad")
	invalid.set_value("audio", "effects", -3)
	invalid.set_value("audio", "trains", 5)
	invalid.save(settings_path)
	sound.load_settings(settings_path)
	check(is_equal_approx(sound.master_volume, 0.37) and sound.effects_volume == 0.0 and sound.trains_volume == 1.0, "损坏或越界的设置安全回退与限幅")
	sound.settings_timer.stop()
	sound.stop_all()
	sound.master_volume = previous[0]
	sound.effects_volume = previous[1]
	sound.trains_volume = previous[2]
	sound.muted = previous[3]
	sound.apply_settings()
	sound.settings_timer.paused = false
	app.simulation.paused = true
	# Let deferred node deletion and the audio thread release stopped playbacks.
	await app.get_tree().create_timer(0.15).timeout
	app.set_process(was_processing)
	app.set_physics_process(was_physics)
	var report = {"checks":checks, "failures":failures}
	var file = FileAccess.open("res://test-results/audio.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	print("AUDIO_RESULT " + JSON.stringify(report))
	return failures
