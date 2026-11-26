extends RefCounted

const Connections = preload("res://scripts/vehicle_connections.gd")
var checks = 0
var failures = 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + message)
	else:
		failures += 1
		push_error("FAIL: " + message)

func attached(rig, cars: Array) -> bool:
	for i in cars.size():
		for end in [-1, 1]:
			var fitting: Dictionary = rig.ends[i][end]
			var expected: Vector3 = cars[i].transform * fitting.anchor
			if expected.distance_to(rig.transform * fitting.housing.position) > 0.0002:
				return false
			if fitting.shank.visible:
				var start: Vector3 = rig.transform * fitting.shank.transform * Vector3(-0.5, 0, 0)
				if start.distance_to(expected) > 0.0002:
					return false
	for link in rig.links:
		var a: Dictionary = rig.ends[link.a][-1]
		var b: Dictionary = rig.ends[link.b][1]
		if link.drawbar:
			if (link.bar.transform * Vector3(-0.5, 0, 0)).distance_to(a.housing.position) > 0.00001 or (link.bar.transform * Vector3(0.5, 0, 0)).distance_to(b.housing.position) > 0.00001:
				return false
		else:
			# Local jaw offsets are prototype metres, whereas head origins are scaled.
			var tip_a: Vector3 = a.head.position + a.head.basis * Vector3(0.055, 0, -0.055) * rig.factor
			var tip_b: Vector3 = b.head.position + b.head.basis * Vector3(0.055, 0, -0.055) * rig.factor
			if tip_a.distance_to(tip_b) > 0.00001:
				return false
	return true

