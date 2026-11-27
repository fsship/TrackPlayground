extends RefCounted

const Gear = preload("res://scripts/running_gear.gd")
const IDS = ["core:diesel", "core:electric", "core:coach", "core:freight", "core:tanker", "alpine:mountain_diesel", "core:steam_tender"]
var checks = 0
var failures = 0

func check(ok: bool, title: String) -> void:
	checks += 1
	if ok:
		print("PASS: " + title)
	else:
		failures += 1
		push_error("FAIL: " + title)

func sample_train(id: String, s: float, route: Array = [{"edge":"1:0", "rev":false}]) -> Dictionary:
	return {"cars":[id], "s":s, "route":route}

func aligned(app, node: Node3D, sample: Dictionary, def: Dictionary) -> bool:
	var spec = Gear.layout(def)
	var factor: float = 10.0 / app.simulation.ratio()
	var entries: Array = node.get_meta("bogie_nodes")
	for i in 2:
		var pivot: Node3D = entries[i].node
		var body_pin: Vector3 = node.transform * (Vector3(spec.center * (-1 if i == 0 else 1), spec.height, 0) * factor)
		if pivot.global_position.distance_to(body_pin) > 0.00005:
			return false
		# Extreme axle contact centres must lie on the actual baked route, even
		# when the truck and body have different yaw/pitch. Ignore wheel spin.
		for x in [spec.axles[0], spec.axles[-1]]:
			var contact = pivot.global_transform * (Vector3(x, -spec.height, 0) * (factor / entries[i].factor)) - Vector3.UP * 0.08
			var nearest: Dictionary = app.graph.nearest(contact, 1.0)
			if nearest.is_empty() or nearest.position.distance_to(contact) > 0.00005:
				return false
	return sample.bogie_fit

func pose_model(node: Node3D, sample: Dictionary) -> void:
	node.transform = Transform3D(sample.basis, sample.position + Vector3.UP * 0.08)
	Gear.apply(node, sample)

