class_name RailSimulation
extends RefCounted

signal train_event(train_id: int, message: String)
signal train_added(train: Dictionary)
signal train_removed(train_id: int)

var graph: RailGraph
var catalog: RailCatalog
var trains: Array = []
var next_uid = 1
var paused = false
var wet_rails = false
var derailments = true

func _init(g: RailGraph, c: RailCatalog) -> void:
	graph = g
	catalog = c

func ratio() -> float:
	return RailCatalog.SCALES[graph.scale_name].ratio

func vehicle_length(id: String) -> float:
	return (catalog.vehicles[id].length_m + 0.7) * 10.0 / ratio()

func consist_length(cars: Array) -> float:
	var length = 0.0
	for id in cars:
		length += vehicle_length(id)
	return length

func train_placement(cars: Array, edge: String, distance: float, reversed: bool = false, title: String = "") -> Dictionary:
	# Build and validate without changing trains, IDs or emitting signals. The
	# hover preview and the final click must use exactly the same placement rules.
	var result = {"train":{}, "error":""}
	if cars.is_empty():
		result.error = "请先向编组添加车辆"
		return result
	if not graph.edges.has(edge) or not is_finite(distance):
		result.error = "请将鼠标移到轨道上"
		return result
	for id in cars:
		if not catalog.vehicles.has(id):
			result.error = "编组中有不可用的车辆"
			return result
	var s = clampf(distance, 0.0, graph.edges[edge].length)
	if reversed:
		s = graph.edges[edge].length - s
	var train = {"id":next_uid, "name":title if not title.is_empty() else "编组 %02d" % next_uid, "cars":cars.duplicate(), "route":[{"edge":edge, "rev":reversed}], "s":s, "velocity":0.0, "target":0.0, "direction":1, "state":"就绪", "fault":false, "traction":0.0, "braking":0.0, "grade":0.0, "distance_m":0.0}
	ensure_route(train)
	result.train = train
	if cars.size() > 24:
		result.error = "每个编组最多 24 辆车辆"
		return result
	if trains.size() >= 64:
		result.error = "场景最多容纳 64 个编组"
		return result
	if not cars.any(func(id): return catalog.vehicles[id].kind == "locomotive"):
		result.error = "编组至少需要一辆机车"
		return result
	if train.s < consist_length(cars) + 0.04:
		result.error = "车尾方向的轨道长度不足"
		return result
	var occupied = occupancy(train)
	for intervals in occupied.values():
		for i in intervals.size():
			for j in range(i + 1, intervals.size()):
				if minf(intervals[i].y, intervals[j].y) > maxf(intervals[i].x, intervals[j].x) + 0.005:
					result.error = "编组过长，在环线上与自身重叠"
					return result
	for existing in trains:
		if overlaps(train, existing):
			result.error = "放置位置与已有列车重叠"
			return result
	return result

func add_train(cars: Array, edge: String, distance: float, title: String = "", reversed: bool = false) -> Dictionary:
	var result = train_placement(cars, edge, distance, reversed, title)
	if not result.error.is_empty():
		return {}
	var train: Dictionary = result.train
	next_uid += 1
	trains.append(train)
	train_added.emit(train)
	return train

func route_length(train: Dictionary) -> float:
	var length = 0.0
	for entry in train.route:
		if graph.edges.has(entry.edge):
			length += graph.edges[entry.edge].length
	return length

func ensure_route(train: Dictionary) -> void:
	refresh_route(train)
	var needed = consist_length(train.cars) + 3.0
	var count = 0
	while train.s < needed and count < 200:
		var first: Dictionary = train.route[0]
		var previous = graph.next_edge({"edge":first.edge, "rev":not first.rev})
		if previous.is_empty():
			break
		previous.rev = not previous.rev
		train.route.push_front(previous)
		train.s += graph.edges[previous.edge].length
		count += 1
	# Only commit a turnout once the leading vehicle reaches it. The whole
	# consist then follows this recorded path, including when reversing.
	count = 0
	while train.s > route_length(train) - 0.02 and count < 100:
		var following = graph.next_edge(train.route[-1])
		if following.is_empty():
			break
		train.route.append(following)
		count += 1
	while train.route.size() > 160 and train.s - consist_length(train.cars) > graph.edges[train.route[0].edge].length + 5.0:
		train.s -= graph.edges[train.route.pop_front().edge].length
	while train.route.size() > 160 and route_length(train) - train.s > graph.edges[train.route[-1].edge].length + 5.0:
		train.route.pop_back()

