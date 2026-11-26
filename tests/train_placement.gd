extends RefCounted

var checks = 0
var failures = 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + message)
	else:
		failures += 1
		push_error("FAIL: " + message)

func motion(app, position: Vector2) -> void:
	var event = InputEventMouseMotion.new()
	event.position = position
	app.get_viewport().push_input(event, true)
	app.update_preview()

func key(app, code: Key, echo: bool = false) -> void:
	var event = InputEventKey.new()
	event.keycode = code
	event.pressed = true
	event.echo = echo
	app.get_viewport().push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	event.echo = false
	app.get_viewport().push_input(event, true)

func click(app) -> void:
	var event = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = app.get_viewport().get_mouse_position()
	event.pressed = true
	app.get_viewport().push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	app.get_viewport().push_input(event, true)

func capture(app, name: String, enabled: bool) -> void:
	if not enabled:
		return
	await RenderingServer.frame_post_draw
	app.get_viewport().get_texture().get_image().save_png("res://screenshots/placement-" + name + ".png")

func test_routes(catalog) -> void:
	var cars = ["core:diesel", "core:coach", "core:tanker"]
	for scale_name in ["HO", "N"]:
		var graph = RailGraph.new(catalog)
		graph.scale_name = scale_name
		var point = Vector3.ZERO
		var yaw = 0.0
		for i in 12:
			var kind = "curve" if i >= 4 and i < 8 else "straight"
			var part = graph.add_part("core:" + scale_name + ":" + kind, point, yaw, 0.03)
			point = graph.edges[str(part.uid) + ":0"].points[-1]
			if kind == "curve":
				yaw -= PI / 6
		for reversed in [false, true]:
			var sim = RailSimulation.new(graph, catalog)
			var result = sim.train_placement(cars, "6:0", 0.8, reversed)
			check(result.error.is_empty(), "%s 弯道坡轨可预览%s编组" % [scale_name, "反向" if reversed else "正向"])
			check(sim.trains.is_empty() and sim.next_uid == 1, "悬浮校验不创建列车或消耗 ID")
			var front = sim.sample_route(result.train, result.train.s)
			check(front.position.distance_to(graph.sample("6:0", 0.8).position) < 0.001, "翻转方向保持鼠标指定的车头位置")
			var expected = sim.car_samples(result.train, true)
			var train = sim.add_train(cars, "6:0", 0.8, "", reversed)
			check(not train.is_empty() and sim.car_samples(train) == expected, "实际落位与弯道虚影逐车一致")
			var blocked = sim.train_placement(cars, "6:0", 0.8, reversed)
			check(blocked.error.contains("重叠") and sim.add_train(cars, "6:0", 0.8, "", reversed).is_empty(), "占用位置预览与放置均拒绝重叠")
			var start = sim.car_samples(train)[0].position
			train.target = 10
			for tick in 120:
				sim.tick(1.0 / 60.0)
			check((sim.car_samples(train)[0].position - start).dot(expected[0].tangent) > 0.001, "新列车按预览朝向前进")
		var sim = RailSimulation.new(graph, catalog)
		var short_route = sim.train_placement(cars, "1:0", 0.2)
		check(short_route.error.contains("长度不足"), "尽头轨道不足在预览阶段被识别")
		var samples = sim.car_samples(short_route.train, true)
		check(samples[0].position.distance_to(samples[1].position) > sim.vehicle_length(cars[0]) * 0.8 and samples[2].tangent.length() > 0.99, "红色虚影超出尽头仍完整展开，不堆叠或塌缩")
		check(sim.train_placement(cars, "1:0", 0.2, true).error.is_empty(), "Tab 翻转到有足够轨道的一侧后可放置")
		check(sim.train_placement(["core:coach"], "6:0", 0.8).error.contains("机车"), "无机车草稿报告原因且保留可显示的候选")
		check(not sim.train_placement([], "6:0", 0.8).error.is_empty(), "空草稿不可放置")

