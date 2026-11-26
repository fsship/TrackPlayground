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

func bounds(node: Node3D, parent_transform: Transform3D = Transform3D.IDENTITY) -> AABB:
	var transform = parent_transform * node.transform
	var result = AABB()
	if node is MeshInstance3D:
		result = transform * node.mesh.get_aabb()
	for child in node.get_children():
		if child is Node3D and not child is Label3D:
			var child_bounds = bounds(child, transform)
			if child_bounds.size.length_squared() > 0:
				result = child_bounds if result.size == Vector3.ZERO else result.merge(child_bounds)
	return result

func run(app, capture: bool = false) -> int:
	var start = Time.get_ticks_msec()
	for ratio in [87.1, 160.0]:
		for id in ["core:steam", "core:steam_tender"]:
			var model = RailGeometry.vehicle(app.catalog.vehicles[id], ratio)
			var def: Dictionary = app.catalog.vehicles[id]
			var box = bounds(model)
			var f = 10.0 / ratio
			check(box.size.x <= (def.length_m + 0.01) * f and box.size.z <= (def.width_m + 0.01) * f and box.end.y <= (def.height_m + 0.01) * f, "%s 1:%.1f 实际网格符合编组及碰撞包络 %s" % [id, ratio, box.size / f])
			check(absf(box.position.y + 0.025 * f) < 0.001 and model.axles.size() == (4 if model.tender else 6), "轮缘与轨面位置、2-8-2 / 煤水车轴数正确")
			model.sync_motion(0, 3, false, false)
			model.sync_motion(0.7, 3, false, false)
			var phase: float = model.axles[0].node.rotation.z
			model.sync_motion(0.7, 3, true, false)
			check(is_equal_approx(model.axles[0].node.rotation.z, phase), "暂停不改变轮相")
			model.sync_motion(1.4, -3, false, false)
			check(absf(model.wheel_travel) < 0.0001, "后退按实际路程反向转动")
			if not model.tender:
				var valid_gear = true
				for i in 64:
					model.set_travel(i * TAU * 0.78 / 64)
					for linkage in model.gear:
						var rod: Node3D = linkage.connecting
						var end = rod.transform * Vector3(1.675, 0, 0)
						valid_gear = valid_gear and end.distance_to(linkage.slider.position) < 0.0001
						var pin = linkage.coupling.position + Vector3(0.85, 0, linkage.side * 0.14)
						valid_gear = valid_gear and (rod.transform * Vector3(-1.675, 0, 0)).distance_to(pin) < 0.0001
				check(valid_gear, "整周左右四分之一相位连杆与曲柄、十字头保持连接")
			var original_material = model.model.get_child(0).mesh.surface_get_material(0)
			RailGeometry.apply_preview_material(model, RailGeometry.material(Color(0.2, 0.5, 1, 0.4)))
			check(model.model.get_child(0).mesh.surface_get_material(0) == original_material and model.smoke == null, "预览不污染共享模型材质、不创建烟雾")
			model.free()
	print("STEAM_GEOMETRY_BUILD_MS: " + str(Time.get_ticks_msec() - start))
	var triangle_count = 0
	for mesh in preload("res://scripts/steam_locomotive.gd").meshes.values():
		for surface in mesh.get_surface_count():
			triangle_count += mesh.surface_get_array_index_len(surface) / 3
	print("STEAM_UNIQUE_MESH_TRIANGLES: " + str(triangle_count))
	app.draft_cars.clear()
	app.append_draft_vehicle("core:steam")
	check(app.draft_cars == ["core:steam", "core:steam_tender"], "从车辆列表添加蒸汽机车会成对加入煤水车")
	app.draft_cars.resize(23)
	app.draft_cars.fill("core:coach")
	app.append_draft_vehicle("core:steam")
	check(app.draft_cars.size() == 23, "编组只剩一个空位时不会部分添加蒸汽机车")
	for scale_name in ["HO", "N"]:
		app.graph.scale_name = scale_name
		app.empty_scene()
		var p = Vector3(-10, 0.15, 0)
		for i in 12:
			var part = app.graph.add_part("core:" + scale_name + ":straight", p, 0, 0.015)
			p = app.graph.edges[str(part.uid) + ":0"].points[-1]
		app.rebuild_rails()
		var train = app.simulation.add_train(["core:steam", "core:steam_tender", "core:coach"], "6:0", 1.0)
		check(not train.is_empty(), scale_name + " 蒸汽编组可在坡轨放置")
		if train.is_empty():
			continue
		train.target = 16
		app.simulation.paused = false
		for i in 300:
			app.simulation.tick(1.0 / 60.0)
			app.update_train_visuals()
		check(train.velocity > 1.0 and not train.fault, scale_name + " 蒸汽机车正常牵引煤水车与客车")
		check(app.train_nodes[train.id][0].wheel_travel > 1.0, "行车数据实际驱动车轮及连杆动画")
		var snapshot = app.snapshot()
		check(app.validate_snapshot(snapshot).is_empty() and app.apply_snapshot(snapshot), scale_name + " 蒸汽机车及煤水车存档往返成功")
		check(app.simulation.trains[0].cars == ["core:steam", "core:steam_tender", "core:coach"], "载入后车辆顺序保留")
	if capture:
		await capture_models(app)
		await capture_in_scene(app)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test-results"))
	var file = FileAccess.open("res://test-results/steam-locomotive.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks, "failures":failures}, "\t"))
	print("STEAM_RESULT checks=%d failures=%d" % [checks, failures])
	return failures

func capture_models(app) -> void:
	var viewport = SubViewport.new()
	viewport.size = Vector2i(1800, 1100)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_4X
	app.add_child(viewport)
	var scene = Node3D.new()
	viewport.add_child(scene)
	var world = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("26353b")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("c7d9e2")
	env.ambient_light_energy = 0.70
	world.environment = env
	scene.add_child(world)
	for spec in [[Vector3(-0.8, -0.5, 0), 1.6, Color("fff0d5")], [Vector3(-0.4, 2.3, 0), 1.1, Color("bad8f0")]]:
		var light = DirectionalLight3D.new()
		light.rotation = spec[0]
		light.light_energy = spec[1]
		light.light_color = spec[2]
		light.shadow_enabled = true
		scene.add_child(light)
	var engine = RailGeometry.vehicle(app.catalog.vehicles["core:steam"], 10.0)
	scene.add_child(engine)
	engine.position.y = 0.08
	engine.set_travel(0.45)
	var tender_model = RailGeometry.vehicle(app.catalog.vehicles["core:steam_tender"], 10.0)
	tender_model.position = Vector3(-12.0, 0.08, 0)
	scene.add_child(tender_model)
	var track = RailGeometry.track([PackedVector3Array([Vector3(-19, 0, 0), Vector3(9, 0, 0)])], 1.435)
	scene.add_child(track)
	RailGeometry.box(scene, Vector3(2000, 0.12, 2000), Vector3(0, -0.10, 0), Color("263136"))
	var cam = Camera3D.new()
	cam.near = 0.05
	cam.far = 300
	cam.fov = 37
	scene.add_child(cam)
	cam.current = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://screenshots"))
	var views = [
		["steam-overview", Vector3(17, 11, 27), Vector3(-4.5, 1.7, 0)],
		["steam-running-gear", Vector3(5.4, 3.2, 15), Vector3(0.6, 1.4, 0)],
		["steam-cab", Vector3(-12, 6.1, 10), Vector3(-4.35, 2.7, 0)],
		["steam-front", Vector3(16, 7.0, 11), Vector3(2.0, 2.0, 0)]
	]
	for view in views:
		cam.position = view[1]
		cam.look_at(view[2])
		await app.get_tree().process_frame
		await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png("res://screenshots/" + view[0] + ".png")
	engine.sync_motion(0.0, 4.0, false, false)
	await app.get_tree().create_timer(1.4).timeout
	check(engine.smoke != null and engine.smoke.emitting, "运行中烟囱粒子正常启动")
	check(engine.smoke.puffs[0].age > 0.5 and engine.smoke.puffs[0].node.global_position.y > engine.smoke.global_position.y + 0.5, "烟雾实际随时间上升、扩散")
	cam.position = Vector3(17, 11, 27)
	cam.look_at(Vector3(-4.5, 1.7, 0))
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png("res://screenshots/steam-smoke.png")
	engine.sync_motion(0.0, 4.0, true, false)
	check(engine.smoke.speed_scale == 0.0, "暂停冻结烟雾")
	var puff_position: Vector3 = engine.smoke.puffs[0].node.global_position
	engine.smoke._process(0.5)
	check(engine.smoke.puffs[0].node.global_position == puff_position, "暂停时烟团位置保持不变")
	engine.position.x += 1.0
	engine.sync_motion(0.0, 4.0, true, false)
	check(engine.smoke.puffs[0].node.global_position == puff_position, "移动烟囱不拖走已经发出的烟团")
	engine.sync_motion(0.0, 0.0, false, true)
	check(not engine.smoke.emitting, "脱轨关闭烟雾发射")
	viewport.queue_free()

func capture_in_scene(app) -> void:
	app.graph.scale_name = "HO"
	app.empty_scene()
	var p = Vector3(-9.2, 0, 0)
	for i in 8:
		var part = app.graph.add_part("core:HO:straight", p, 0)
		p = app.graph.edges[str(part.uid) + ":0"].points[-1]
	app.rebuild_rails()
	var train = app.simulation.add_train(["core:steam", "core:steam_tender"], "5:0", 1.2, "SY 0808 · 蒸汽机车")
	app.selected_train = train.id
	app.simulation.paused = true
	app.draft_cars = ["core:steam", "core:steam_tender"]
	app.set_mode("operate")
	app.refresh_train_list()
	app.update_train_visuals()
	app.update_ui()
	app.camera_target = app.train_nodes[train.id][0].position + Vector3(-0.6, 0.22, 0)
	app.camera_yaw = 0.40
	app.camera_pitch = 0.30
	app.camera_distance = 4.2
	app.update_camera()
	var frame_times: Array = []
	var previous = Time.get_ticks_usec()
	for frame in 90:
		await app.get_tree().process_frame
		var now = Time.get_ticks_usec()
		if frame >= 15:
			frame_times.append((now - previous) / 1000.0)
		previous = now
	frame_times.sort()
	print("STEAM_SCENE_FRAME_MS median=%.2f p95=%.2f" % [frame_times[frame_times.size() / 2], frame_times[int(frame_times.size() * 0.95)]])
	await app.get_tree().process_frame
	await RenderingServer.frame_post_draw
	app.get_viewport().get_texture().get_image().save_png("res://screenshots/steam-in-scene.png")
