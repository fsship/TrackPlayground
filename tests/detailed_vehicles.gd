extends RefCounted

const IDS = ["core:diesel", "core:electric", "core:coach", "core:freight", "core:tanker", "alpine:mountain_diesel"]
const TITLES = ["DF 柴油机车", "EL 电力机车", "客运车厢", "集装箱平车", "罐式货车", "山地柴油机车"]
var checks = 0
var failures = 0

func check(condition: bool, title: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + title)
	else:
		failures += 1
		push_error("FAIL: " + title)

func clip_z(polygon: Array, plane: float, above: bool) -> Array:
	var result = []
	if polygon.is_empty():
		return result
	var previous: Vector3 = polygon[-1]
	var previous_inside = previous.z >= plane if above else previous.z <= plane
	for current in polygon:
		var inside = current.z >= plane if above else current.z <= plane
		if inside != previous_inside:
			result.append(previous.lerp(current, (plane - previous.z) / (current.z - previous.z)))
		if inside:
			result.append(current)
		previous = current
		previous_inside = inside
	return result

func wheel_clearance(model) -> bool:
	# Clip real static mesh triangles to the wheel's lateral slab, then test
	# against its full rotational disc. This catches plates or pipe segments
	# crossing a tyre even when all triangle corners are outside the wheel.
	for node in model.model.get_children():
		if not node is MeshInstance3D or model.axles.any(func(axle): return axle.node == node):
			continue
		var vertices: PackedVector3Array = node.mesh.get_faces()
		for i in range(0, vertices.size(), 3):
			var a: Vector3 = node.transform * vertices[i]
			var b: Vector3 = node.transform * vertices[i + 1]
			var c: Vector3 = node.transform * vertices[i + 2]
			if minf(a.y, minf(b.y, c.y)) > 1.04:
				continue
			for axle in model.axles:
				var r: float = axle.radius + 0.025
				var center = Vector2(axle.node.position.x, axle.radius)
				if minf(a.x, minf(b.x, c.x)) > center.x + r or maxf(a.x, maxf(b.x, c.x)) < center.x - r or minf(a.y, minf(b.y, c.y)) > center.y + r:
					continue
				for side in [-1, 1]:
					var z0 = 0.65 if side > 0 else -0.84
					var z1 = 0.84 if side > 0 else -0.65
					var polygon = clip_z(clip_z([a, b, c], z0, true), z1, false)
					if polygon.size() < 2:
						continue
					var flat = PackedVector2Array()
					for point in polygon:
						flat.append(Vector2(point.x, point.y))
					var distance = INF
					if flat.size() >= 3 and Geometry2D.is_point_in_polygon(center, flat):
						distance = 0.0
					for j in flat.size():
						distance = minf(distance, center.distance_to(Geometry2D.get_closest_point_to_segment(center, flat[j], flat[(j + 1) % flat.size()])))
					if distance < r - 0.002:
						print("WHEEL_CLEARANCE_INTERSECTION node=%s axle=%.2f side=%d triangle=%s,%s,%s distance=%.3f radius=%.3f" % [node.name, center.x, side, a, b, c, distance, r])
						return false
	return true