func refresh_route(train: Dictionary) -> void:
	if train.has("derailed_cars"):
		return
	# Saved routes and reversing can leave many unoccupied entries on either
	# side of a train. Recheck facing turnouts there, but never change the path
	# beneath any vehicle (including a trailing move through a different branch).
	var tail = train.s - consist_length(train.cars)
	var base = 0.0
	var cut_front = 0
	var cut_back = train.route.size()
	var subtract = 0.0
	for i in train.route.size():
		var entry: Dictionary = train.route[i]
		var edge: Dictionary = graph.edges[entry.edge]
		var end: float = base + edge.length
		if catalog.tracks[edge.part.definition].kind == "turnout" and int(edge.branch) != int(edge.part.get("branch", 0)):
			if entry.rev and end <= tail and i + 1 < train.route.size():
				cut_front = i + 1
				subtract = end
			elif not entry.rev and base >= train.s and i > 0:
				cut_back = mini(cut_back, i)
		base = end
	if cut_front > 0 or cut_back < train.route.size():
		train.route = train.route.slice(cut_front, cut_back)
		train.s -= subtract

func sample_route(train: Dictionary, s: float, extrapolate: bool = false) -> Dictionary:
	var d = s
	for entry in train.route:
		var length: float = graph.edges[entry.edge].length
		if d <= length:
			var sample = graph.sample(entry.edge, d, entry.rev)
			if extrapolate and d < 0.0:
				sample.position += sample.tangent * d
			return sample
		d -= length
	var last: Dictionary = train.route[-1]
	return graph.sample(last.edge, graph.edges[last.edge].length, last.rev)

func car_samples(train: Dictionary, extrapolate: bool = false) -> Array:
	var result = []
	if train.has("derailed_cars"):
		for i in train.cars.size():
			var pose: Dictionary = train.derailed_cars[i]
			var basis = Basis(Quaternion(pose.rotation[0], pose.rotation[1], pose.rotation[2], pose.rotation[3]))
			result.append({"position":RailGraph.array_v(pose.position), "tangent":basis.x, "basis":basis, "vehicle":train.cars[i], "radius":0.0})
		return result
	var offset = 0.0
	for id in train.cars:
		var length = vehicle_length(id)
		# Invalid placement previews extend beyond a dead end instead of piling
		# every car up at the endpoint. Running trains keep the clamped behavior.
		var center = sample_route(train, train.s - offset - length * 0.5, extrapolate)
		var front = sample_route(train, train.s - offset - length * 0.18, extrapolate)
		var back = sample_route(train, train.s - offset - length * 0.82, extrapolate)
		center.tangent = (front.position - back.position).normalized()
		center.position = (front.position + back.position) * 0.5
		center.vehicle = id
		result.append(center)
		offset += length
	return result

func occupancy(train: Dictionary) -> Dictionary:
	if train.has("derailed_cars"):
		return {}
	var start = train.s - consist_length(train.cars)
	var finish = train.s
	var base = 0.0
	var intervals = {}
	for entry in train.route:
		var length: float = graph.edges[entry.edge].length
		var a = maxf(start, base) - base
		var b = minf(finish, base + length) - base
		if a < b:
			if entry.rev:
				var old_a = a
				a = length - b
				b = length - old_a
			if not intervals.has(entry.edge):
				intervals[entry.edge] = []
			intervals[entry.edge].append(Vector2(a, b))
		base += length
	return intervals

func overlaps(a: Dictionary, b: Dictionary) -> bool:
	var oa = occupancy(a)
	var ob = occupancy(b)
	for edge in oa:
		if ob.has(edge):
			for ia in oa[edge]:
				for ib in ob[edge]:
					if minf(ia.y, ib.y) > maxf(ia.x, ib.x) + 0.005:
						return true
	# Distinct graph edges can occupy the same space at turnouts/crossings.
	for ea in envelopes(a):
		for eb in envelopes(b):
			var points = Geometry3D.get_closest_points_between_segments(ea.a, ea.b, eb.a, eb.b)
			if points[0].distance_squared_to(points[1]) < pow(ea.radius + eb.radius, 2):
				return true
	return false

