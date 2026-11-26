extends RefCounted

const Collision = preload("res://scripts/vehicle_collisions.gd")
var checks = 0
var failures = 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
	else:
		print("PASS: " + message)

func line(graph: RailGraph, origin: Vector3, yaw: float = 0.0) -> String:
	var part = graph.add_part("core:" + graph.scale_name + ":flex_straight", origin, yaw, 0, false, {"length_mm":1200.0})
	return str(part.uid) + ":0"

func setup(app, scale_name: String = "HO") -> RailSimulation:
	app.empty_scene(false)
	app.graph.scale_name = scale_name
	app.simulation.collision_physics = true
	app.simulation.derailments = false
	app.simulation.paused = false
	return app.simulation

func drive(train: Dictionary, speed: float) -> void:
	train.velocity = speed
	train.target = absf(speed) * 3.6
	train.direction = -1 if speed < 0 else 1

func until_contact(sim: RailSimulation, a: Dictionary, b: Dictionary, dt: float = 1.0 / 60.0) -> bool:
	for i in ceili(10.0 / dt):
		sim.tick(dt)
		if a.has("derailed_cars") and b.has("derailed_cars"):
			return true
	return false

func frames(app, count: int) -> void:
	for i in count:
		await app.get_tree().physics_frame
	await app.get_tree().process_frame

func momentum(sim: RailSimulation) -> Vector3:
	var result = Vector3.ZERO
	for train in sim.trains:
		for i in train.cars.size():
			result += RailGraph.array_v(train.derailed_cars[i].linear) * sim.catalog.vehicles[train.cars[i]].mass_kg / 1000.0
	return result

func energy(sim: RailSimulation) -> float:
	var result = 0.0
	for train in sim.trains:
		for i in train.cars.size():
			result += RailGraph.array_v(train.derailed_cars[i].linear).length_squared() * sim.catalog.vehicles[train.cars[i]].mass_kg / 2000.0
	return result

func head_on(app, scale_name: String, swapped: bool = false) -> Array:
	var sim = setup(app, scale_name)
	line(app.graph, Vector3(-12, 0, 0))
	line(app.graph, Vector3.ZERO)
	var a = sim.add_train(["core:diesel"], "1:0", 9)
	var b = sim.add_train(["core:electric"], "2:0", 3, "", true)
	drive(a, 20)
	drive(b, 20)
	if swapped:
		sim.trains.reverse()
	return [a, b]

func detection_tests(app) -> void:
	var sim: RailSimulation = app.simulation
	var first = head_on(app, "HO")
	check(until_contact(sim, first[0], first[1]), "迎头碰撞双方进入刚体模拟")
	var positions = [first[0].derailed_cars.duplicate(true), first[1].derailed_cars.duplicate(true)]
	var reverse_order = head_on(app, "HO", true)
	check(until_contact(sim, reverse_order[0], reverse_order[1]), "交换列车遍历顺序仍检测到碰撞")
	check(reverse_order[0].derailed_cars == positions[0] and reverse_order[1].derailed_cars == positions[1], "迎头接触姿态与遍历顺序无关")
	for scale_name in ["HO", "N"]:
		setup(app, scale_name)
		line(app.graph, Vector3(-12, 0, 0))
		line(app.graph, Vector3.ZERO)
		var a = sim.add_train(["core:diesel"], "1:0", 9)
		var b = sim.add_train(["core:electric"], "2:0", 1)
		drive(a, 180)
		check(until_contact(sim, a, b, 0.5), scale_name + " 高速大时间步追尾不会穿车")
		check(RailGraph.array_v(b.derailed_cars[0].linear).length() < 0.001 and RailGraph.array_v(a.derailed_cars[0].linear).x > 5, "交接保留动量，停车车辆等待实际冲量")
		setup(app, scale_name)
		line(app.graph, Vector3(-12, 0, 0))
		line(app.graph, Vector3(-12, 0, 0.7))
		a = sim.add_train(["core:diesel"], "1:0", 7)
		b = sim.add_train(["core:diesel"], "2:0", 7)
		for i in 30:
			sim.tick(1.0 / 60.0)
		check(not a.fault and not b.fault, scale_name + " 平行邻线不会误判碰撞")
		setup(app, scale_name)
		line(app.graph, Vector3(-6, 0, 0))
		line(app.graph, Vector3(0, 1.0, -6), -PI / 2)
		a = sim.add_train(["core:diesel"], "1:0", 7)
		b = sim.add_train(["core:diesel"], "2:0", 7)
		sim.tick(1.0 / 60.0)
		check(not a.is_empty() and not b.is_empty() and not a.fault and not b.fault, scale_name + " 高架立交不会误撞")
	var safe = head_on(app, "HO")
	sim.collision_physics = false
	for i in 240:
		sim.tick(1.0 / 60.0)
	check(safe[0].fault and safe[1].fault and not safe[0].has("derailed_cars") and not sim.overlaps(safe[0], safe[1]), "关闭碰撞物理保留接触停车模式")
	var saved = app.snapshot()
	check(not saved.physics.collisions and app.apply_snapshot(saved) and not sim.collision_physics, "碰撞开关随存档往返")
	saved.physics.erase("collisions")
	check(app.apply_snapshot(saved) and sim.collision_physics, "旧存档默认开启碰撞物理")
	saved.physics.collisions = "invalid"
	check(not app.validate_snapshot(saved).is_empty(), "拒绝非法碰撞设置")