func run(app, capture: bool = false) -> int:
	for scale_name in ["HO", "N"]:
		app.graph.scale_name = scale_name
		app.empty_scene()
		app.graph.add_part("core:" + scale_name + ":flex_arc", Vector3.ZERO, 0, 0.04, false, {"radius_mm":430.0 if scale_name == "HO" else 280.0, "angle_deg":180.0})
		for id in IDS:
			var def: Dictionary = app.catalog.vehicles[id]
			var node = RailGeometry.vehicle(def, app.simulation.ratio())
			app.add_child(node)
			var train = sample_train(id, app.graph.edges["1:0"].length * 0.65)
			var sample: Dictionary = app.simulation.car_samples(train)[0]
			pose_model(node, sample)
			check(aligned(app, node, sample, def), scale_name + " " + id + " 弯坡轨轮组贴轨、车体支点不分离")
			var entries: Array = node.get_meta("bogie_nodes")
			check(absf(entries[0].node.rotation.y) > 0.02 and entries[0].node.rotation.y * entries[1].node.rotation.y < 0, id + " 前后转向架相对车体独立转向")
			var phase: float = node.axles[0].node.rotation.z
			node.sync_motion(0, 4, false, false)
			node.sync_motion(1, 4, false, false)
			check(not is_equal_approx(phase, node.axles[0].node.rotation.z) and aligned(app, node, sample, def), id + " 车轮滚动不改变转向架与轨道的连接")
			var reversed = sample_train(id, train.s, [{"edge":"1:0", "rev":true}])
			var reverse_sample: Dictionary = app.simulation.car_samples(reversed)[0]
			pose_model(node, reverse_sample)
			check(aligned(app, node, reverse_sample, def), id + " 反向路线仍贴轨且保持支点距离")
			node.free()
		# A body straddling a grade break must pitch less than its uphill truck.
		app.empty_scene()
		app.graph.add_part("core:" + scale_name + ":flex_straight", Vector3(-10, 0, 0), 0, 0, false, {"length_mm":1000.0})
		app.graph.add_part("core:" + scale_name + ":flex_straight", Vector3.ZERO, 0, 0.08, false, {"length_mm":1000.0})
		var train = sample_train("core:coach", 10.0 + app.simulation.vehicle_length("core:coach") * 0.5, [{"edge":"1:0", "rev":false}, {"edge":"2:0", "rev":false}])
		var sample: Dictionary = app.simulation.car_samples(train)[0]
		var coach = RailGeometry.vehicle(app.catalog.vehicles["core:coach"], app.simulation.ratio())
		app.add_child(coach)
		pose_model(coach, sample)
		check(aligned(app, coach, sample, app.catalog.vehicles["core:coach"]) and sample.bogies[0].basis.x.y < sample.tangent.y and sample.bogies[1].basis.x.y > sample.tangent.y, scale_name + " 坡道接头两台转向架独立俯仰并支撑车体")
		coach.free()
		test_transitions(app, scale_name)
	await test_lifecycle(app)
	if capture:
		await capture_curve(app)
	var file = FileAccess.open("res://test-results/bogies.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks, "failures":failures}, "\t"))
	print("BOGIES_RESULT checks=%d failures=%d" % [checks, failures])
	return failures

func test_transitions(app, scale_name: String) -> void:
	for shape in ["straight", "s", "transition"]:
		app.empty_scene()
		app.graph.add_part("core:" + scale_name + ":flex_" + shape, Vector3.ZERO, 0, 0.02, false, {"length_mm":1000.0, "offset_mm":150.0, "radius_mm":650.0})
		var coach = RailGeometry.vehicle(app.catalog.vehicles["core:coach"], app.simulation.ratio())
		app.add_child(coach)
		var half: float = app.simulation.vehicle_length("core:coach") * 0.5
		var track_length: float = app.graph.edges["1:0"].length
		var previous: Dictionary = {}
		var continuous = true
		var attached = true
		for step in 161:
			var s = lerpf(half + 0.05, track_length - half - 0.05, float(step) / 160.0)
			var sample: Dictionary = app.simulation.car_samples(sample_train("core:coach", s + half))[0]
			pose_model(coach, sample)
			attached = attached and aligned(app, coach, sample, app.catalog.vehicles["core:coach"])
			if not previous.is_empty():
				for i in 2:
					continuous = continuous and sample.bogies[i].basis.x.angle_to(previous.bogies[i].basis.x) < 0.04
			previous = sample
		check(attached and continuous, scale_name + " " + shape + " 全段连续通过，转向架无跳向或支点分离")
		if shape == "straight":
			check(coach.get_meta("bogie_nodes").all(func(entry): return entry.node.basis.is_equal_approx(Basis.IDENTITY)), "直轨上的转向架与车体对齐")
		coach.free()
	var generic: Dictionary = app.catalog.vehicles["core:coach"].duplicate(true)
	generic.id = "test:generic"
	app.catalog.vehicles[generic.id] = generic
	var node = RailGeometry.vehicle(generic, app.simulation.ratio())
	app.add_child(node)
	var sample: Dictionary = app.simulation.car_samples(sample_train(generic.id, 5.0))[0]
	pose_model(node, sample)
	check(aligned(app, node, sample, generic), scale_name + " 无 GLB 的通用 Mod 车辆同样支持转向架约束")
	node.free()
	app.catalog.vehicles.erase(generic.id)

func test_lifecycle(app) -> void:
	app.graph.scale_name = "HO"
	app.empty_scene()
	app.graph.add_part("core:HO:flex_arc", Vector3(-4, 0, -4), 0, 0, false, {"radius_mm":430.0, "angle_deg":180.0})
	app.rebuild_rails()
	app.draft_cars = ["core:diesel", "core:coach"]
	app.begin_train_placement()
	app.update_train_preview({"edge":"1:0", "distance":8.0})
	check(app.valid_placement and app.preview.get_child(1).has_meta("bogie_nodes"), "放置虚影使用活动转向架")
	var preview_pose: Transform3D = app.preview.get_child(1).get_meta("bogie_nodes")[0].node.global_transform
	var train: Dictionary = app.simulation.add_train(app.draft_cars, "1:0", 8.0)
	check(not train.is_empty(), "弯道编组可以放置")
	if train.is_empty():
		return
	app.set_mode("operate")
	var coach: Node3D = app.train_nodes[train.id][1]
	check(coach.get_meta("bogie_nodes")[0].node.global_transform.is_equal_approx(preview_pose), "正式放置与虚影姿态完全一致")
	var saved = app.snapshot()
	check(app.apply_snapshot(saved), "活动转向架场景存档往返")
	train = app.simulation.trains[0]
	coach = app.train_nodes[train.id][1]
	check(coach.get_meta("bogie_nodes")[0].node.global_transform.is_equal_approx(preview_pose), "载入后自动重建转向架约束")
	var rotation: Basis = coach.get_meta("bogie_nodes")[0].node.basis
	app.simulation.derail(train)
	app.update_train_visuals()
	check(coach.get_meta("bogie_nodes")[0].node.basis.is_equal_approx(rotation), "脱轨解除贴轨约束并保留转向架角度")
	saved = JSON.parse_string(JSON.stringify(app.snapshot()))
	check(app.validate_snapshot(saved).is_empty() and app.apply_snapshot(saved), "脱轨转向架角度可通过 JSON 保存并载入")
	train = app.simulation.trains[0]
	coach = app.train_nodes[train.id][1]
	check(coach.get_meta("bogie_nodes")[0].node.basis.is_equal_approx(rotation), "重建脱轨车辆不把转向架回正")
	var invalid = saved.duplicate(true)
	invalid.trains[0].derailed_cars[0].bogie_rotations = [[0, 0, 0, 0]]
	check(not app.validate_snapshot(invalid).is_empty(), "拒绝非法转向架四元数")
	for pose in saved.trains[0].derailed_cars:
		pose.erase("bogie_rotations")
	check(app.validate_snapshot(saved).is_empty(), "缺少转向架角度的旧脱轨存档仍兼容")
	check(app.simulation.reset_train(train), "脱轨编组可重新上轨")
	app.update_train_visuals()
	check(coach.get_meta("bogie_nodes")[0].node.global_transform.is_equal_approx(preview_pose), "复位后重新应用轨道约束")
	app.empty_scene()
	app.graph.add_part("core:HO:flex_arc", Vector3.ZERO, 0, 0, false, {"radius_mm":80.0, "angle_deg":180.0})
	var impossible: Dictionary = app.simulation.car_samples(sample_train("core:coach", 2.3))[0]
	check(not impossible.bogie_fit and impossible.position.is_finite(), "过小半径报告无法贴合，不产生无效姿态")

func capture_curve(app) -> void:
	app.graph.scale_name = "HO"
	app.empty_scene()
	app.graph.add_part("core:HO:flex_arc", Vector3(-4, 0.2, -4), 0, 0, false, {"radius_mm":430.0, "angle_deg":180.0})
	app.rebuild_rails()
	var train: Dictionary = app.simulation.add_train(["core:diesel", "core:coach"], "1:0", 8.0)
	app.simulation.paused = true
	var coach: Node3D = app.train_nodes[train.id][1]
	var center: Vector3 = coach.global_position
	app.set_process(false)
	var viewport = SubViewport.new()
	viewport.size = Vector2i(1600, 900)
	viewport.world_3d = app.get_world_3d()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_4X
	app.add_child(viewport)
	var camera = Camera3D.new()
	viewport.add_child(camera)
	camera.current = true
	camera.near = 0.01
	camera.fov = 42
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://screenshots"))
	for closeup in [false, true]:
		var focus = coach.get_meta("bogie_nodes")[1].node.global_position if closeup else center + Vector3.UP * 0.14
		camera.position = focus + coach.basis * (Vector3(0.45, 0.35, 1.1) if closeup else Vector3(0.5, 1.5, 3.9))
		camera.look_at(focus)
		await app.get_tree().process_frame
		await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png("res://screenshots/bogies-" + ("closeup" if closeup else "curve") + ".png")
	viewport.queue_free()