func envelopes(train: Dictionary) -> Array:
	var result = []
	if train.has("derailed_cars"):
		for sample in car_samples(train):
			var def = catalog.vehicles[sample.vehicle]
			var radius: float = def.width_m * 5.0 / ratio()
			var center: Vector3 = sample.position + sample.basis.y * def.height_m * 5.0 / ratio()
			var half: Vector3 = sample.tangent * maxf(0.0, def.length_m * 5.0 / ratio() - radius)
			result.append({"a":center + half, "b":center - half, "radius":radius})
		return result
	var offset = 0.0
	for id in train.cars:
		var length = vehicle_length(id)
		var def = catalog.vehicles[id]
		var radius: float = def.width_m * 5.0 / ratio()
		var up = Vector3.UP * def.height_m * 5.0 / ratio()
		result.append({"a":sample_route(train, train.s - offset - radius - 0.04).position + up, "b":sample_route(train, train.s - offset - length + radius + 0.04).position + up, "radius":radius})
		offset += length
	return result

func reverse(train: Dictionary) -> bool:
	if train.has("derailed_cars"):
		train_event.emit(train.id, "请先将脱轨列车复位到轨道")
		return false
	if absf(train.velocity) > 0.15:
		train_event.emit(train.id, "请先制动至停车，再切换方向")
		return false
	train.direction *= -1
	train.target = 0.0
	return true

func emergency(train: Dictionary) -> void:
	train.target = 0.0
	train.emergency = true

func reset_train(train: Dictionary) -> bool:
	if train.has("derailed_cars"):
		var candidate = train.duplicate(true)
		candidate.erase("derailed_cars")
		for other in trains:
			if other.id != train.id and overlaps(candidate, other):
				train_event.emit(train.id, "复位位置被其他列车占用，请先移开列车")
				return false
		train.erase("derailed_cars")
	train.fault = false
	train.velocity = 0.0
	train.target = 0.0
	train.emergency = false
	train.state = "就绪"
	return true

func derail(train: Dictionary) -> void:
	# Keep the last valid route position for recovery, and hand each car's
	# pose and momentum to the 3D rigid-body solver. Arrays survive JSON saves.
	var poses = []
	for sample in car_samples(train):
		var tangent: Vector3 = sample.tangent
		var side = tangent.cross(Vector3.UP).normalized()
		var rotation = Basis(tangent, side.cross(tangent).normalized(), side).get_rotation_quaternion()
		poses.append({"position":RailGraph.v_array(sample.position + Vector3.UP * 0.08),
			"rotation":[rotation.x, rotation.y, rotation.z, rotation.w],
			"linear":RailGraph.v_array(tangent * train.velocity * 10.0 / ratio()),
			"angular":[0.0, 0.0, 0.0], "sleeping":false})
	train.derailed_cars = poses
	train.fault = true
	train.target = 0.0
	train.traction = 0.0
	train.braking = 0.0
	train.state = "轨道尽头脱轨 · 可复位上轨"
	train_event.emit(train.id, "列车冲出轨道尽头 · 已进入脱轨物理模拟")

func fault(train: Dictionary, reason: String) -> void:
	if not train.fault:
		train_event.emit(train.id, reason)
	train.fault = true
	train.state = reason
	train.velocity = 0.0
	train.target = 0.0

