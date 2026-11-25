extends RefCounted

var failures = 0
var checks = 0

func check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + description)
	else:
		failures += 1
		push_error("FAIL: " + description)

func run(app) -> int:
	var sim = app.simulation
	var graph = app.graph
	var catalog = app.catalog
	test_scene_settings(app)
	app.make_demo()
	check(sim.trains.size() == 2, "示例双列车成功放置")
	check(graph.parts.size() == 48, "双环线和道岔场共 48 个零件")
	check(graph.open_end_count() == 3, "两环闭合、道岔场仅三个开放端点")
	check(catalog.packages.size() == 1 and catalog.errors.is_empty(), "示例 Mod 清洁加载")
	check(catalog.tracks.has("alpine:ho_long") and catalog.vehicles.has("alpine:mountain_diesel"), "Mod 轨道和车辆可注册")
	var custom = RailGeometry.scenery_model(catalog.scenery["alpine:water_tower"], 87.1)
	check(custom.get_child_count() > 0, "外部 GLB 模型运行时加载")
	custom.free()
	var before = app.snapshot()
	var first = sim.trains[0]
	var previous = sim.sample_route(first, first.s).position
	var max_jump = 0.0
	for i in range(60 * 180):
		sim.tick(1.0 / 60.0)
		var point = sim.sample_route(first, first.s).position
		max_jump = maxf(max_jump, point.distance_to(previous))
		previous = point
	check(not first.fault and not sim.trains[1].fault, "双列车模拟 180 秒无脱轨或断轨")
	check(first.distance_m > 800 and sim.trains[1].distance_m > 650, "两列车独立持续行驶")
	check(max_jump < 0.02, "列车跨零件连接处位置连续")
	check(absf(first.velocity * 3.6 - 23.0) < 2, "速度控制收敛到设定值")
	check(not sim.reverse(first), "运动中禁止换向")
	first.target = 0
	for i in range(60 * 35):
		sim.tick(1.0 / 60.0)
	check(absf(first.velocity) < 0.01, "行车制动可完全停车")
	check(sim.reverse(first) and first.direction == -1, "停车后可换向")
	first.target = 18
	for i in range(60 * 30):
		sim.tick(1.0 / 60.0)
	check(first.velocity < -3.0 and not first.fault, "反向跨轨道连续运行")
	sim.emergency(first)
	for i in range(60 * 10):
		sim.tick(1.0 / 60.0)
	check(absf(first.velocity) < 0.01, "紧急制动生效")
	var count = sim.trains.size()
	var front = sim.sample_route(first, first.s)
	check(sim.add_train(["core:diesel"], front.edge, front.distance).is_empty() and sim.trains.size() == count, "拒绝重叠生成列车")
	app.apply_snapshot(before)
	var center_height = app.terrain.height_at(12, 8)
	app.push_undo()
	app.terrain.brush(Vector3(12, 0, 8), 2.0, 1.0, "raise", 1.0)
	check(app.terrain.height_at(12, 8) > center_height + 0.6, "地形笔刷改变高度")
	app.undo()
	check(absf(app.terrain.height_at(12, 8) - center_height) < 0.001, "地形编辑可撤销")
	app.redo()
	check(app.terrain.height_at(12, 8) > center_height + 0.6, "地形编辑可重做")
	var data = app.snapshot()
	var json = JSON.parse_string(JSON.stringify(data))
	check(app.apply_snapshot(json), "JSON 保存数据可以无损重新加载")
	check(app.simulation.paused and app.simulation.trains.size() == 2, "载入时保留编组并安全暂停")
	var save_path = "res://test-results/roundtrip.railway"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test-results"))
	check(app.save_layout(save_path) and FileAccess.file_exists(save_path), "场景文件原子写入")
	check(app.save_layout(save_path), "覆盖已有场景文件")
	var invalid = data.duplicate(true)
	invalid.parts[0].definition = "missing:track"
	check(not app.validate_snapshot(invalid).is_empty(), "缺失 Mod 场景在修改世界前被拒绝")
	invalid = data.duplicate(true)
	invalid.trains[0].velocity = "bad"
	check(not app.validate_snapshot(invalid).is_empty(), "拒绝非法列车数值")
	invalid = data.duplicate(true)
	invalid.next_part = 1
	check(not app.validate_snapshot(invalid).is_empty(), "拒绝会导致重复 ID 的场景")
	invalid = data.duplicate(true)
	invalid.trains[0].route[0].edge = "99999:0"
	check(not app.apply_snapshot(invalid) and app.simulation.trains.size() == 2, "错误路径不会破坏已加载世界")
	var parked_s: float = app.simulation.trains[0].s
	app.simulation.tick(1.0)
	check(app.simulation.trains[0].s == parked_s, "暂停时物理位置不变")
	var loop_sim = RailSimulation.new(app.graph, catalog)
	var long_consist: Array = ["core:diesel"]
	for i in range(23):
		long_consist.append("core:coach")
	check(loop_sim.add_train(long_consist, "4:0", 1.0).is_empty(), "拒绝长度超过环线的自重叠编组")
	var fast = loop_sim.add_train(["core:diesel"], "7:0", 1.0)
	fast.velocity = 30.0
	fast.target = 108.0
	loop_sim.tick(1.0 / 60)
	check(fast.fault and "脱轨" in fast.state, "弯道超速保护触发")
	var fresh = RailCatalog.new()
	check(fresh.tracks.has("core:N:inner_demo"), "新会话可识别 N 场景所需全部内置轨道")
	check(not catalog.register_package({"api_version":99,"id":"bad"}), "拒绝不兼容 Mod API")
	check(not catalog.register_package({"api_version":1,"id":"bad2","tracks":[{"id":"x","scale":"HO","kind":"curve","radius_mm":-1,"angle_deg":20}]}), "拒绝非物理 Mod 参数")
	test_switch(catalog)
	test_physics(catalog)
	app.graph.scale_name = "N"
	app.selected_track = "core:N:straight"
	app.make_demo()
	check(app.graph.open_end_count() == 3 and app.simulation.trains.size() == 2, "N 比例环线和双列车生成")
	for i in range(60 * 45):
		app.simulation.tick(1.0 / 60.0)
	check(not app.simulation.trains[0].fault and not app.simulation.trains[1].fault, "N 比例运行通过")
	check(absf(app.simulation.vehicle_length("core:diesel") - 20.7 * 10 / 160) < 0.001, "N 比例车辆尺寸严格按 1:160 缩放")
	var track_buried = false
	for e in app.graph.edges.values():
		for p in e.points:
			if app.terrain.height_at(p.x, p.z) > p.y + 0.05:
				track_buried = true
	check(not track_buried, "N 示例路基不会埋入中央山丘")
	var n_saved = JSON.parse_string(JSON.stringify(app.snapshot()))
	check(app.apply_snapshot(n_saved), "N 场景 JSON 往返保存")
	print("CHECKS: %d, FAILURES: %d" % [checks, failures])
	var report = FileAccess.open("res://test-results/integration.json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks,"failures":failures,"engine":Engine.get_version_info().string,"tested":"blank startup, sandbox sizing/persistence/bounds, camera panning, HO/N routing, train control, collision, grades, switches, terrain, persistence, mods"}, "  "))
	return failures

func test_scene_settings(app) -> void:
	check(app.graph.parts.is_empty() and app.simulation.trains.is_empty() and app.scenery_items.is_empty(), "默认启动为空白场景")
	check(Array(app.terrain.heights).all(func(h): return h == 0.0) and app.selected_train == -1, "空白场景地形平整且没有选中列车")
	var legacy = app.snapshot()
	legacy.erase("sandbox")
	app.show_new_scene()
	check(app.new_scene_dialog.visible and app.new_scene_width.value == 3.4 and app.new_scene_depth.value == 2.6, "新建窗口预填当前沙盘尺寸")
	app.new_scene_width.get_line_edit().text = "6.0"
	app.new_scene_depth.get_line_edit().text = "4.0"
	app.new_scene_dialog.confirmed.emit()
	app.new_scene_dialog.hide()
	check(app.terrain.width == 60.0 and app.terrain.depth == 40.0, "创建会应用尚未失焦的宽度和深度输入")
	check(app.table_base.mesh.size.is_equal_approx(Vector3(60.3, 0.6, 40.3)) and app.water.mesh.size.is_equal_approx(Vector3(59.9, 0.025, 39.9)), "桌面和水面同步使用新尺寸")
	check(app.mode_label.text.contains("6.0 × 4.0"), "场景标签显示实际尺寸")
	app.selected_track = "core:HO:straight"
	app.placement = Vector3(22, 0, 0)
	app.placement_yaw = 0
	check(app.place_track(), "大沙盘可在原边界外铺轨")
	app.placement = Vector3(29, 0, 0)
	check(not app.place_track(), "轨道端点不得越过新沙盘边界")
	var hit = app.terrain.ray_hit(Vector3(25, 160, 0), Vector3.DOWN)
	check(hit.is_finite() and absf(hit.y) < 0.01, "远距离视角可拾取扩大后的地形")
	app.terrain.brush(Vector3(22, 0, 8), 1.4, 1.0, "raise", 1.0)
	var raised: float = app.terrain.height_at(22, 8)
	check(raised > 0.7, "大沙盘保持地形笔刷精度")
	var sized = JSON.parse_string(JSON.stringify(app.snapshot()))
	app.push_undo()
	app.empty_scene(true, 10.0, 8.0)
	check(app.graph.parts.is_empty() and app.terrain.width == 10.0, "缩小沙盘同时清空已有内容")
	app.placement = Vector3(4, 0, 0)
	check(not app.place_track(), "小沙盘限制铺轨边界")
	app.undo()
	check(app.terrain.width == 60.0 and app.graph.parts.size() == 1 and absf(app.terrain.height_at(22, 8) - raised) < 0.001, "撤销新建恢复尺寸、轨道与地形")
	app.redo()
	check(app.terrain.width == 10.0 and app.terrain.depth == 8.0 and app.graph.parts.is_empty(), "重做恢复小空白沙盘")
	check(app.apply_snapshot(sized) and app.terrain.width == 60.0 and absf(app.terrain.height_at(22, 8) - raised) < 0.001, "自定义尺寸和地形 JSON 往返读取")
	var invalid = sized.duplicate(true)
	invalid.sandbox.width = 0
	check(not app.apply_snapshot(invalid) and app.terrain.width == 60.0 and app.graph.parts.size() == 1, "非法尺寸在改变场景前被拒绝")
	invalid = sized.duplicate(true)
	invalid.sandbox.depth = 20.0
	check(not app.apply_snapshot(invalid) and app.terrain.depth == 40.0, "拒绝与尺寸不匹配的地形网格")
	check(app.apply_snapshot(legacy) and app.terrain.width == 34.0 and app.terrain.depth == 26.0 and app.terrain.heights.size() == 85 * 65, "旧版无尺寸字段的存档保持兼容")
	for size in [Vector2(5, 5), Vector2(100, 100), Vector2(5, 100), Vector2(100, 5)]:
		app.empty_scene(true, size.x, size.y)
		var bounds: Vector3 = app.terrain.mesh.get_aabb().size
		check(app.validate_snapshot(app.snapshot()).is_empty() and Vector2(bounds.x, bounds.z).is_equal_approx(size), "尺寸极值 %s 的地形和存档合法" % size)
	app.empty_scene()
	for angle in [0.0, PI / 2, PI, -0.55]:
		for pitch in [0.2, 0.88, 1.49]:
			for drag in [Vector2(20, 0), Vector2(-20, 0), Vector2(0, 20), Vector2(0, -20)]:
				app.camera_yaw = angle
				app.camera_pitch = pitch
				app.camera_target = Vector3.ZERO
				app.update_camera()
				var screen_before: Vector2 = app.camera.unproject_position(Vector3.ZERO)
				app.pan_camera(drag)
				app.update_camera()
				var movement: Vector2 = app.camera.unproject_position(Vector3.ZERO) - screen_before
				check(movement.dot(drag) > 0.1 and absf(app.camera_target.y) < 0.001, "中键拖动画面随鼠标移动 yaw=%.2f pitch=%.2f drag=%s" % [angle, pitch, drag])
	app.undo_stack.clear()
	app.redo_stack.clear()
	app.empty_scene()

func straight_graph(catalog, grade: float = 0.0):
	var graph = RailGraph.new(catalog)
	var p = Vector3.ZERO
	for i in range(20):
		var part = graph.add_part("core:HO:straight", p, 0, grade)
		p = graph.edges[str(part.uid) + ":0"].points[-1]
	return graph

func test_switch(catalog) -> void:
	var graph = RailGraph.new(catalog)
	graph.add_part("core:HO:straight", Vector3(-2.3,0,0), 0)
	var part = graph.add_part("core:HO:turnout", Vector3.ZERO, 0)
	var straight = graph.next_edge({"edge":"1:0","rev":false})
	check(straight.get("edge", "") == "2:0", "道岔默认选择直股")
	part.branch = 1
	var diverge = graph.next_edge({"edge":"1:0","rev":false})
	check(diverge.get("edge", "") == "2:1", "扳动道岔选择侧股")
	var trailing = graph.next_edge({"edge":"2:1","rev":true})
	check(trailing.get("edge", "") == "1:0" and trailing.rev, "侧股反向正确合流")
	var snap = graph.snap(Vector3(-2.3,0,0))
	check(not snap.is_empty() and snap.out.x < -0.9, "端点吸附方向正确")

func test_physics(catalog) -> void:
	var flat = RailSimulation.new(straight_graph(catalog), catalog)
	var uphill = RailSimulation.new(straight_graph(catalog, 0.04), catalog)
	var a = flat.add_train(["core:diesel", "core:tanker", "core:tanker"], "5:0", 1.5)
	var b = uphill.add_train(["core:diesel", "core:tanker", "core:tanker"], "5:0", 1.5)
	a.target = 100
	b.target = 100
	for i in range(600):
		flat.tick(1.0 / 60.0)
		uphill.tick(1.0 / 60.0)
	check(a.velocity > b.velocity + 1.0, "真实质量和坡度使上坡列车加速更慢")
	check(b.grade > 3.9 and b.grade < 4.1, "按车辆占位统计线路坡度")
	var dry = RailSimulation.new(straight_graph(catalog), catalog)
	var wet = RailSimulation.new(straight_graph(catalog), catalog)
	wet.wet_rails = true
	var c = dry.add_train(["core:diesel"], "5:0", 1.5)
	var d = wet.add_train(["core:diesel"], "5:0", 1.5)
	c.target = 100
	d.target = 100
	# Force an adhesion-sensitive high trailing mass.
	c.cars.append_array(["core:tanker", "core:tanker", "core:tanker"])
	d.cars.append_array(["core:tanker", "core:tanker", "core:tanker"])
	for i in range(300):
		dry.tick(1.0 / 60.0)
		wet.tick(1.0 / 60.0)
	check(c.velocity > d.velocity + 0.2, "湿轨降低牵引黏着上限")
	var collision = RailSimulation.new(straight_graph(catalog), catalog)
	var lead = collision.add_train(["core:diesel"], "9:0", 1.5)
	var rear = collision.add_train(["core:diesel"], "6:0", 1.5)
	rear.target = 70
	for i in range(3600):
		collision.tick(1.0 / 60.0)
	check(lead.fault and rear.fault and not collision.overlaps(lead, rear), "追尾接触停车并回退重叠位置")
	var buffer = RailSimulation.new(straight_graph(catalog), catalog)
	var end = buffer.add_train(["core:diesel"], "20:0", 2.1)
	end.target = 30
	for i in range(900):
		buffer.tick(1.0 / 60.0)
	check(end.fault and end.state == "到达轨道尽头", "开放端点不会越界或传送")
	var cross_graph = RailGraph.new(catalog)
	for axis in [0, 1]:
		var origin = Vector3(-9.2, 0, 0) if axis == 0 else Vector3(0, 0, -9.2)
		for i in range(8):
			var part = cross_graph.add_part("core:HO:straight", origin, 0 if axis == 0 else -PI / 2)
			origin = cross_graph.edges[str(part.uid) + ":0"].points[-1]
	var crossing = RailSimulation.new(cross_graph, catalog)
	var occupied = crossing.add_train(["core:diesel"], "5:0", 1.5)
	var other = crossing.add_train(["core:diesel"], "13:0", 1.5)
	check(not occupied.is_empty() and other.is_empty(), "空间包络阻止不同图边上的交叉碰撞")
	var edit_sim = RailSimulation.new(straight_graph(catalog), catalog)
	var editable = edit_sim.add_train(["core:diesel"], "8:0", 1.0)
	var front_before = edit_sim.sample_route(editable, editable.s)
	check(edit_sim.reconfigure(editable, ["core:diesel", "core:coach"]), "停车后可增加车厢")
	check(edit_sim.sample_route(editable, editable.s).position.distance_to(front_before.position) < 0.001, "修改编组保留车头位置和历史路径")
	check(not edit_sim.reconfigure(editable, ["core:coach"]), "拒绝无机车编组且保留原列车")
