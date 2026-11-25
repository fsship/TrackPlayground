extends RefCounted

var failures = 0
var checks = 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + message)
	else:
		failures += 1
		push_error("FAIL: " + message)

func frames(app, count: int, train: Dictionary = {}, car_index: int = 0) -> float:
	var min_up = 1.0
	for i in count:
		await app.get_tree().physics_frame
		if train.has("derailed_cars"):
			min_up = minf(min_up, app.simulation.car_samples(train)[car_index].basis.y.y)
	await app.get_tree().process_frame
	return min_up

func setup(app, scale_name: String, reverse: bool, height: float = 3.0) -> Dictionary:
	app.empty_scene(false)
	app.graph.scale_name = scale_name
	var point = Vector3(-10, height, 0)
	for i in 8:
		var part = app.graph.add_part("core:" + scale_name + ":straight", point, 0)
		point = app.graph.edges[str(part.uid) + ":0"].points[-1]
	app.terrain.rebuild()
	app.rebuild_rails()
	var sim = app.simulation
	sim.paused = false
	sim.derailments = false
	var cars = ["core:diesel", "core:coach", "core:tanker"]
	var train = sim.add_train(cars, "8:0", app.graph.edges["8:0"].length - 0.04)
	if reverse:
		train.route.clear()
		for i in 8:
			train.route.append({"edge":str(i + 1) + ":0", "rev":false})
		train.s = sim.consist_length(cars) + 0.04
	train.direction = -1 if reverse else 1
	train.velocity = 12.0 * train.direction
	train.target = 43.2
	app.selected_train = train.id
	return train

func run(app) -> int:
	for scale_name in ["HO", "N"]:
		for reverse in [false, true]:
			var train = setup(app, scale_name, reverse)
			var sim = app.simulation
			await frames(app, 30)
			check(train.has("derailed_cars"), "%s %s关闭保护可驶出尽头" % [scale_name, "倒车" if reverse else "正向"])
			if not train.has("derailed_cars"):
				continue
			var index = train.cars.size() - 1 if reverse else 0
			var start = RailGraph.array_v(train.derailed_cars[index].position)
			check(RailGraph.array_v(train.derailed_cars[index].linear).x * train.direction > 0.2, "脱轨保留行进方向与惯性")
			var trailing_index = 0 if reverse else train.cars.size() - 1
			check(RailGraph.array_v(train.derailed_cars[trailing_index].position).y > 2.9, "后方车厢在离开轨道前仍受轨面支撑")
			sim.paused = true
			await frames(app, 3)
			var paused_pose = train.derailed_cars.duplicate(true)
			await frames(app, 30)
			check(train.derailed_cars == paused_pose, "暂停会冻结坠落及旋转")
			sim.paused = false
			var fall_tilt = await frames(app, 360, train, index)
			var falling = RailGraph.array_v(train.derailed_cars[index].position)
			print("FALL: ", scale_name, " reverse=", reverse, " from=", start, " to=", falling)
			check(falling.y < start.y - 0.6, "高架尽头车辆受重力下落")
			if scale_name == "HO" and not reverse:
				var midair = JSON.parse_string(JSON.stringify(app.snapshot()))
				check(app.apply_snapshot(midair), "坠落途中也可以存档和读档")
				await frames(app, 3)
				train = sim.trains[0]
				check(RailGraph.array_v(train.derailed_cars[index].position).distance_to(falling) < 0.02, "空中读档保留原姿态")
				sim.paused = false
			await frames(app, 1200)
			var landed = RailGraph.array_v(train.derailed_cars[index].position)
			check(landed.y > -0.6 and landed.y < 1.0, "车辆与地面碰撞后停留在地表附近")
			check(RailGraph.array_v(train.derailed_cars[index].linear).length() < 0.3, "落地后摩擦耗散动能")
			check(fall_tilt < 0.98, "坠落过程产生俯仰或翻滚，而非只平移")
			var saved = JSON.parse_string(JSON.stringify(app.snapshot()))
			check(app.validate_snapshot(saved).is_empty() and app.apply_snapshot(saved), "脱轨状态可 JSON 存档并恢复")
			await frames(app, 3)
			train = sim.trains[0]
			check(RailGraph.array_v(train.derailed_cars[index].position).distance_to(landed) < 0.02, "读档保留坠落位置且默认暂停")
			check(sim.reset_train(train) and not train.has("derailed_cars") and not train.fault, "复位可将编组重新放回轨道")
			await frames(app, 3)
			check(app.derailment.consists.is_empty(), "复位清理旧刚体与车钩")
	var protected = setup(app, "HO", false)
	app.simulation.derailments = true
	await frames(app, 60)
	check(protected.fault and protected.state == "到达轨道尽头" and not protected.has("derailed_cars"), "开启保护时仍在尽头停车")
	var invalid = app.snapshot()
	invalid.trains[0].derailed_cars = [{"position":[0,0,0]}]
	check(not app.validate_snapshot(invalid).is_empty(), "拒绝损坏的脱轨存档")
	var train = setup(app, "HO", false, 0.0)
	await frames(app, 300)
	check(train.has("derailed_cars") and RailGraph.array_v(train.derailed_cars[0].position).y > -0.2, "地面轨道尽头脱轨不会穿地")
	app.simulation.remove_train(train.id)
	await frames(app, 3)
	check(app.derailment.consists.is_empty(), "删除脱轨列车清理物理对象")
	var report = FileAccess.open("res://test-results/derailment.json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks,"failures":failures}, "  "))
	print("DERAILMENT_CHECKS: %d, FAILURES: %d" % [checks, failures])
	return failures
