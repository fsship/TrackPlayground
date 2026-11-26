extends RefCounted

# Use the same oriented boxes and wheel-plane origins as the rigid bodies.
# Capsules alone miss square vehicle corners and cannot distinguish overpasses.
static func boxes(sim: RailSimulation, train: Dictionary) -> Array:
	var result = []
	var factor = 10.0 / sim.ratio()
	for sample in sim.car_samples(train):
		var def: Dictionary = sim.catalog.vehicles[sample.vehicle]
		var basis: Basis
		var origin: Vector3 = sample.position
		if train.has("derailed_cars"):
			basis = sample.basis
		else:
			var side: Vector3 = sample.tangent.cross(Vector3.UP).normalized()
			basis = Basis(sample.tangent, side.cross(sample.tangent).normalized(), side)
			origin += Vector3.UP * 0.08
		var half = Vector3(def.length_m, def.height_m, def.width_m) * factor * 0.5
		result.append({"center":origin + basis.y * half.y, "basis":basis, "half":half})
	return result

static func bounds(cars: Array) -> AABB:
	var result = AABB()
	for i in cars.size():
		var car: Dictionary = cars[i]
		var extent: Vector3 = car.basis.x.abs() * car.half.x + car.basis.y.abs() * car.half.y + car.basis.z.abs() * car.half.z
		var box = AABB(car.center - extent, extent * 2.0)
		result = box if i == 0 else result.merge(box)
	return result

static func radius_on(car: Dictionary, axis: Vector3) -> float:
	return absf(axis.dot(car.basis.x)) * car.half.x + absf(axis.dot(car.basis.y)) * car.half.y + absf(axis.dot(car.basis.z)) * car.half.z

static func intersects(a: Dictionary, b: Dictionary) -> bool:
	# The 15 separating axes of two oriented boxes, including rolled wrecks.
	var axes = [a.basis.x, a.basis.y, a.basis.z, b.basis.x, b.basis.y, b.basis.z]
	for ax in [a.basis.x, a.basis.y, a.basis.z]:
		for bx in [b.basis.x, b.basis.y, b.basis.z]:
			axes.append(ax.cross(bx))
	var offset: Vector3 = b.center - a.center
	for axis in axes:
		if axis.length_squared() < 0.00000001:
			continue
		if absf(offset.dot(axis)) > radius_on(a, axis) + radius_on(b, axis):
			return false
	return true

static func interpolate(a: Dictionary, b: Dictionary, weight: float) -> Dictionary:
	return {"center":a.center.lerp(b.center, weight), "half":b.half,
		"basis":Basis(a.basis.get_rotation_quaternion().slerp(b.basis.get_rotation_quaternion(), weight))}

static func first_contact(a0: Array, a1: Array, b0: Array, b1: Array) -> float:
	if not bounds(a1).intersects(bounds(b1)):
		return -1.0
	var first = 2.0
	for i in a1.size():
		for j in b1.size():
			if not intersects(a1[i], b1[j]):
				continue
			var low = 0.0
			var high = 1.0
			if intersects(a0[i], b0[j]):
				high = 0.0
			else:
				for iteration in 12:
					var middle = (low + high) * 0.5
					if intersects(interpolate(a0[i], a1[i], middle), interpolate(b0[j], b1[j], middle)):
						high = middle
					else:
						low = middle
			first = minf(first, high)
	return first if first <= 1.0 else -1.0

static func impact_poses(sim: RailSimulation, train: Dictionary, before: Array, after: Array, fraction: float) -> Array:
	var result = []
	for i in after.size():
		var car = interpolate(before[i], after[i], fraction)
		var rotation: Quaternion = car.basis.get_rotation_quaternion()
		result.append({"position":RailGraph.v_array(car.center - car.basis.y * car.half.y),
			"rotation":[rotation.x, rotation.y, rotation.z, rotation.w],
			"linear":RailGraph.v_array(car.basis.x * train.velocity * 10.0 / sim.ratio()),
			"angular":[0.0, 0.0, 0.0], "sleeping":false})
	return result

static func interpolate_cars(before: Array, after: Array, fraction: float) -> Array:
	var result = []
	for i in after.size():
		result.append(interpolate(before[i], after[i], fraction))
	return result

static func swept_contact(before: Array, after: Array, target: Array) -> float:
	# Wrecks move in the physics server, outside RailSimulation's substeps.
	# Sweep their measured translation AND rotation against on-rail vehicles.
	var travel = 0.0
	var dimension = INF
	var rotation_margin = 0.0
	for i in after.size():
		var angle: float = before[i].basis.get_rotation_quaternion().angle_to(after[i].basis.get_rotation_quaternion())
		var rotation_distance: float = angle * after[i].half.length()
		rotation_margin = maxf(rotation_margin, rotation_distance)
		travel = maxf(travel, before[i].center.distance_to(after[i].center) + rotation_distance)
		var half: Vector3 = after[i].half
		dimension = minf(dimension, minf(half.x, minf(half.y, half.z)) * 2)
	for car in target:
		var half: Vector3 = car.half
		dimension = minf(dimension, minf(half.x, minf(half.y, half.z)) * 2)
	if travel < 0.000001 or not bounds(before).merge(bounds(after)).grow(rotation_margin).intersects(bounds(target)):
		return -1.0
	var count = maxi(1, ceili(travel * 4.0 / dimension))
	var previous = before
	for step in count:
		var current = interpolate_cars(before, after, float(step + 1) / count)
		var fraction = first_contact(previous, current, target, target)
		if fraction >= 0:
			return (step + fraction) / count
		previous = current
	return -1.0
