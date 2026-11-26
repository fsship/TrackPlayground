extends Node3D

# Off-track cars use Godot's rigid-body solver; normal railway dynamics stay
# in RailSimulation. Body origins are at the centre of the vehicle envelope.
var consists: Dictionary = {}

static func car_basis(pose: Dictionary) -> Basis:
	var q: Array = pose.rotation
	return Basis(Quaternion(q[0], q[1], q[2], q[3]))

func clear() -> void:
	for rig in consists.values():
		rig.root.free()
	consists.clear()

func sync(sim: RailSimulation) -> void:
	var active = {}
	for train in sim.trains:
		if not train.has("derailed_cars"):
			continue
		active[train.id] = true
		if not consists.has(train.id):
			create_consist(sim, train)
		var rig: Dictionary = consists[train.id]
		for i in rig.bodies.size():
			var body: RigidBody3D = rig.bodies[i]
			if body.freeze != sim.paused:
				if sim.paused:
					store_car(train.derailed_cars[i], body, rig.heights[i])
				body.freeze = sim.paused
				if not sim.paused:
					body.linear_velocity = RailGraph.array_v(train.derailed_cars[i].linear)
					body.angular_velocity = RailGraph.array_v(train.derailed_cars[i].angular)
					body.sleeping = train.derailed_cars[i].sleeping
			if not sim.paused:
				store_car(train.derailed_cars[i], body, rig.heights[i])
		train.velocity = RailGraph.array_v(train.derailed_cars[0].linear).length() * sim.ratio() / 10.0
	for id in consists.keys():
		if not active.has(id):
			consists[id].root.free()
			consists.erase(id)

func store_car(pose: Dictionary, body: RigidBody3D, height: float) -> void:
	var q = body.basis.get_rotation_quaternion()
	pose.position = RailGraph.v_array(body.position - body.basis.y * height * 0.5)
	pose.rotation = [q.x, q.y, q.z, q.w]
	pose.linear = RailGraph.v_array(Vector3.ZERO if body.sleeping else body.linear_velocity)
	pose.angular = RailGraph.v_array(Vector3.ZERO if body.sleeping else body.angular_velocity)
	pose.sleeping = body.sleeping

func create_consist(sim: RailSimulation, train: Dictionary) -> void:
	var root = Node3D.new()
	add_child(root)
	var rig = {"root":root, "bodies":[], "heights":[]}
	var factor = 10.0 / sim.ratio()
	for i in train.cars.size():
		var def: Dictionary = sim.catalog.vehicles[train.cars[i]]
		var pose: Dictionary = train.derailed_cars[i]
		var height: float = def.height_m * factor
		var body = RigidBody3D.new()
		body.mass = def.mass_kg / 1000.0
		# Prototype-equivalent time, matching the on-rail speed conversion.
		body.gravity_scale = factor
		body.continuous_cd = true
		body.linear_damp = 0.02
		body.angular_damp = 0.18
		body.physics_material_override = PhysicsMaterial.new()
		body.physics_material_override.friction = 0.6
		body.physics_material_override.bounce = 0.04
		var shape = CollisionShape3D.new()
		var box = BoxShape3D.new()
		box.size = Vector3(def.length_m, def.height_m, def.width_m) * factor
		shape.shape = box
		body.add_child(shape)
		body.basis = car_basis(pose)
		body.position = RailGraph.array_v(pose.position) + body.basis.y * height * 0.5
		body.freeze = sim.paused
		root.add_child(body)
		body.linear_velocity = RailGraph.array_v(pose.linear)
		body.angular_velocity = RailGraph.array_v(pose.angular)
		body.sleeping = pose.sleeping
		rig.bodies.append(body)
		rig.heights.append(height)
		if i > 0:
			var previous: RigidBody3D = rig.bodies[i - 1]
			var joint = PinJoint3D.new()
			joint.exclude_nodes_from_collision = false
			root.add_child(joint)
			# Use the same mounting points as the visible shanks/drawbar.
			var a = Transform3D(previous.basis, previous.position - previous.basis.y * rig.heights[i - 1] * 0.5)
			var b = Transform3D(body.basis, body.position - body.basis.y * height * 0.5)
			joint.position = preload("res://scripts/vehicle_connections.gd").joint_center(sim.catalog.vehicles[train.cars[i - 1]], def, a, b, sim.ratio())
			joint.node_a = joint.get_path_to(previous)
			joint.node_b = joint.get_path_to(body)
	consists[train.id] = rig

static func track_collision(parent: Node3D, paths: Array, gauge: float) -> void:
	# A narrow, low-friction rail deck supports trailing cars until they pass
	# the actual endpoint. There is no invisible floor beyond the track.
	var body = StaticBody3D.new()
	body.physics_material_override = PhysicsMaterial.new()
	body.physics_material_override.friction = 0.002
	for points in paths:
		var start_direction: Vector3 = (points[1] - points[0]).normalized()
		var end_direction: Vector3 = (points[-1] - points[-2]).normalized()
		# Merge straight segments to avoid internal triangle edges catching cars.
		var stride: int = points.size() - 1 if start_direction.dot(end_direction) > 0.99999 else 4
		for i in range(0, points.size() - 1, stride):
			var a: Vector3 = points[i]
			var b: Vector3 = points[mini(i + stride, points.size() - 1)]
			var tangent = (b - a).normalized()
			var side = tangent.cross(Vector3.UP).normalized()
			var shape = CollisionShape3D.new()
			var box = BoxShape3D.new()
			box.size = Vector3(a.distance_to(b), 0.08, gauge * 2.45)
			shape.shape = box
			shape.basis = Basis(tangent, side.cross(tangent).normalized(), side)
			shape.position = (a + b) * 0.5 + Vector3.UP * 0.04
			body.add_child(shape)
	parent.add_child(body)