func run(app, capture: bool = false) -> int:
	for scale_name in ["HO", "N"]:
		app.empty_scene()
		app.graph.scale_name = scale_name
		app.graph.add_part("core:" + scale_name + ":flex_arc", Vector3(-8, 0.4, -6), 0, 0.035, false, {"radius_mm":900.0, "angle_deg":120.0})
		app.rebuild_rails()
		var ids = ["core:steam", "core:steam_tender", "core:coach", "core:coach", "alpine:mountain_diesel", "core:freight", "core:tanker"]
		var train = app.simulation.add_train(ids, "1:0", 17.0)
		check(not train.is_empty(), scale_name + " 混合编组可放置于曲线坡道")
		if train.is_empty():
			continue
		var nodes: Array = app.train_nodes[train.id]
		var rig = app.train_connections[train.id]
		check(rig.links.size() == ids.size() - 1 and rig.ends.size() == ids.size(), "每对相邻车辆生成一组连接，首尾保留开放车钩")
		check(rig.links[0].drawbar and rig.links[2].gangway != null and rig.links[1].gangway == null and rig.links[4].gangway == null, "煤水车用牵引杆，只有相邻客车带风挡，货车和混编不生成风挡")
		check(attached(rig, nodes), scale_name + " 曲线坡道上所有车钩根部与两端钩头对齐")
		check(absf(rig.ends[0][1].housing.scale.y - 0.28 * 10.0 / app.simulation.ratio()) < 0.00001, "连接件按模型比例缩放")
		var connected = true
		for direction in [1, -1]:
			for step in 45:
				train.s += direction * 0.025
				app.update_train_visuals()
				connected = connected and attached(rig, nodes)
		check(connected, scale_name + " 正反向经过曲线时连接持续贴合，不依赖行驶方向")
		var mesh: ImmediateMesh = rig.links[2].gangway.mesh
		check(mesh.get_surface_count() == 1 and mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() == 288, "客车风挡生成完整的可变形折棚表面")
		var saved = JSON.parse_string(JSON.stringify(app.snapshot()))
		var loaded: bool = app.apply_snapshot(saved)
		train = app.simulation.trains[0]
		check(loaded and app.train_connections[train.id].links.size() == ids.size() - 1, "无需新增存档字段，JSON 往返自动重建连接件")
		app.simulation.derail(train)
		# Arbitrary rolled/pitched car poses cover the full off-track transform path.
		var rolled = Basis.from_euler(Vector3(0.55, -0.3, 0.25)).get_rotation_quaternion()
		train.derailed_cars[2].rotation = [rolled.x, rolled.y, rolled.z, rolled.w]
		app.derailment.sync(app.simulation)
		app.update_train_visuals()
		rig = app.train_connections[train.id]
		nodes = app.train_nodes[train.id]
		check(attached(rig, nodes), "脱轨旋转后车钩、风挡仍跟随各自车体")
		var joints = []
		for child in app.derailment.consists[train.id].root.get_children():
			if child is PinJoint3D:
				joints.append(child)
		var joint_match = joints.size() == ids.size() - 1
		for i in joints.size():
			var expected = Connections.joint_center(app.catalog.vehicles[ids[i]], app.catalog.vehicles[ids[i + 1]], nodes[i].transform, nodes[i + 1].transform, app.simulation.ratio())
			joint_match = joint_match and joints[i].position.distance_to(expected) < 0.00001
		check(joint_match, "脱轨物理关节与可见连接使用同一安装点")
		check(app.simulation.reset_train(train), "连接件不影响脱轨复位")
		app.derailment.sync(app.simulation)
		app.update_train_visuals()
		check(attached(rig, nodes), "复位后连接件恢复沿轨姿态")
		check(app.simulation.reconfigure(train, ["core:diesel"]), "停车可缩短为单机")
		app.rebuild_trains()
		check(app.train_connections[train.id].links.is_empty() and app.train_connections[train.id].ends.size() == 1, "缩短编组清除旧连接，单机保留两端车钩")
		app.simulation.remove_train(train.id)
		check(app.train_connections.is_empty(), "移除列车清理连接件索引")
	await test_preview(app)
	if capture:
		await capture_models(app)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test-results"))
	var file = FileAccess.open("res://test-results/vehicle-connections.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks, "failures":failures}, "\t"))
	print("CONNECTIONS_RESULT checks=%d failures=%d" % [checks, failures])
	return failures

func test_preview(app) -> void:
	app.empty_scene()
	app.graph.scale_name = "HO"
	app.graph.add_part("core:HO:flex_straight", Vector3(-10, 0, 0), 0, 0, false, {"length_mm":2000.0})
	app.draft_cars = ["core:diesel", "core:coach", "core:coach"]
	app.begin_train_placement()
	app.update_train_preview({"edge":"1:0", "distance":12.0})
	var rig = app.preview.get_node("Connections")
	check(rig.links.size() == 2 and rig.links[1].gangway != null and attached(rig, app.preview.get_children().slice(0, 3)), "放置预览包括完整车钩与客车风挡")
	check(rig.ends[0][1].head.get_child(0).material_override == app.train_preview_material and rig.links[0].hose.material_override == app.train_preview_material and rig.links[1].gangway.material_override == app.train_preview_material, "连接件全部使用预览颜色，不污染真实列车材质")
	app.train_placement_reversed = true
	app.update_train_preview({"edge":"1:0", "distance":8.0})
	check(app.valid_placement and attached(rig, app.preview.get_children().slice(0, 3)), "反向放置预览中的连接保持对齐")
	app.set_mode("operate")

func capture_models(app) -> void:
	var viewport = SubViewport.new()
	viewport.size = Vector2i(1600, 1000)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_4X
	app.add_child(viewport)
	var scene = Node3D.new()
	viewport.add_child(scene)
	var world = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("34454c")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("cfdae1")
	env.ambient_light_energy = 0.5
	world.environment = env
	scene.add_child(world)
	var light = DirectionalLight3D.new()
	light.rotation = Vector3(-0.8, -0.5, 0)
	light.light_energy = 0.85
	light.shadow_enabled = true
	scene.add_child(light)
	var camera = Camera3D.new()
	scene.add_child(camera)
	camera.near = 0.01
	camera.fov = 42
	camera.current = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://screenshots"))
	for spec in [["coach-gangway", "core:coach", "core:coach"], ["steam-drawbar", "core:steam", "core:steam_tender"], ["freight-coupler", "core:freight", "core:tanker"]]:
		var pair = Node3D.new()
		scene.add_child(pair)
		var ids = [spec[1], spec[2]]
		var nodes = []
		for i in 2:
			var def: Dictionary = app.catalog.vehicles[ids[i]]
			var model = RailGeometry.vehicle(def, 10.0)
			pair.add_child(model)
			model.position.x = (1 if i == 0 else -1) * (def.length_m * 0.5 + 0.35)
			if i == 1:
				# Rotate about the body end, reproducing articulation in a curve.
				model.basis = Basis(Vector3.UP, 0.12) * Basis(Vector3.BACK, 0.025)
				model.position = Vector3(-0.35, 0, 0) - model.basis.x * def.length_m * 0.5
			nodes.append(model)
		var rig = Connections.new()
		rig.setup(ids, app.catalog, 10.0)
		pair.add_child(rig)
		rig.update_from_cars(nodes)
		RailGeometry.box(pair, Vector3(50, 0.08, 14), Vector3(0, -0.10, 0), Color("596064"))
		camera.position = Vector3(1.0, 2.8, 7.7) if ids[0] == "core:coach" else Vector3(0.7, 1.7, 5.3)
		camera.look_at(Vector3(0, 1.8 if ids[0] == "core:coach" else 0.9, 0))
		await app.get_tree().process_frame
		await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png("res://screenshots/" + spec[0] + ".png")
		pair.free()
	viewport.queue_free()