func run(app, capture: bool = false) -> int:
	app.set_physics_process(false)
	detection_tests(app)
	for scale_name in ["HO", "N"]:
		var pair = head_on(app, scale_name)
		var sim: RailSimulation = app.simulation
		check(until_contact(sim, pair[0], pair[1]), scale_name + " 迎头接触交接成功")
		var initial_momentum = momentum(sim)
		var initial_energy = energy(sim)
		check(RailGraph.array_v(pair[0].derailed_cars[0].linear).x > 0 and RailGraph.array_v(pair[1].derailed_cars[0].linear).x < 0, "迎头碰撞保留相反运动方向")
		app.rebuild_rails()
		app.derailment.sync(sim)
		app.set_physics_process(true)
		await frames(app, 12)
		var final_momentum = momentum(sim)
		check(absf(final_momentum.x - initial_momentum.x) < maxf(5.0, absf(initial_momentum.x) * 0.25), scale_name + " 不等质量碰撞近似守恒水平总动量")
		check(energy(sim) < initial_energy * 0.4, scale_name + " 非弹性迎头撞击消耗动能")
		check(sim.car_samples(pair[0])[0].position.x < sim.car_samples(pair[1])[0].position.x, "撞击后没有互相穿越")
		sim.paused = true
		await frames(app, 3)
		var paused_poses = pair[0].derailed_cars.duplicate(true)
		await frames(app, 10)
		check(paused_poses == pair[0].derailed_cars, "暂停冻结碰撞后的平移和旋转")
		var saved = JSON.parse_string(JSON.stringify(app.snapshot()))
		check(app.apply_snapshot(saved), "碰撞状态可保存并载入")
		await frames(app, 3)
		var restored: Dictionary = sim.trains[0].derailed_cars[0]
		var old: Dictionary = paused_poses[0]
		check(sim.paused and RailGraph.array_v(restored.position).distance_to(RailGraph.array_v(old.position)) < 0.00001 and RailGraph.array_v(restored.linear).distance_to(RailGraph.array_v(old.linear)) < 0.00001 and absf(Quaternion(restored.rotation[0], restored.rotation[1], restored.rotation[2], restored.rotation[3]).dot(Quaternion(old.rotation[0], old.rotation[1], old.rotation[2], old.rotation[3]))) > 0.99999, "读档保留碰撞姿态、速度并暂停")
		sim.remove_train(sim.trains[1].id)
		check(sim.reset_train(sim.trains[0]), "移开另一编组后可复位上轨")
		await frames(app, 3)
		check(app.derailment.consists.is_empty(), "复位和删除清理碰撞刚体")
		app.set_physics_process(false)
	await side_impact(app, false, capture)
	await side_impact(app, true, capture)
	await rear_and_wreck_tests(app)
	app.set_physics_process(true)
	var report = FileAccess.open("res://test-results/vehicle-collisions.json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks, "failures":failures}, "  "))
	print("COLLISION_CHECKS: %d, FAILURES: %d" % [checks, failures])
	return failures

func side_impact(app, turnout: bool, capture: bool) -> void:
	var sim = setup(app)
	var a: Dictionary
	var b: Dictionary
	if turnout:
		var fixture = load("res://tests/turnout_routing.gd").new().junction(app.catalog, "HO")
		app.graph.parts = fixture.parts.duplicate(true)
		app.graph.next_uid = fixture.next_uid
		app.graph.rebuild()
		a = sim.add_train(["core:diesel", "core:coach"], "3:0", 3.0, "", true)
		b = sim.add_train(["core:electric", "core:freight"], "4:0", 3.0, "", true)
	else:
		line(app.graph, Vector3(-8, 0, 0))
		line(app.graph, Vector3(0, 0, -8), -PI / 2)
		a = sim.add_train(["core:diesel", "core:coach"], "1:0", 9.5)
		b = sim.add_train(["core:electric", "core:freight"], "2:0", 5.0)
	check(not a.is_empty() and not b.is_empty(), "侧撞场景允许合法放置两列车")
	if a.is_empty() or b.is_empty():
		return
	drive(a, 16 if turnout else 0)
	drive(b, 20)
	check(until_contact(sim, a, b), "道岔并轨碰撞" if turnout else "十字交叉侧面碰撞")
	if not a.has("derailed_cars"):
		return
	var start = sim.car_samples(a)[0].position
	app.rebuild_rails()
	app.derailment.sync(sim)
	check(app.derailment.consists[a.id].bodies.size() == 2 and app.derailment.consists[b.id].bodies.size() == 2, "碰撞整列交接，保留车钩连接")
	app.set_physics_process(true)
	var max_rotation = 0.0
	for i in 180:
		await frames(app, 1)
		for train in [a, b]:
			for pose in train.derailed_cars:
				max_rotation = maxf(max_rotation, RailGraph.array_v(pose.angular).length())
	check(max_rotation > 0.05, "偏心撞击产生角速度")
	check(absf(sim.car_samples(a)[0].position.z - start.z) > 0.05, "侧向碰撞产生横向位移")
	check(app.validate_snapshot(app.snapshot()).is_empty(), "碰撞后速度与姿态保持有限且可存档")
	if capture:
		sim.paused = true
		app.camera_target = (sim.car_samples(a)[0].position + sim.car_samples(b)[0].position) * 0.5
		app.camera_distance = 16
		app.camera_yaw = -0.65
		app.camera_pitch = 0.8
		app.set_mode("operate")
		app.update_camera()
		await app.get_tree().process_frame
		await RenderingServer.frame_post_draw
		app.get_viewport().get_texture().get_image().save_png("res://screenshots/collision-" + ("merge" if turnout else "crossing") + ".png")
	app.set_physics_process(false)

func rear_and_wreck_tests(app) -> void:
	for speed in [1.0, 12.0]:
		var sim = setup(app)
		line(app.graph, Vector3(-12, 0, 0))
		line(app.graph, Vector3.ZERO)
		var rear = sim.add_train(["core:diesel"], "1:0", 11.8)
		var lead = sim.add_train(["core:electric"], "2:0", 2.3)
		drive(rear, speed)
		check(until_contact(sim, rear, lead), "追尾接触 %.1f m/s" % speed)
		if not lead.has("derailed_cars"):
			continue
		app.rebuild_rails()
		app.derailment.sync(sim)
		app.set_physics_process(true)
		await frames(app, 10)
		check(RailGraph.array_v(lead.derailed_cars[0].linear).x > speed * 10.0 / sim.ratio() * 0.2, "追尾冲量推动原本静止的前车")
		check(RailGraph.array_v(rear.derailed_cars[0].linear).x < speed * 10.0 / sim.ratio() * 0.8, "后车因追尾减速")
		app.set_physics_process(false)
	var sim = setup(app)
	line(app.graph, Vector3(-12, 0, 0))
	line(app.graph, Vector3.ZERO)
	var a = sim.add_train(["core:diesel"], "2:0", 4)
	var b = sim.add_train(["core:electric"], "1:0", 10)
	drive(a, -20)
	check(until_contact(sim, a, b) and RailGraph.array_v(a.derailed_cars[0].linear).x < 0, "倒车以车尾撞击时保留负向惯性")
	# A moving wreck must also release an on-rail train that never moved.
	setup(app)
	line(app.graph, Vector3(-6, 0, 0))
	line(app.graph, Vector3(0.5, 0, -6), -PI / 2)
	a = sim.add_train(["core:diesel"], "1:0", 7)
	b = sim.add_train(["core:electric"], "2:0", 4)
	drive(b, 80)
	sim.derail(b)
	app.rebuild_rails()
	app.derailment.sync(sim)
	app.set_physics_process(true)
	for i in 90:
		await frames(app, 1)
		if a.has("derailed_cars"):
			break
	check(a.has("derailed_cars"), "移动残骸撞上静止在轨列车触发连环碰撞")
	if a.has("derailed_cars"):
		await frames(app, 12)
		check(RailGraph.array_v(a.derailed_cars[0].linear).length() > 0.1, "连环碰撞继续传递冲量")
	app.set_physics_process(false)
