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

func junction(catalog: RailCatalog, scale_name: String, mirrored: bool = false) -> RailGraph:
	var graph = RailGraph.new(catalog)
	graph.scale_name = scale_name
	var prefix = "core:" + scale_name + ":"
	graph.add_part(prefix + "flex_straight", Vector3(-12, 0, 0), 0, 0, false, {"length_mm":1200.0})
	graph.add_part(prefix + "turnout", Vector3.ZERO, 0, 0, mirrored)
	for branch in [0, 1]:
		var end = graph.endpoint("2:" + str(branch), 1)
		graph.add_part(prefix + "flex_straight", end.position, atan2(-end.out.z, end.out.x), 0, false, {"length_mm":1200.0})
	return graph

func cached_train(sim: RailSimulation, backwards: bool = false) -> Dictionary:
	var train = sim.add_train(["core:diesel", "core:coach", "core:coach"], "1:0", 10.5)
	# Reproduce a saved/precomputed straight route beyond the actual train.
	train.route = [{"edge":"1:0", "rev":false}, {"edge":"2:0", "rev":false}, {"edge":"3:0", "rev":false}]
	train.s = 10.5
	if backwards:
		train.route.reverse()
		for entry in train.route:
			entry.rev = true
		train.s = sim.route_length(train) - 10.5 + sim.consist_length(train.cars)
		train.direction = -1
	return train

func same_poses(before: Array, after: Array) -> bool:
	for i in before.size():
		if before[i].position.distance_to(after[i].position) > 0.0001 or before[i].tangent.distance_to(after[i].tangent) > 0.0001:
			return false
	return true

func test_motion(catalog: RailCatalog, scale_name: String, mirrored: bool, backwards: bool) -> void:
	var graph = junction(catalog, scale_name, mirrored)
	var sim = RailSimulation.new(graph, catalog)
	var train = cached_train(sim, backwards)
	graph.parts[1].branch = 1
	var before = sim.car_samples(train)
	# A stationary tick also refreshes cached history in the reverse direction.
	sim.tick(1.0 / 60.0)
	check(same_poses(before, sim.car_samples(train)), "刷新道岔路线保持所有车辆位置与朝向")
	train.target = 12
	var used_siding = false
	var used_straight = false
	var clear_switch = false
	var max_jump = 0.0
	for i in 60 * 90:
		var old = sim.car_samples(train)
		sim.tick(1.0 / 60.0)
		var poses = sim.car_samples(train)
		for j in poses.size():
			max_jump = maxf(max_jump, poses[j].position.distance_to(old[j].position))
		var occupied = sim.occupancy(train)
		used_siding = used_siding or occupied.has("2:1")
		used_straight = used_straight or occupied.has("2:0")
		if train.fault:
			break
		if used_siding and not sim.occupied_part(2):
			clear_switch = true
			break
	check(used_siding and not used_straight and clear_switch and not train.fault and max_jump < 0.02,
		"%s 镜像=%s 倒车=%s：旧直股路线失效，整列连续通过侧股" % [scale_name, mirrored, backwards])

func test_occupied(catalog: RailCatalog) -> void:
	var graph = junction(catalog, "HO")
	var sim = RailSimulation.new(graph, catalog)
	var train = cached_train(sim)
	train.s = 12.4
	graph.parts[1].branch = 1
	var before = sim.car_samples(train)
	sim.ensure_route(train)
	check(sim.occupied_part(2) and sim.occupancy(train).has("2:0") and same_poses(before, sim.car_samples(train)), "已占用道岔仍锁定并保留整列车的原路径")
	train.velocity = 0.0
	check(sim.reverse(train), "占用道岔时可停车换向")
	train.target = 10
	for i in 60 * 15:
		sim.tick(1.0 / 60.0)
	check(not train.fault and not sim.occupancy(train).has("2:1"), "未驶离道岔即倒车，车厢继续沿原直股退回")
	# A trailing move through an unselected branch must still merge normally.
	var trailing = graph.next_edge({"edge":"3:0", "rev":true})
	check(trailing.get("edge") == "2:0" and trailing.rev, "顺岔合流不受另一分支选择影响")
	var wreck = cached_train(RailSimulation.new(graph, catalog))
	wreck.derailed_cars = []
	var recovery = wreck.route.duplicate(true)
	sim.refresh_route(wreck)
	check(wreck.route == recovery, "脱轨列车保留原始复位路线")

func test_load(app) -> void:
	app.empty_scene(false)
	var graph = junction(app.catalog, "HO")
	var sim = RailSimulation.new(graph, app.catalog)
	var train = cached_train(sim)
	graph.parts[1].branch = 1
	var before = sim.car_samples(train)
	var saved = app.snapshot()
	saved.scale = "HO"
	saved.parts = graph.parts.duplicate(true)
	saved.next_part = graph.next_uid
	saved.trains = sim.trains.duplicate(true)
	saved.next_train = sim.next_uid
	check(app.apply_snapshot(JSON.parse_string(JSON.stringify(saved))), "含过期直股路线的旧格式存档可载入")
	var loaded: Dictionary = app.simulation.trains[0]
	check(app.simulation.paused and loaded.route.size() == 1 and same_poses(before, app.simulation.car_samples(loaded)), "读档自动清除未驶入的旧路线且保持暂停与逐车姿态")
	check(saved.trains[0].route.size() == 3, "载入修复不会改写原始存档数据")
	var roundtrip = JSON.parse_string(JSON.stringify(app.snapshot()))
	check(app.apply_snapshot(roundtrip), "修复后的路线可再次保存和载入")

func run(app) -> int:
	for scale_name in ["HO", "N"]:
		for mirrored in [false, true]:
			for backwards in [false, true]:
				test_motion(app.catalog, scale_name, mirrored, backwards)
	test_occupied(app.catalog)
	test_load(app)
	print("TURNOUT ROUTING: %d checks, %d failures" % [checks, failures])
	var report = FileAccess.open("res://test-results/turnout-routing.json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks, "failures":failures}, "  "))
	return failures
