class_name RailSceneFormat
extends RefCounted

const MAX_CAMERA_DISTANCE = 300.0

static func number(value, low: float, high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= low and float(value) <= high

static func integer(value, low: int, high: int) -> bool:
	return number(value, low, high) and float(value) == floorf(float(value))

static func vector(value, bound: float = 1000.0) -> bool:
	return value is Array and value.size() == 3 and value.all(func(n): return number(n, -bound, bound))

static func validate(data: Dictionary, catalog: RailCatalog) -> String:
	if data.get("format", "") != "track-playground" or data.get("version", 0) != 1 or not RailCatalog.SCALES.has(data.get("scale", "")):
		return "格式或版本不支持"
	for key in ["parts", "scenery", "terrain", "paint", "trains"]:
		if not data.get(key) is Array:
			return "缺少数据：" + key
	if data.parts.size() > 1000 or data.scenery.size() > 5000 or data.trains.size() > 64:
		return "场景超过零件、布景或列车数量限制"
	# Older version 1 scenes have no sandbox field and use the original size.
	var sandbox = data.get("sandbox", {"width":RailTerrain.WIDTH, "depth":RailTerrain.DEPTH})
	if not sandbox is Dictionary or not number(sandbox.get("width"), RailTerrain.MIN_SIZE, RailTerrain.MAX_SIZE) or not number(sandbox.get("depth"), RailTerrain.MIN_SIZE, RailTerrain.MAX_SIZE):
		return "沙盘尺寸不正确"
	var grid = RailTerrain.grid_size(sandbox.width, sandbox.depth)
	if data.terrain.size() != grid.x * grid.y or data.paint.size() != grid.x * grid.y:
		return "地形尺寸不正确"
	for v in data.terrain:
		if not number(v, -0.801, 4.001):
			return "地形高度数据不合法"
	for v in data.paint:
		if not number(v, 0.0, 1.0):
			return "地形涂层数据不合法"
	var uids = {}
	var max_part = 0
	for p in data.parts:
		if not p is Dictionary or not catalog.tracks.has(p.get("definition", "")):
			return "轨道定义缺失，请安装场景使用的 Mod"
		if catalog.tracks[p.definition].scale != data.scale:
			return "场景包含不同轨距的轨道"
		if not vector(p.get("position"), 100) or not number(p.get("yaw"), -10000, 10000) or not integer(p.get("uid"), 1, 10000000) or uids.has(p.get("uid")):
			return "轨道位置、角度或 ID 不正确"
		if not number(p.get("grade", 0), -0.08, 0.08) or not p.get("mirror", false) is bool or not integer(p.get("branch", 0), 0, 1):
			return "轨道坡度或道岔参数不正确"
		if catalog.tracks[p.definition].kind != "turnout" and p.get("branch", 0) != 0:
			return "非道岔零件不能指定侧股"
		var definition: Dictionary = catalog.tracks[p.definition]
		if definition.kind == "flex":
			if not p.get("flex", {}) is Dictionary or not RailFlexTrack.validate_options(definition.shape, p.get("flex", {})):
				return "柔性轨道参数或控制点不正确"
			var points = RailGraph.new(catalog).part_paths(p)[0]
			var measured = RailFlexTrack.measure(points, sandbox.width, sandbox.depth)
			if not measured.error.is_empty():
				return "柔性轨道不合法：" + measured.error
			if RailFlexTrack.self_crosses(points):
				return "柔性轨道不能自交"
		uids[p.uid] = true
		max_part = maxi(max_part, int(p.uid))
	if not integer(data.get("next_part"), max_part + 1, 10000001):
		return "轨道 ID 计数器不正确"
	for item in data.scenery:
		if not item is Dictionary or not catalog.scenery.has(item.get("definition", "")) or not vector(item.get("position"), 100) or not number(item.get("yaw", 0), -10000, 10000):
			return "布景定义或位置缺失"
	var train_ids = {}
	var max_train = 0
	for t in data.trains:
		if not t is Dictionary or not t.get("cars") is Array or t.cars.is_empty() or t.cars.size() > 24 or not t.get("route") is Array or t.route.is_empty() or t.route.size() > 512:
			return "编组或行车路径数据不正确"
		for id in t.cars:
			if not catalog.vehicles.has(id):
				return "车辆定义缺失，请安装对应 Mod"
		if not t.cars.any(func(id): return catalog.vehicles[id].kind == "locomotive"):
			return "编组缺少机车"
		if not integer(t.get("id"), 1, 10000000) or train_ids.has(t.id) or not t.get("name") is String or not t.get("state") is String or not t.get("fault") is bool:
			return "列车 ID 或状态字段错误"
		for spec in [["s",0,100000],["velocity",-200,200],["target",0,600],["traction",0,100000000],["braking",0,100000000],["grade",-10,10],["distance_m",0,1e12]]:
			if not number(t.get(spec[0]), spec[1], spec[2]):
				return "列车参数不合法：" + spec[0]
		if not number(t.get("direction"), -1, 1) or absf(float(t.direction)) != 1.0 or (t.has("emergency") and not t.emergency is bool):
			return "列车方向或制动状态不正确"
		for entry in t.route:
			if not entry is Dictionary or not entry.get("edge") is String or not entry.get("rev") is bool:
				return "行车路径字段不正确"
		if t.has("derailed_cars"):
			if not t.fault or not t.derailed_cars is Array or t.derailed_cars.size() != t.cars.size():
				return "脱轨车辆数量或状态不正确"
			for pose in t.derailed_cars:
				if not pose is Dictionary or not vector(pose.get("position"), 10000) or not vector(pose.get("linear"), 1000) or not vector(pose.get("angular"), 1000) or not pose.get("sleeping") is bool:
					return "脱轨车辆姿态或速度不正确"
				var rotation = pose.get("rotation")
				if not rotation is Array or rotation.size() != 4 or not rotation.all(func(v): return number(v, -1.001, 1.001)):
					return "脱轨车辆旋转不正确"
				var norm = 0.0
				for v in rotation:
					norm += v * v
				if absf(norm - 1.0) > 0.01:
					return "脱轨车辆旋转未归一化"
		train_ids[t.id] = true
		max_train = maxi(max_train, int(t.id))
	if not integer(data.get("next_train"), max_train + 1, 10000001):
		return "列车 ID 计数器不正确"
	var physics = data.get("physics", {})
	if not physics is Dictionary or not physics.get("wet", false) is bool or not physics.get("derailments", true) is bool:
		return "物理配置格式不正确"
	var cam = data.get("camera", {})
	if not cam is Dictionary or not vector(cam.get("target", [0,0,0])) or not number(cam.get("yaw", 0), -10000, 10000) or not number(cam.get("pitch", 0.88), 0.1, 1.55) or not number(cam.get("distance", 34), 3, MAX_CAMERA_DISTANCE):
		return "相机参数不正确"
	return ""
