class_name RailFlexTrack
extends RefCounted

# World units are 100 model millimetres. Curves are baked once and shared by
# rendering, topology, collision, terrain and train sampling.
const SHAPES = ["straight", "arc", "s", "transition", "bezier"]
const MAX_GRADE = 0.08
const MIN_RADIUS = 0.8

static func settings(definition: Dictionary, overrides: Dictionary = {}) -> Dictionary:
	var result = {"length_mm":definition.get("length_mm", 460.0), "radius_mm":definition.get("radius_mm", 550.0), "angle_deg":definition.get("angle_deg", 45.0), "offset_mm":definition.get("offset_mm", 100.0)}
	result.merge(overrides, true)
	return result

static func valid_number(value, low: float, high: float) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and value >= low and value <= high

static func validate_options(shape: String, options: Dictionary) -> bool:
	if not shape in SHAPES:
		return false
	if shape == "bezier":
		var controls = options.get("controls")
		if not controls is Array or controls.size() != 4:
			return false
		for p in controls:
			if not p is Array or p.size() != 3 or not p.all(func(v): return valid_number(v, -200, 200)):
				return false
		return Vector3(controls[0][0], controls[0][1], controls[0][2]).length() < 0.0001
	for spec in [["length_mm",10,2000], ["radius_mm",80,5000], ["angle_deg",1,180], ["offset_mm",-1000,1000]]:
		if options.has(spec[0]) and not valid_number(options[spec[0]], spec[1], spec[2]):
			return false
	return not options.has("controls")

static func bake(shape: String, options: Dictionary, grade: float = 0.0) -> PackedVector3Array:
	if shape == "bezier":
		var c = options.controls
		return bezier(Vector3(c[0][0], c[0][1], c[0][2]), Vector3(c[1][0], c[1][1], c[1][2]), Vector3(c[2][0], c[2][1], c[2][2]), Vector3(c[3][0], c[3][1], c[3][2]))
	var length: float = options.length_mm / 100.0
	var radius: float = options.radius_mm / 100.0
	var angle = deg_to_rad(float(options.angle_deg))
	if shape == "arc":
		length = radius * angle
	var steps = clampi(ceili(length / 0.04), 16, 4096)
	var points = PackedVector3Array()
	var point = Vector3.ZERO
	var distance = 0.0
	for i in range(steps + 1):
		var t = float(i) / steps
		var next = Vector3(length * t, 0, 0)
		if shape == "arc":
			next = Vector3(sin(angle * t) * radius, 0, (1.0 - cos(angle * t)) * radius)
		elif shape == "s":
			# Quintic smoothstep gives zero lateral curvature at both joins.
			next.z = options.offset_mm / 100.0 * (t * t * t * (10.0 + t * (-15.0 + 6.0 * t)))
		elif shape == "transition" and i > 0:
			# Euler spiral: curvature grows linearly from zero to 1 / radius.
			var middle = (i - 0.5) * length / steps
			var heading = middle * middle / (2.0 * length * radius)
			next = point + Vector3(cos(heading), 0, sin(heading)) * length / steps
		if i > 0:
			distance += Vector2(next.x - point.x, next.z - point.z).length()
		point = next
		points.append(Vector3(next.x, grade * distance, next.z))
	return points