func run(app, capture: bool = false) -> int:
	var inspector = preload("res://tests/steam_locomotive.gd").new()
	for ratio in [87.1, 160.0]:
		for id in IDS:
			var def: Dictionary = app.catalog.vehicles[id]
			var model = RailGeometry.vehicle(def, ratio)
			var box: AABB = inspector.bounds(model)
			var f = 10.0 / ratio
			check(box.size.x <= (def.length_m + 0.01) * f and box.size.z <= (def.width_m + 0.01) * f and box.end.y <= (def.height_m + 0.01) * f, "%s 1:%.1f 精细网格符合车辆包络：%s" % [id, ratio, box.size / f])
			check(box.position.x >= (-def.length_m * 0.5 - 0.01) * f and box.end.x <= (def.length_m * 0.5 + 0.01) * f and box.position.z >= (-def.width_m * 0.5 - 0.01) * f and box.end.z <= (def.width_m * 0.5 + 0.01) * f, id + " 车体两端及两侧均保持在原有碰撞边界内")
			check(absf(box.position.y + 0.025 * f) < 0.001, id + " 轮缘下探量正确，轮面落在轨面")
			check(model.axles.size() == (6 if id in ["core:diesel", "core:electric"] else 4), id + " 车轴数与两台转向架匹配")
			var body_mesh: ArrayMesh = model.model.get_child(0).mesh
			var indexed_surfaces = true
			for surface in body_mesh.get_surface_count():
				var used = {}
				for index in body_mesh.surface_get_arrays(surface)[Mesh.ARRAY_INDEX]:
					used[index] = true
				indexed_surfaces = indexed_surfaces and used.size() >= body_mesh.surface_get_array_len(surface) * 0.95
			check(indexed_surfaces, id + " 曲面与标准几何合并后顶点仍被索引，车顶与端面无丢面")
			if ratio == 87.1:
				check(wheel_clearance(model), id + " 车体、底盘、转向架、踏板与制动件未穿入轮缘旋转空间")
			model.sync_motion(0, 4, false, false)
			model.sync_motion(0.5, 4, false, false)
			var phase: float = model.axles[0].node.rotation.z
			check(absf(phase - fposmod(-0.5 / model.axles[0].radius, TAU)) < 0.001, id + " 车轮按行驶距离滚动")
			model.sync_motion(0.5, 4, true, false)
			check(is_equal_approx(phase, model.axles[0].node.rotation.z), id + " 暂停保持轮相")
			model.sync_motion(1.0, -4, false, false)
			check(absf(model.wheel_travel) < 0.001, id + " 倒车轮组反向旋转")
			var other = RailGeometry.vehicle(def, ratio)
			check(other.model.get_child(0).mesh == model.model.get_child(0).mesh, id + " 多辆车辆复用静态网格")
			var original_material: Material = other.model.get_child(0).mesh.surface_get_material(0)
			RailGeometry.apply_preview_material(model, RailGeometry.material(Color(0.2, 0.5, 1, 0.4)))
			check(other.model.get_child(0).material_override == null and other.model.get_child(0).mesh.surface_get_material(0) == original_material, id + " 放置虚影不污染实际车辆")
			model.free()
			other.free()
	var override = app.catalog.vehicles["core:diesel"].duplicate(true)
	override.model_path = "res://mods/alpine_pack/water_tower.glb"
	var custom = RailGeometry.vehicle(override, 87.1)
	check(not custom.has_method("sync_motion") and custom.get_child_count() == 1, "外部 GLB 模型仍优先于程序生成外观")
	custom.free()
	for scale_name in ["HO", "N"]:
		app.graph.scale_name = scale_name
		app.empty_scene()
		var p = Vector3(-14, 0.1, 0)
		for i in 20:
			var part = app.graph.add_part("core:" + scale_name + ":straight", p, 0, 0.01)
			p = app.graph.edges[str(part.uid) + ":0"].points[-1]
		app.rebuild_rails()
		var cars = IDS.duplicate()
		cars.insert(3, "core:coach")
		var train = app.simulation.add_train(cars, "12:0", 1.0, "精细车辆验证")
		check(not train.is_empty(), scale_name + " 全车型混合编组可放上坡轨")
		if train.is_empty():
			continue
		train.target = 12
		app.simulation.paused = false
		for i in 180:
			app.simulation.tick(1.0 / 60.0)
			app.update_train_visuals()
		check(not train.fault and train.velocity > 0.5 and app.train_nodes[train.id].all(func(node): return node.wheel_travel > 0.1), scale_name + " 全车型在运行中驱动轮组动画")
		check(app.train_connections[train.id].links.size() == cars.size() - 1 and app.train_connections[train.id].links[2].gangway != null, "车钩、软管与两辆客车之间的折棚保持连接")
		var data = app.snapshot()
		check(app.validate_snapshot(data).is_empty() and app.apply_snapshot(data), scale_name + " 精细车型存档往返成功")
	if capture:
		await capture_models(app)
	var file = FileAccess.open("res://test-results/detailed-vehicles.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks, "failures":failures}, "\t"))
	print("DETAILED_VEHICLES_RESULT checks=%d failures=%d" % [checks, failures])
	return failures

func studio(app, def: Dictionary, size: Vector2i) -> Dictionary:
	var viewport = SubViewport.new()
	viewport.size = size
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_4X
	app.add_child(viewport)
	var world = Node3D.new()
	viewport.add_child(world)
	var environment = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("26333a")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("cedde7")
	env.ambient_light_energy = 0.45
	environment.environment = env
	world.add_child(environment)
	for spec in [[Vector3(-0.85, -0.6, 0), 0.95, Color("fff0d9")], [Vector3(-0.5, 2.2, 0), 0.45, Color("c1dbed")]]:
		var light = DirectionalLight3D.new()
		light.rotation = spec[0]
		light.light_energy = spec[1]
		light.light_color = spec[2]
		light.shadow_enabled = true
		world.add_child(light)
	var model = RailGeometry.vehicle(def, 10.0)
	model.position.y = 0.08
	world.add_child(model)
	var connections = preload("res://scripts/vehicle_connections.gd").new()
	connections.setup([def.id], app.catalog, 10.0)
	world.add_child(connections)
	connections.update_from_cars([model])
	world.add_child(RailGeometry.track([PackedVector3Array([Vector3(-def.length_m * 0.65, 0, 0), Vector3(def.length_m * 0.65, 0, 0)])], 1.435))
	RailGeometry.box(world, Vector3(1500, 0.12, 1500), Vector3(0, -0.10, 0), Color("29353a"))
	var camera = Camera3D.new()
	camera.near = 0.05
	camera.far = 2000
	camera.fov = 36
	world.add_child(camera)
	camera.position = Vector3(def.length_m * 0.55, def.length_m * 0.34, def.length_m * 1.08)
	camera.look_at(Vector3(0, def.height_m * 0.48, 0))
	camera.current = true
	return {"viewport":viewport, "model":model, "camera":camera}

func capture_models(app) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://screenshots"))
	# Render the contact sheet in Godot from live 3D viewports, including labels.
	var gallery = SubViewport.new()
	gallery.size = Vector2i(1800, 1530)
	gallery.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	app.add_child(gallery)
	var backdrop = ColorRect.new()
	backdrop.color = Color("17242b")
	backdrop.size = Vector2(1800, 1530)
	gallery.add_child(backdrop)
	var studios = []
	for i in IDS.size():
		var view = studio(app, app.catalog.vehicles[IDS[i]], Vector2i(1800, 1000))
		studios.append(view)
		await app.get_tree().process_frame
		await RenderingServer.frame_post_draw
		view.viewport.get_texture().get_image().save_png("res://screenshots/vehicle-" + IDS[i].split(":")[1] + ".png")
		var rect = TextureRect.new()
		rect.texture = view.viewport.get_texture()
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.position = Vector2((i % 2) * 900 + 8, (i / 2) * 510 + 46)
		rect.size = Vector2(884, 456)
		gallery.add_child(rect)
		var title = Label.new()
		title.text = TITLES[i]
		title.position = Vector2((i % 2) * 900 + 28, (i / 2) * 510 + 10)
		title.add_theme_font_size_override("font_size", 27)
		title.modulate = Color("e6d4a9")
		gallery.add_child(title)
	await app.get_tree().process_frame
	await RenderingServer.frame_post_draw
	gallery.get_texture().get_image().save_png("res://screenshots/vehicles-detailed-gallery.png")
	var camera: Camera3D = studios[0].camera
	camera.position = Vector3(8.6, 2.3, 7)
	camera.look_at(Vector3(6.3, 0.8, 0))
	await RenderingServer.frame_post_draw
	studios[0].viewport.get_texture().get_image().save_png("res://screenshots/vehicle-bogie-detail.png")
	camera = studios[2].camera
	camera.position = Vector3(0.6, 3.0, 7.3)
	camera.look_at(Vector3(0, 2.3, 0))
	await RenderingServer.frame_post_draw
	studios[2].viewport.get_texture().get_image().save_png("res://screenshots/vehicle-coach-detail.png")
	for view in studios:
		view.viewport.queue_free()
	gallery.queue_free()
	await app.get_tree().process_frame
	var frame_times: Array = []
	var previous = Time.get_ticks_usec()
	app.simulation.paused = false
	for frame in 90:
		await app.get_tree().process_frame
		var now = Time.get_ticks_usec()
		if frame >= 15:
			frame_times.append((now - previous) / 1000.0)
		previous = now
	frame_times.sort()
	print("DETAILED_VEHICLES_FRAME_MS median=%.2f p95=%.2f" % [frame_times[frame_times.size() / 2], frame_times[int(frame_times.size() * 0.95)]])
