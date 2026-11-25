extends RefCounted

var checks = 0
var failures = 0
var input = preload("res://tests/train_placement.gd").new()

func check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + message)
	else:
		failures += 1
		push_error("FAIL: " + message)

func fixture(catalog, finish: Vector3, yaw: float = 0, scale_name: String = "HO", grade: float = 0) -> RailGraph:
	var graph = RailGraph.new(catalog)
	graph.scale_name = scale_name
	graph.add_part("core:" + scale_name + ":flex_straight", Vector3(-10, 0, 0), 0, 0, false, {"length_mm":600.0})
	graph.add_part("core:" + scale_name + ":flex_straight", finish, yaw, grade, false, {"length_mm":600.0})
	return graph

func test_geometry(catalog) -> void:
	for scale_name in ["HO", "N"]:
		var graph = RailGraph.new(catalog)
		graph.scale_name = scale_name
		for shape in ["straight", "arc", "s", "transition"]:
			var definition: Dictionary = catalog.tracks["core:" + scale_name + ":flex_" + shape]
			var options = {"length_mm":600.0, "radius_mm":650.0, "angle_deg":60.0, "offset_mm":120.0}
			var normal = graph.make_paths(definition, Vector3.ZERO, 0, 0.035, false, options)[0]
			var mirrored = graph.make_paths(definition, Vector3.ZERO, 0, 0.035, true, options)[0]
			var measured = RailFlexTrack.measure(normal, 34, 26)
			check(measured.error.is_empty() and measured.length > 5.9 and absf(measured.max_grade - 0.035) < 0.0001, "%s %s 柔轨按参数生成并保留 3.5%% 坡度" % [scale_name, shape])
			check(normal.size() == mirrored.size() and normal[-1].is_equal_approx(Vector3(mirrored[-1].x, mirrored[-1].y, -mirrored[-1].z)), "%s %s 镜像仅改变左右方向" % [scale_name, shape])
			var part = graph.add_part(definition.id, Vector3.ZERO, 0, 0.035, false, options)
			var edge = str(part.uid) + ":0"
			check(graph.edges[edge].points == normal and graph.edges[edge].length > 0, "%s %s 图边、渲染路径一致" % [scale_name, shape])
			var radius: float = graph.sample(edge, graph.edges[edge].length * 0.25).radius
			check(radius == 0 if shape == "straight" else radius > 0, "%s %s 向动力学提供局部弯曲半径" % [scale_name, shape])
	var mod_catalog = RailCatalog.new()
	check(mod_catalog.register_package({"api_version":1,"id":"flexmod","tracks":[{"id":"s","scale":"N","kind":"flex","shape":"s","length_mm":350,"offset_mm":50}]}), "Mod 支持参数化柔轨")
	check(not mod_catalog.register_package({"api_version":1,"id":"badflex","tracks":[{"id":"s","scale":"HO","kind":"flex","shape":"s","length_mm":-5}]}), "Mod 拒绝非法柔轨参数")

