extends RefCounted
## Track-constrained running gear. All dimensions here are prototype metres;
## solved poses use world units and the same rail datum as car_samples().

class RouteSampler:
	extends RefCounted
	var graph: RailGraph
	var entries: Array
	var ends = PackedFloat64Array()
	var scale_ratio: float

	func _init(sim, train: Dictionary) -> void:
		graph = sim.graph
		entries = train.route
		scale_ratio = sim.ratio()
		var total = 0.0
		for entry in entries:
			total += graph.edges[entry.edge].length
			ends.append(total)

	func ratio() -> float:
		return scale_ratio

	func sample_route(_train: Dictionary, s: float, extrapolate: bool) -> Dictionary:
		# A truck solver samples repeatedly; avoid rescanning the entire route
		# history at every axle and every constraint iteration.
		var index = mini(ends.bsearch(s), entries.size() - 1)
		var entry: Dictionary = entries[index]
		var d = s - (ends[index - 1] if index > 0 else 0.0)
		var sample = graph.sample(entry.edge, d, entry.rev)
		if extrapolate:
			sample.position += sample.tangent * (minf(s, 0.0) + maxf(s - ends[-1], 0.0))
		return sample

static func layout(def: Dictionary) -> Dictionary:
	if def.id == "core:steam":
		return {} # Coupled driving axles belong to the locomotive's rigid frame.
	if def.id == "core:steam_tender":
		return {"center":2.25, "height":0.90, "axles":[-0.7, 0.7], "radius":0.48}
	if def.has("model_path"):
		return {} # An arbitrary GLB does not expose a running-gear hierarchy.
	var loco: bool = def.kind == "locomotive"
	if def.id in ["core:diesel", "core:electric", "core:coach", "core:freight", "core:tanker", "alpine:mountain_diesel"]:
		return {"center":def.length_m * (0.315 if loco else 0.32), "height":1.07,
			"axles":[-1.55, 0.0, 1.55] if def.id in ["core:diesel", "core:electric"] else [-1.08, 1.08], "radius":0.50 if loco else 0.46}
	return {"center":def.length_m * 0.32, "height":def.height_m * 0.18,
		"axles":[-def.length_m * 0.05, def.length_m * 0.05], "radius":def.height_m * 0.105}

static func frame(direction: Vector3) -> Basis:
	var forward = direction.normalized() if direction.length_squared() > 0.00000001 else Vector3.RIGHT
	var side = forward.cross(Vector3.UP).normalized()
	return Basis(forward, side.cross(forward).normalized(), side)

static func minimum_radius(a: float, b: float) -> float:
	return minf(a, b) if a > 0 and b > 0 else maxf(a, b)

static func truck(sim, train: Dictionary, s: float, spec: Dictionary, factor: float, extrapolate: bool) -> Dictionary:
	var half: float = spec.axles[-1] * factor
	var span = half
	var back: Dictionary
	var front: Dictionary
	# The axle spacing is a chord, not an arc length. Keep the actual rigid
	# wheelbase while placing the outer wheelsets on the sampled rail centreline.
	for iteration in 5:
		back = sim.sample_route(train, s - span, extrapolate)
		front = sim.sample_route(train, s + span, extrapolate)
		var distance: float = back.position.distance_to(front.position)
		if absf(distance - 2.0 * half) < 0.000002 or distance < 0.000001:
			break
		if iteration < 4:
			span = minf(span * 2.0 * half / distance, half * 1.5)
	var basis = frame(front.position - back.position)
	var pivot: Vector3 = (front.position + back.position) * 0.5 + basis.y * spec.height * factor
	return {"pose":Transform3D(basis, pivot), "radius":minimum_radius(front.radius, back.radius),
		"fit":absf(back.position.distance_to(front.position) - 2.0 * half) < 0.00005}

static func sample(sim, train: Dictionary, s: float, def: Dictionary, extrapolate: bool) -> Dictionary:
	var spec = layout(def)
	if spec.is_empty():
		return {}
	var factor: float = 10.0 / sim.ratio()
	var half: float = spec.center * factor
	var span = half
	var back: Dictionary
	var front: Dictionary
	# Solve the fixed distance between body bolster pins. Simply sampling at
	# +/- the body wheelbase shortens that distance on a curve and detaches pins.
	var limit: float = (def.length_m * 0.5 - spec.axles[-1]) * factor
	for iteration in 10:
		back = truck(sim, train, s - span, spec, factor, extrapolate)
		front = truck(sim, train, s + span, spec, factor, extrapolate)
		var distance: float = back.pose.origin.distance_to(front.pose.origin)
		if absf(distance - 2.0 * half) < 0.000002 or distance < 0.000001:
			break
		if iteration < 9:
			span = minf(span * 2.0 * half / distance, limit)
	var basis = frame(front.pose.origin - back.pose.origin)
	var position: Vector3 = (front.pose.origin + back.pose.origin) * 0.5 - basis.y * spec.height * factor
	var fit: bool = back.fit and front.fit and absf(back.pose.origin.distance_to(front.pose.origin) - 2.0 * half) < 0.00005
	return {"position":position, "tangent":basis.x, "basis":basis, "vehicle":def.id,
		"radius":minimum_radius(back.radius, front.radius), "bogies":[back.pose, front.pose], "bogie_fit":fit}

static func add_pivot(root: Node3D, parent: Node3D, center: float, height: float, factor: float) -> Node3D:
	var pivot = Node3D.new()
	pivot.name = "BogiePivot"
	pivot.position = Vector3(center, height, 0)
	parent.add_child(pivot)
	var entries: Array = root.get_meta("bogie_nodes", [])
	entries.append({"node":pivot, "rest":pivot.transform, "factor":factor})
	root.set_meta("bogie_nodes", entries)
	return pivot

static func apply(root: Node3D, sample: Dictionary) -> void:
	var entries: Array = root.get_meta("bogie_nodes", [])
	for i in entries.size():
		var entry: Dictionary = entries[i]
		if sample.has("bogies"):
			var pose: Transform3D = sample.bogies[i]
			pose.origin += Vector3.UP * 0.08
			var local = root.transform.affine_inverse() * pose
			local.origin /= entry.factor
			entry.node.transform = local
		else:
			entry.node.transform = entry.rest
			var rotations: Array = sample.get("bogie_rotations", [])
			if i < rotations.size():
				var q: Array = rotations[i]
				entry.node.basis = Basis(Quaternion(q[0], q[1], q[2], q[3]))

static func rotations(sample: Dictionary) -> Array:
	var result = []
	for pose in sample.get("bogies", []):
		var q: Quaternion = (sample.basis.inverse() * pose.basis).get_rotation_quaternion()
		result.append([q.x, q.y, q.z, q.w])
	return result
