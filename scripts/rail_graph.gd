class_name RailGraph
extends RefCounted

var parts: Array = []
var edges: Dictionary = {}
var connections: Dictionary = {}
var catalog: RailCatalog
var scale_name: String = "HO"
var next_uid: int = 1
const SNAP_DISTANCE = 0.15

func _init(c: RailCatalog) -> void:
	catalog = c

static func array_v(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))

static func v_array(v: Vector3) -> Array:
	return [v.x, v.y, v.z]

func make_paths(definition: Dictionary, origin: Vector3, yaw: float, grade: float = 0.0, mirror: bool = false, options: Dictionary = {}) -> Array:
	if definition.kind == "flex":
		var points = RailFlexTrack.bake(definition.shape, RailFlexTrack.settings(definition, options), grade)
		for i in points.size():
			var p = points[i]
			if mirror:
				p.z = -p.z
			points[i] = origin + p.rotated(Vector3.UP, yaw)
		return [points]
	var paths: Array = []
	var variants = ["straight", "curve"] if definition.kind == "turnout" else [definition.kind]
	for kind in variants:
		var pts = PackedVector3Array()
		var length: float = float(definition.get("length_mm", 230.0)) / 100.0
		var radius: float = float(definition.get("radius_mm", 430.0)) / 100.0
		var angle: float = deg_to_rad(float(definition.get("angle_deg", 30.0)))
		if kind == "curve":
			length = radius * angle
		var steps = maxi(4, ceili(length / 0.09))
		for i in range(steps + 1):
			var t = float(i) / steps
			var p = Vector3(length * t, grade * length * t, 0)
			if kind == "curve":
				p.x = sin(angle * t) * radius
				p.z = (1.0 - cos(angle * t)) * radius * (-1.0 if mirror else 1.0)
			pts.append(origin + p.rotated(Vector3.UP, yaw))
		paths.append(pts)
	return paths

static func placement_endpoints(paths: Array) -> Array:
	# All generated paths share their starting point, including turnouts.
	var first: PackedVector3Array = paths[0]
	var result = [{"position":first[0], "out":(first[0] - first[1]).normalized()}]
	for points in paths:
		result.append({"position":points[-1], "out":(points[-1] - points[-2]).normalized()})
	return result

func part_paths(part: Dictionary) -> Array:
	return make_paths(catalog.tracks[part.definition], array_v(part.position), float(part.yaw), float(part.get("grade", 0.0)), bool(part.get("mirror", false)), part.get("flex", {}))

func add_part(definition: String, pos: Vector3, yaw: float, grade: float = 0.0, mirror: bool = false, options: Dictionary = {}) -> Dictionary:
	var p = {"uid": next_uid, "definition":definition, "position":v_array(pos), "yaw":yaw, "grade":grade, "mirror":mirror, "branch":0}
	if catalog.tracks[definition].kind == "flex":
		p.flex = RailFlexTrack.settings(catalog.tracks[definition], options)
	next_uid += 1
	parts.append(p)
	rebuild()
	return p

func rebuild() -> void:
	edges.clear()
	connections.clear()
	for part in parts:
		var def = catalog.tracks.get(part.definition)
		if def == null:
			continue
		var paths = part_paths(part)
		for branch in paths.size():
			var pts: PackedVector3Array = paths[branch]
			var distances = PackedFloat64Array([0.0])
			for i in range(1, pts.size()):
				distances.append(distances[-1] + pts[i].distance_to(pts[i - 1]))
			var id = str(int(part.uid)) + ":" + str(branch)
			edges[id] = {"id":id, "part":part, "branch":branch, "points":pts, "distances":distances, "length":distances[-1], "radius":float(def.get("radius_mm", 0.0)) / 100.0 if branch == 1 or def.kind == "curve" else 0.0}
			if def.kind == "flex":
				edges[id].radii = RailFlexTrack.radii(pts)
	for id in edges:
		for end in [0, 1]:
			var key = endpoint_key(id, end)
			connections[key] = []
			var ep = endpoint(id, end)
			for other in edges:
				if other == id or edges[id].part.uid == edges[other].part.uid:
					continue
				for oe in [0, 1]:
					var op = endpoint(other, oe)
					if ep.position.distance_to(op.position) < 0.04 and ep.out.dot(op.out) < -0.94:
						connections[key].append({"edge":other, "rev":oe == 1})