func test_connections(catalog) -> void:
	for scale_name in ["HO", "N"]:
		for test_case in [["直线",Vector3(4,0,0),0.0,0.0], ["错位 S 弯",Vector3(4,0,2),0.0,0.0], ["直角",Vector3(2,0,6),-PI/2,0.0], ["回转",Vector3(-4,0,8),PI,0.0], ["高差坡度",Vector3(4,0.3,2),0.0,0.03]]:
			var graph = fixture(catalog, test_case[1], test_case[2], scale_name, test_case[3])
			var a = graph.endpoint("1:0", 1)
			var b = graph.endpoint("2:0", 0)
			var result = graph.plan_connection(a, b, 34, 26, 1.8)
			check(result.error.is_empty(), "%s 自动连接%s：%s" % [scale_name, test_case[0], result.error])
			if not result.error.is_empty():
				continue
			check(graph.plan_connection(b, a, 34, 26, 1.8).error.is_empty(), "交换两端选择顺序也能连接")
			check(graph.parts.size() == 2 and graph.next_uid == 3, "预览求解不修改轨道或消耗 ID")
			var part = graph.add_part("core:" + scale_name + ":flex_link", a.position, 0, 0, false, {"controls":result.controls})
			var edge = str(part.uid) + ":0"
			check(graph.connections["1:0@1"].any(func(e): return e.edge == edge) and graph.connections["2:0@0"].any(func(e): return e.edge == edge), "两端均建立可通行连接")
			check(graph.endpoint(edge, 0).position.distance_to(a.position) < 0.00001 and graph.endpoint(edge, 1).position.distance_to(b.position) < 0.00001 and graph.endpoint(edge, 0).out.dot(a.out) < -0.995 and graph.endpoint(edge, 1).out.dot(b.out) < -0.995, "位置与朝向连续且高差正确")
			check(graph.open_end_count() == 2, "新增柔轨不留下接缝开放端点")
			check(not graph.plan_connection(a, b, 34, 26, 1.8).error.is_empty(), "重复连接已连接端点被拒绝")
	var graph = fixture(catalog, Vector3(4,0,2))
	var a = graph.endpoint("1:0", 1)
	check(not graph.plan_connection(a, a, 34, 26, 1.8).error.is_empty(), "拒绝连接同一端点")
	check(not graph.plan_connection({"edge":"missing","end":0}, a, 34, 26, 1.8).error.is_empty(), "过期或已删除端点不会崩溃")
	check(not graph.plan_connection(a, graph.endpoint("2:0",0), 5, 5, 1.8).error.is_empty(), "拒绝超出沙盘的自动连接")
	graph = fixture(catalog, Vector3(-3,3.0,0))
	check(not graph.plan_connection(graph.endpoint("1:0",1), graph.endpoint("2:0",0),34,26,1.8).error.is_empty(), "拒绝无法满足 8% 的高差")
	graph = fixture(catalog, Vector3(4,0,2))
	check(not graph.plan_connection(graph.endpoint("1:0",1), graph.endpoint("2:0",0),34,26,100).error.is_empty(), "最小半径限制实际参与求解")
	graph = RailGraph.new(catalog)
	graph.add_part("core:HO:straight",Vector3(-4,0,0),PI)
	graph.add_part("core:HO:straight",Vector3(6.3,0,2),PI)
	var reversed = graph.plan_connection(graph.endpoint("1:0",0),graph.endpoint("2:0",1),34,26,1.8)
	check(reversed.error.is_empty(), "支持从轨道起点连接到另一轨道终点")
	# A turnout's diverging end is independently selectable and connectable.
	graph = RailGraph.new(catalog)
	graph.add_part("core:HO:turnout", Vector3(-5,0,0),0)
	var turnout_end = graph.endpoint("1:1",1)
	var target: Vector3 = turnout_end.position + turnout_end.out * 6
	graph.add_part("core:HO:straight",target,atan2(-turnout_end.out.z,turnout_end.out.x))
	var joined = graph.plan_connection(turnout_end,graph.endpoint("2:0",0),34,26,1.8)
	check(joined.error.is_empty(), "支持道岔侧股端连接")
	if joined.error.is_empty():
		graph.add_part("core:HO:flex_link",turnout_end.position,0,0,false,{"controls":joined.controls})
		check(graph.connections["1:1@1"].size() == 1, "侧股连接写入正确分支")