static func bezier(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> PackedVector3Array:
	var steps = clampi(ceili((a.distance_to(b) + b.distance_to(c) + c.distance_to(d)) / 0.04), 24, 4096)
	var points = PackedVector3Array()
	for i in range(steps + 1):
		var t = float(i) / steps
		var u = 1.0 - t
		points.append(a * u * u * u + b * 3.0 * u * u * t + c * 3.0 * u * t * t + d * t * t * t)
	return points

static func radii(points: PackedVector3Array) -> PackedFloat64Array:
	var result = PackedFloat64Array()
	result.resize(points.size())
	for i in range(1, points.size() - 1):
		var a = Vector2(points[i].x - points[i - 1].x, points[i].z - points[i - 1].z)
		var b = Vector2(points[i + 1].x - points[i].x, points[i + 1].z - points[i].z)
		var cross = absf(a.cross(b))
		# Very nearly collinear samples are straight for lateral-force purposes.
		if cross > a.length() * b.length() * 0.00002:
			result[i] = a.length() * b.length() * (a + b).length() / (2.0 * cross)
	if points.size() > 2:
		result[0] = result[1]
		result[-1] = result[-2]
	return result

static func measure(points: PackedVector3Array, width: float = 200, depth: float = 200, minimum_radius: float = MIN_RADIUS) -> Dictionary:
	var length = 0.0
	var max_grade = 0.0
	var min_radius = INF
	var error = ""
	var sampled_radii = radii(points)
	for i in points.size():
		var p = points[i]
		if not p.is_finite() or absf(p.x) > width * 0.5 - 0.2 or absf(p.z) > depth * 0.5 - 0.2 or p.y < -0.8 or p.y > 4.0:
			error = "曲线超出沙盘范围或高程范围（−80～400 mm）"
		if sampled_radii[i] > 0:
			min_radius = minf(min_radius, sampled_radii[i])
		if i == 0:
			continue
		var delta = p - points[i - 1]
		var horizontal = Vector2(delta.x, delta.z).length()
		length += delta.length()
		if horizontal < 0.00001:
			error = "端点过近或曲线出现折返尖点"
		max_grade = maxf(max_grade, absf(delta.y) / maxf(horizontal, 0.000001))
	if error.is_empty() and max_grade > MAX_GRADE + 0.0001:
		error = "所需坡度 %.1f%% 超过 8%%，请加大间距或减小高差" % (max_grade * 100)
	if error.is_empty() and min_radius < minimum_radius * 0.995:
		error = "弯曲半径仅 %.0f mm，小于设定的 %.0f mm" % [min_radius * 100, minimum_radius * 100]
	if error.is_empty() and length < 0.1:
		error = "端点距离太近，柔轨至少需要 10 mm 长度"
	return {"error":error, "length":length, "min_radius":min_radius, "max_grade":max_grade}

static func self_crosses(points: PackedVector3Array) -> bool:
	# A coarser polyline suffices to reject loops; retain the exact final point.
	var coarse: Array[Vector2] = []
	var stride = maxi(1, ceili(points.size() / 160.0))
	for i in range(0, points.size() - 1, stride):
		coarse.append(Vector2(points[i].x, points[i].z))
	coarse.append(Vector2(points[-1].x, points[-1].z))
	for i in range(coarse.size() - 1):
		for j in range(i + 2, coarse.size() - 1):
			if Geometry2D.segment_intersects_segment(coarse[i], coarse[i + 1], coarse[j], coarse[j + 1]) != null:
				return true
	return false

static func connect_endpoints(start: Dictionary, finish: Dictionary, width: float, depth: float, minimum_radius: float) -> Dictionary:
	var a: Vector3 = start.position
	var d: Vector3 = finish.position
	var distance = a.distance_to(d)
	if distance < 0.1:
		return {"error":"请选择两个不同且相距至少 10 mm 的开放端点"}
	var best = {}
	var failed = {}
	var best_score = INF
	var failed_score = INF
	# Search asymmetric handles too: offset tracks and differing endpoint grades
	# often cannot be joined well with equal handle lengths.
	for left in [0.15, 0.25, 0.333333, 0.5, 0.75, 1.0, 1.5]:
		for right in [0.15, 0.25, 0.333333, 0.5, 0.75, 1.0, 1.5]:
			var b: Vector3 = a + start.out * distance * left
			var c: Vector3 = d + finish.out * distance * right
			var points = bezier(a, b, c, d)
			var result = measure(points, width, depth, minimum_radius)
			if (points[1] - points[0]).normalized().dot(start.out) < 0.995 or (points[-2] - points[-1]).normalized().dot(finish.out) < 0.995:
				result.error = "端点朝向无法平顺衔接，请调整位置或方向"
			var score: float = result.length + (0.0 if is_inf(result.min_radius) else minimum_radius * minimum_radius / maxf(result.min_radius, 0.001))
			result.points = points
			result.controls = [[0.0,0.0,0.0], [b.x-a.x,b.y-a.y,b.z-a.z], [c.x-a.x,c.y-a.y,c.z-a.z], [d.x-a.x,d.y-a.y,d.z-a.z]]
			if result.error.is_empty() and score < best_score:
				if self_crosses(points):
					result.error = "无法找到不自交的平滑曲线，请调整端点朝向或间距"
				else:
					best = result
					best_score = score
			if not result.error.is_empty() and score < failed_score:
				failed = result
				failed_score = score
	return best if not best.is_empty() else failed