func run(app, screenshots: bool = false) -> int:
	test_routes(app.catalog)
	# A SubViewport accepts deterministic local mouse input even in headless
	# runs, without moving the user's actual desktop cursor.
	var original_parent: Node = app.get_parent()
	var viewport = SubViewport.new()
	viewport.size = Vector2i(1600, 1000)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.gui_embed_subwindows = true
	original_parent.add_child(viewport)
	app.reparent(viewport)
	app.graph.scale_name = "HO"
	app.empty_scene()
	var point = Vector3(-9.2, 0.5, 0)
	for i in 8:
		var part = app.graph.add_part("core:HO:straight", point, 0)
		point = app.graph.edges[str(part.uid) + ":0"].points[-1]
	app.rebuild_rails()
	app.camera_target = Vector3(0, 0.5, 0)
	app.camera_distance = 28
	app.camera_yaw = -0.1
	app.camera_pitch = 0.75
	app.update_camera()
	app.draft_cars = ["core:diesel", "core:coach"]
	app.set_mode("operate")
	for frame in 3:
		await app.get_tree().process_frame
	var place_button: Button
	for child in app.left_body.get_children():
		if child is Button and child.text.begins_with("将编组"):
			place_button = child
	place_button.grab_focus()
	place_button.pressed.emit()
	motion(app, app.camera.unproject_position(Vector3(0, 0.5, 0)))
	check(app.preview != null and app.preview.visible and app.valid_placement and app.preview.get_child_count() == 3 and app.preview.has_node("Connections"), "悬浮轨道显示完整编组及连接件")
	if app.preview == null:
		app.reparent(original_parent)
		viewport.queue_free()
		return failures
	check(app.train_preview_material.albedo_color == app.TRAIN_PREVIEW_VALID and app.train_preview_material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA, "可放置虚影为蓝色半透明")
	await capture(app, "blue", screenshots)
	var forward: Transform3D = app.preview.get_child(0).transform
	key(app, KEY_TAB)
	check(app.train_placement_reversed and app.preview.get_child(0).basis.x.dot(forward.basis.x) < -0.99, "放置按钮仍有焦点时 Tab 可翻转车头")
	check(app.get_viewport().gui_get_focus_owner() == place_button, "Tab 被放置工具消费，不跳转 UI 焦点")
	key(app, KEY_TAB, true)
	check(app.train_placement_reversed, "长按 Tab 的键盘重复事件不会连续翻转")
	await capture(app, "reversed", screenshots)
	key(app, KEY_TAB)
	check(not app.train_placement_reversed and app.preview.get_child(0).transform.is_equal_approx(forward), "第二次 Tab 恢复原朝向与位置")
	app.draft_cars.append("core:tanker")
	app.update_preview()
	check(app.preview.get_child_count() == 4 and app.preview.get_node("Connections").links.size() == 2, "编辑草稿时虚影同步更新车辆与连接数量")
	app.draft_cars = ["core:coach"]
	app.update_preview()
	check(not app.valid_placement and app.preview.visible and app.train_preview_material.albedo_color == app.TRAIN_PREVIEW_INVALID, "无机车时仍显示红色完整虚影")
	await capture(app, "red", screenshots)
	var undo_count: int = app.undo_stack.size()
	click(app)
	check(app.simulation.trains.is_empty() and app.undo_stack.size() == undo_count and app.placing_train, "点击红色虚影不创建列车，不污染撤销记录")
	app.draft_cars = ["core:diesel", "core:coach"]
	app.update_preview()
	key(app, KEY_TAB)
	var expected = []
	for node in app.preview.get_children().slice(0, app.draft_cars.size()):
		expected.append(node.transform)
	click(app)
	check(app.simulation.trains.size() == 1 and not app.placing_train and not app.preview.visible, "点击蓝色虚影完成放置并清除预览")
	if not app.simulation.trains.is_empty():
		var train = app.simulation.trains[0]
		check(app.train_nodes[train.id][0].transform.is_equal_approx(expected[0]) and app.train_nodes[train.id][1].transform.is_equal_approx(expected[1]), "反向放置的真实车辆与虚影姿态一致")
		check(app.validate_snapshot(app.snapshot()).is_empty(), "反向放置编组可正常保存")
	app.begin_train_placement()
	key(app, KEY_TAB)
	check(not app.valid_placement and app.preview.visible, "已占用轨道立即显示不可放置预览")
	motion(app, app.left_panel.get_global_rect().get_center())
	check(not app.preview.visible, "鼠标进入界面面板隐藏虚影")
	motion(app, app.camera.unproject_position(Vector3(0, 0.5, 4)))
	check(not app.preview.visible and not app.valid_placement, "离开轨道隐藏虚影且不能放置")
	app.show_new_scene()
	key(app, KEY_TAB)
	check(app.train_placement_reversed, "对话框内 Tab 不改变编组方向")
	app.new_scene_dialog.hide()
	app.get_viewport().gui_release_focus()
	key(app, KEY_ESCAPE)
	check(not app.placing_train and app.preview == null, "Esc 取消放置并移除虚影")
	key(app, KEY_TAB)
	check(app.train_placement_reversed, "非放置模式 Tab 不改变编组方向")
	var report = FileAccess.open("res://test-results/train-placement.json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks, "failures":failures}, "  "))
	print("PLACEMENT_RESULT checks=%d failures=%d" % [checks, failures])
	app.reparent(original_parent)
	viewport.queue_free()
	return failures