func test_train(catalog) -> void:
	var graph = fixture(catalog, Vector3(4,0.2,2), 0, "HO", 0.01)
	var a = graph.endpoint("1:0",1)
	var result = graph.plan_connection(a,graph.endpoint("2:0",0),34,26,1.8)
	if not result.error.is_empty():
		check(false, "行车测试连接生成成功")
		return
	graph.add_part("core:HO:flex_link",a.position,0,0,false,{"controls":result.controls})
	var sim = RailSimulation.new(graph,catalog)
	var train = sim.add_train(["core:diesel"],"1:0",5.0)
	check(not train.is_empty(), "柔轨线路允许创建列车")
	if train.is_empty():
		return
	train.target = 8
	var previous: Vector3 = sim.sample_route(train,train.s).position
	var max_jump = 0.0
	for i in range(60*60):
		sim.tick(1.0/60)
		var current = sim.sample_route(train,train.s)
		max_jump = maxf(max_jump,previous.distance_to(current.position))
		previous = current.position
		if current.edge == "2:0" and current.distance > 2.5:
			break
	check(not train.fault and sim.sample_route(train,train.s).edge == "2:0" and max_jump < 0.02, "列车跨越带坡 S 柔轨与两处接缝，无跳跃或断轨")
	train.target = 0
	for i in 600:
		sim.tick(1.0/60)
	check(sim.reverse(train), "柔轨线路停车后可换向")
	train.target = 8
	for i in range(60*60):
		sim.tick(1.0/60)
		if sim.sample_route(train,train.s).edge == "1:0":
			break
	check(not train.fault and sim.sample_route(train,train.s).edge == "1:0", "反向行车沿原柔轨连续返回")
	var fast = RailSimulation.new(graph,catalog)
	var overspeed = fast.add_train(["core:diesel"],"3:0",3.0)
	overspeed.velocity = 40
	overspeed.target = 144
	fast.tick(1.0/60)
	check(overspeed.fault and "脱轨" in overspeed.state, "柔轨局部半径参与弯道超速保护")

