extends SceneTree

var failures = 0

func _initialize() -> void:
	call_deferred("run")

func settle() -> void:
	for i in 12:
		await process_frame

func run() -> void:
	var app = load("res://main.tscn").instantiate()
	root.add_child(app)
	app.simulation.paused = true
	await settle()
	var results = []
	for dimensions in [Vector2i(1600,1000), Vector2i(1600,700), Vector2i(1280,1024), Vector2i(900,1000), Vector2i(800,600)]:
		root.size = dimensions
		await settle()
		var visible = root.get_visible_rect()
		var ratio = visible.size.x / visible.size.y
		var actual_ratio = float(root.size.x) / root.size.y
		var valid = absf(ratio - actual_ratio) < 0.005
		for panel in [app.top_panel, app.bottom_panel, app.left_panel, app.right_panel]:
			valid = valid and visible.encloses(panel.get_global_rect())
			valid = valid and panel.get_global_rect().encloses(panel.get_child(0).get_global_rect())
		valid = valid and app.left_panel.get_global_rect().end.x < app.right_panel.position.x
		valid = valid and app.top_panel.get_global_rect().end.y < app.left_panel.position.y
		valid = valid and app.left_panel.get_global_rect().end.y < app.bottom_panel.position.y
		for control in app.top_panel.get_child(0).get_children():
			valid = valid and app.top_panel.get_global_rect().encloses(control.get_global_rect())
		app.show_new_scene()
		await settle()
		var dialog_rect = Rect2(Vector2(app.new_scene_dialog.position), Vector2(app.new_scene_dialog.size))
		valid = valid and visible.encloses(dialog_rect) and dialog_rect.get_center().distance_to(visible.get_center()) < 2.0
		app.new_scene_dialog.hide()
		if not valid:
			failures += 1
		await RenderingServer.frame_post_draw
		var path = "res://screenshots/resize-%dx%d.png" % [dimensions.x, dimensions.y]
		var capture = root.get_texture().get_image()
		capture.save_png(path)
		results.append({"requested":[dimensions.x,dimensions.y], "window":[root.size.x,root.size.y], "rendered":[capture.get_width(),capture.get_height()], "logical":[visible.size.x,visible.size.y], "valid":valid})
		print("RESIZE: ", results[-1])
	# A visual fixture of the same end-of-track fall used by the regression test.
	root.size = Vector2i(1600,1000)
	app.empty_scene(true, 60.0, 40.0)
	await settle()
	if app.left_panel.size.x > 273 or app.right_panel.size.x > 289:
		failures += 1
		push_error("新建后侧面板宽度异常")
	var fixture = load("res://tests/derailment.gd").new()
	var train = fixture.setup(app, "HO", false)
	app.camera_target = Vector3(8.2, 1.0, 0)
	app.camera_distance = 17.0
	app.camera_yaw = -0.55
	app.camera_pitch = 0.52
	app.refresh_train_list()
	app.set_mode("operate")
	for stage in ["edge", "falling", "landed"]:
		var count = 20 if stage == "edge" else (240 if stage == "falling" else 900)
		await fixture.frames(app, count)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://screenshots/derailment-" + stage + ".png")
		var fitted = app.left_panel.get_global_rect().encloses(app.left_panel.get_child(0).get_global_rect())
		if not fitted:
			failures += 1
		print("VISUAL DERAILMENT: ", stage, " panels_fit=", fitted)
	var report = FileAccess.open("res://test-results/window-resize.json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"failures":failures,"windows":results}, "  "))
	quit(1 if failures > 0 else 0)