func endpoint_key(id: String, end: int) -> String:
	return id + "@" + str(end)

func endpoint(id: String, end: int) -> Dictionary:
	var pts: PackedVector3Array = edges[id].points
	return {"edge":id, "end":end, "position":pts[0] if end == 0 else pts[-1], "out":(pts[0] - pts[1]).normalized() if end == 0 else (pts[-1] - pts[-2]).normalized()}

func next_edge(entry: Dictionary) -> Dictionary:
	var candidates: Array = connections.get(endpoint_key(entry.edge, 0 if entry.rev else 1), [])
	for candidate in candidates:
		var edge = edges[candidate.edge]
		# A facing-point switch chooses a branch; trailing moves merge naturally.
		if not candidate.rev and catalog.tracks[edge.part.definition].kind == "turnout" and int(edge.part.get("branch", 0)) != int(edge.branch):
			continue
		return candidate.duplicate()
	return {}

func sample(id: String, distance: float, reversed: bool = false) -> Dictionary:
	var edge = edges[id]
	var d = clampf(edge.length - distance if reversed else distance, 0.0, edge.length)
	var distances: PackedFloat64Array = edge.distances
	var lo = 0
	var hi = distances.size() - 1
	while hi - lo > 1:
		var mid = (lo + hi) / 2
		if distances[mid] <= d:
			lo = mid
		else:
			hi = mid
	var t = (d - distances[lo]) / maxf(0.00001, distances[hi] - distances[lo])
	var tangent: Vector3 = (edge.points[hi] - edge.points[lo]).normalized() * (-1.0 if reversed else 1.0)
	var radius: float = edge.radius
	if edge.has("radii"):
		# Use local curvature; an S curve's inflection must not hide its bends.
		var r0: float = edge.radii[lo]
		var r1: float = edge.radii[hi]
		radius = maxf(r0, r1) if minf(r0, r1) == 0 else minf(r0, r1)
	return {"position":edge.points[lo].lerp(edge.points[hi], t), "tangent":tangent, "radius":radius, "edge":id, "distance":d}

func is_open_endpoint(ep: Dictionary) -> bool:
	return ep.has("edge") and ep.get("end", -1) in [0, 1] and edges.has(ep.edge) and connections.get(endpoint_key(ep.edge, ep.end), [true]).is_empty()

func plan_connection(start: Dictionary, finish: Dictionary, width: float, depth: float, minimum_radius: float) -> Dictionary:
	if not is_open_endpoint(start) or not is_open_endpoint(finish):
		return {"error":"请选择尚未连接的开放端点"}
	# Refresh geometry instead of trusting stale hover/selection dictionaries.
	return RailFlexTrack.connect_endpoints(endpoint(start.edge, start.end), endpoint(finish.edge, finish.end), width, depth, minimum_radius)

func nearest(pos: Vector3, limit: float = 1.0) -> Dictionary:
	var best = {}
	var best_d = limit
	for id in edges:
		var e = edges[id]
		for i in range(e.points.size() - 1):
			var a: Vector3 = e.points[i]
			var b: Vector3 = e.points[i + 1]
			var t = clampf((pos - a).dot(b - a) / (b - a).length_squared(), 0, 1)
			var hit = a.lerp(b, t)
			var d = hit.distance_to(pos)
			if d < best_d:
				best_d = d
				best = {"edge":id, "distance":lerpf(e.distances[i], e.distances[i + 1], t), "position":hit, "part":e.part}
	return best

func snap(pos: Vector3) -> Dictionary:
	var best = {}
	var distance = 0.7
	for id in edges:
		for end in [0, 1]:
			if not connections[endpoint_key(id, end)].is_empty():
				continue
			var ep = endpoint(id, end)
			var d: float = Vector2(pos.x, pos.z).distance_to(Vector2(ep.position.x, ep.position.z))
			if d < distance:
				distance = d
				best = ep
	return best

func remove_part(uid: int) -> void:
	parts = parts.filter(func(p): return int(p.uid) != uid)
	rebuild()

func open_end_count() -> int:
	var unique: Dictionary = {}
	for id in edges:
		for end in [0, 1]:
			if connections[endpoint_key(id, end)].is_empty():
				var p: Vector3 = endpoint(id, end).position
				unique[str(p.snapped(Vector3.ONE * 0.02))] = true
	return unique.size()