func run(app, screenshots: bool = false) -> int:
	test_geometry(app.catalog)
	test_connections(app.catalog)
	test_train(app.catalog)
	var original_parent: Node = app.get_parent()
	var viewport = SubViewport.new()
	viewport.size = Vector2i(1600,1000)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.gui_embed_subwindows = true
	original_parent.add_child(viewport)
	app.reparent(viewport)
	app.graph.scale_name = "HO"
	app.empty_scene()
	app.undo_stack.clear()
	app.redo_stack.clear()
	app.graph.parts = fixture(app.catalog,Vector3(4,0.3,2),0,"HO",0.03).parts
	app.graph.next_uid = 3
	app.graph.rebuild()
	app.rebuild_rails()
	app.set_mode("track")
	app.camera_target = Vector3(0,0,1)
	app.camera_distance = 26
	app.camera_yaw = 0
	app.camera_pitch = 1.0
	app.update_camera()
	for i in 3:
		await app.get_tree().process_frame
	var auto_button: Button
	for child in app.left_body.get_children():
		if child is Button and child.text == "自动连接 · 选择两个端点":
			auto_button = child
	check(auto_button != null, "轨道面板提供自动连接入口")
	auto_button.pressed.emit()
	var a = app.graph.endpoint("1:0",1)
	var b = app.graph.endpoint("2:0",0)
	input.motion(app,app.camera.unproject_position(a.position))
	input.click(app)
	check(not app.connection_start.is_empty() and app.connection_marker.visible and app.graph.parts.size() == 2, "鼠标第一击只选中起点并高亮")
	input.motion(app,app.camera.unproject_position(b.position))
	check(app.connection_plan.get("error","missing").is_empty() and app.preview != null and app.preview.visible, "悬浮第二端点显示可连接曲线虚影")
	await input.capture(app,"flex-auto-preview",screenshots)
	input.click(app)
	check(app.graph.parts.size() == 3 and app.graph.open_end_count() == 2 and app.connection_start.is_empty(), "第二次鼠标点击完成连接并清空选择")
	check(app.undo_stack.size() == 1, "一次自动连接只产生一步撤销")
	var saved = JSON.parse_string(JSON.stringify(app.snapshot()))
	check(app.validate_snapshot(saved).is_empty() and app.apply_snapshot(saved) and app.graph.open_end_count() == 2, "JSON 往返保留柔轨形状和两个连接")
	check(app.save_layout("res://test-results/flex-roundtrip.railway"), "柔轨场景可以保存到文件")
	var expected: PackedVector3Array = app.graph.edges["3:0"].points
	app.undo()
	check(app.graph.parts.size() == 2 and app.graph.open_end_count() == 4, "撤销自动连接恢复原来两个端点")
	app.redo()
	check(app.graph.parts.size() == 3 and app.graph.edges["3:0"].points == expected, "重做准确恢复曲线")
	for malformed in [null, {}, {"controls":[[0,0,0]]}, {"controls":[[0,0,0],[0,0,0],[0,0,0],[0,0,0]]}, {"controls":[[0,0,0],[1,"bad",0],[2,0,0],[3,0,0]]}]:
		var invalid = saved.duplicate(true)
		invalid.parts[-1].flex = malformed
		check(not app.validate_snapshot(invalid).is_empty(), "载入拒绝缺失、损坏或退化柔轨控制点")
	app.begin_auto_connect()
	app.choose_connection_endpoint(app.graph.endpoint("1:0",0))
	input.key(app,KEY_ESCAPE)
	check(not app.auto_connect and app.connection_start.is_empty() and not app.connection_marker.visible, "Esc 取消自动连接及选中标记")
	app.undo()
	app.set_mode("track")
	app.begin_auto_connect()
	app.choose_connection_endpoint(app.graph.endpoint("1:0",1))
	var radius_control: SpinBox = app.left_body.get_children().filter(func(node): return node is SpinBox)[0]
	radius_control.value = 2000
	var before = app.snapshot()
	app.update_connection_preview(app.graph.endpoint("2:0",0))
	check(not app.connection_plan.error.is_empty() and app.preview.visible and app.preview.get_child(0).material_override.albedo_color == app.TRAIN_PREVIEW_INVALID, "无解候选显示红色曲线与原因")
	check(not app.choose_connection_endpoint(app.graph.endpoint("2:0",0)) and app.snapshot() == before and not app.connection_start.is_empty(), "连接失败保留场景与起点，可继续换选")
	await input.capture(app,"flex-rejected",screenshots)
	app.choose_connection_endpoint(app.graph.endpoint("1:0",1))
	check(app.connection_start.is_empty(), "再次点击起点可以重新选择")
	app.connection_min_radius = 180
	app.select_track("core:HO:flex_s")
	var spins: Array = app.left_body.get_children().filter(func(node): return node is SpinBox)
	spins[1].value = 700
	spins[2].value = 120
	check(app.flex_options.get("length_mm") == 700 and app.flex_options.get("offset_mm") == 120, "面板数值调整实际更新柔轨参数")
	spins[3].value = 60
	spins[4].value = 2
	app.yaw = 0
	app.mirror = false
	app.track_placement_endpoint = 1
	app.update_track_preview(Vector3(3,0,-3),{})
	check(app.valid_placement and app.place_track(), "可调 S 柔轨支持终点锚定和实际铺设")
	var custom_part: Dictionary = app.graph.parts[-1]
	check(app.graph.part_paths(custom_part)[0][-1].distance_to(Vector3(3,0.6,-3)) < 0.0001, "柔轨终点锚定高程与预览一致")
	check(app.validate_snapshot(JSON.parse_string(JSON.stringify(app.snapshot()))).is_empty(), "参数化柔轨也可存档")
	for i in 3:
		await app.get_tree().process_frame
	input.motion(app,app.camera.unproject_position(Vector3(3,0,-3)))
	await input.capture(app,"flex-parameters",screenshots)
	app.flex_options = {"length_mm":100.0,"offset_mm":500.0}
	app.update_track_preview(Vector3.ZERO,{})
	var count: int = app.graph.parts.size()
	check(not app.valid_placement and not app.place_track() and app.graph.parts.size() == count, "手工柔轨半径不足时预览与落位同时拒绝")
	var report = FileAccess.open("res://test-results/flex-track.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks,"failures":failures},"  "))
	print("FLEX_TRACK_RESULT checks=%d failures=%d" % [checks,failures])
	app.reparent(original_parent)
	viewport.queue_free()
	app.empty_scene()
	await app.get_tree().process_frame
	return failures