func tick(dt: float) -> void:
	if paused:
		return
	for train in trains:
		if train.fault:
			continue
		ensure_route(train)
		var total_mass = 0.0
		var driven_mass = 0.0
		var power = 0.0
		var max_force = 0.0
		var max_speed = 600.0
		var slope_force = 0.0
		var max_lateral = 0.0
		for sample in car_samples(train):
			var car: Dictionary = catalog.vehicles[sample.vehicle]
			total_mass += car.mass_kg
			slope_force += car.mass_kg * 9.81 * sample.tangent.y
			max_speed = minf(max_speed, car.max_kmh)
			if car.kind == "locomotive":
				driven_mass += car.mass_kg
				power += car.power_w
				max_force += car.tractive_n
			if sample.radius > 0.0:
				max_lateral = maxf(max_lateral, train.velocity * train.velocity / (sample.radius * ratio() / 10.0))
		var velocity: float = train.velocity
		var speed = absf(velocity)
		var desired = minf(train.target, max_speed) / 3.6 * train.direction
		var error = desired - velocity
		var adhesion = driven_mass * 9.81 * (0.12 if wet_rails else 0.25)
		var traction_cap = minf(minf(max_force, power / maxf(speed, 1.0)), adhesion)
		var acceleration_request = clampf(error * 0.5, -0.8, 0.8)
		var effort = acceleration_request * total_mass + slope_force
		var tractive = 0.0
		var braking = 0.0
		if effort * train.direction > 0 and not bool(train.get("emergency", false)) and train.target > 0:
			tractive = clampf(effort, -traction_cap, traction_cap)
		else:
			braking = minf(absf(effort), total_mass * (1.2 if bool(train.get("emergency", false)) else 0.75))
		if bool(train.get("emergency", false)):
			braking = total_mass * 1.2
		var resistance = total_mass * 9.81 * (0.0015 + 0.00002 * speed) + 0.5 * 1.225 * 8.0 * speed * speed
		var force = tractive - slope_force
		if speed < 0.015 and absf(force) <= resistance + braking:
			velocity = 0.0
		else:
			var moving_sign = signf(velocity) if speed > 0.001 else signf(force)
			var next_velocity = velocity + (force - moving_sign * (resistance + braking)) / total_mass * dt
			if velocity * next_velocity < 0 and absf(force) < resistance + braking:
				next_velocity = 0.0
			velocity = next_velocity
		train.traction = absf(tractive)
		train.braking = braking
		train.grade = slope_force / (total_mass * 9.81) * 100.0
		train.velocity = velocity
		if derailments and max_lateral > 1.8 and speed > 2.0:
			fault(train, "弯道超速 · 脱轨保护")
			continue
		var movement: float = velocity * dt * 10.0 / ratio()
		train.s += movement
		ensure_route(train)
		var old_s: float = train.s - movement
		var remaining = route_length(train)
		if train.s >= remaining - 0.005:
			train.s = remaining - 0.006
			if derailments:
				fault(train, "到达轨道尽头")
			else:
				derail(train)
		elif train.s - consist_length(train.cars) <= 0.005:
			train.s = consist_length(train.cars) + 0.006
			if derailments:
				fault(train, "到达轨道尽头")
			else:
				derail(train)
		else:
			for other in trains:
				if train.id != other.id and overlaps(train, other):
					# Undo the substep so stopped rolling stock never interpenetrates.
					train.s = old_s
					fault(train, "列车接触 · 已停车")
					fault(other, "列车接触 · 已停车")
					break
		train.distance_m += absf(velocity) * dt
		if not train.fault:
			train.state = "运行中" if absf(velocity) > 0.05 else "已停车"
			if train.get("emergency", false) and absf(velocity) < 0.01:
				train.emergency = false

func occupied_part(uid: int) -> bool:
	for train in trains:
		# Recovery still needs the original route, even after the wreck falls away.
		if train.has("derailed_cars"):
			for entry in train.route:
				if int(graph.edges[entry.edge].part.uid) == uid:
					return true
		for edge in occupancy(train):
			if int(graph.edges[edge].part.uid) == uid:
				return true
	return false

func remove_train(uid: int) -> void:
	trains = trains.filter(func(t): return t.id != uid)
	train_removed.emit(uid)

func reconfigure(train: Dictionary, cars: Array) -> bool:
	if train.has("derailed_cars") or absf(train.velocity) > 0.05 or cars.is_empty() or cars.size() > 24:
		return false
	for id in cars:
		if not catalog.vehicles.has(id):
			return false
	if not cars.any(func(id): return catalog.vehicles[id].kind == "locomotive"):
		return false
	var candidate = train.duplicate(true)
	candidate.cars = cars.duplicate()
	ensure_route(candidate)
	if candidate.s < consist_length(cars) + 0.005:
		return false
	for intervals in occupancy(candidate).values():
		for i in intervals.size():
			for j in range(i + 1, intervals.size()):
				if minf(intervals[i].y, intervals[j].y) > maxf(intervals[i].x, intervals[j].x) + 0.005:
					return false
	for other in trains:
		if other.id != train.id and overlaps(candidate, other):
			return false
	train.merge(candidate, true)
	reset_train(train)
	return true
