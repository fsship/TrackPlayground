class_name RailVehicleConnections
extends Node3D
## Articulated fittings derived from the ordered cars, never saved separately.
## All input car transforms share a parent. Geometry lives in the first car's
## frame, so straight-line movement does not rebuild the bellows or hoses.

const STEEL = Color("657078")
const DARK = Color("30383c")
const RUBBER = Color("242b2e")
var factor = 1.0
var definitions: Array = []
var ends: Array = []
var links: Array = []
var last_poses: Array = []
static var unit_box: BoxMesh
static var unit_cylinder: CylinderMesh

static func mount(def: Dictionary, end: int, ratio: float) -> Vector3:
	# Steam buffer beams are inset from the catalog's overall envelope.
	var steam = def.id in ["core:steam", "core:steam_tender"]
	var inset = 0.7 if steam else 0.18
	# Preserve the original rigid-body attachment height for generic vehicles.
	var height: float = 0.88 if steam else def.height_m * 0.22
	return Vector3(end * maxf(0.0, def.length_m * 0.5 - inset), height, 0) * (10.0 / ratio)

static func joint_center(a: Dictionary, b: Dictionary, pose_a: Transform3D, pose_b: Transform3D, ratio: float) -> Vector3:
	return (pose_a * mount(a, -1, ratio) + pose_b * mount(b, 1, ratio)) * 0.5

static func frame(direction: Vector3, up: Vector3) -> Basis:
	var x = direction.normalized() if direction.length_squared() > 0.00000001 else Vector3.RIGHT
	var z = x.cross(up).normalized()
	if z.length_squared() < 0.1:
		z = x.cross(Vector3.UP if absf(x.y) < 0.9 else Vector3.BACK).normalized()
	return Basis(x, z.cross(x).normalized(), z)

static func mesh_node(parent: Node3D, mesh: Mesh, color: Color) -> MeshInstance3D:
	var node = MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = RailGeometry.material(color, 0.6, 0.45 if color != RUBBER else 0.0)
	parent.add_child(node)
	return node

static func box(parent: Node3D, size: Vector3, position: Vector3, color: Color) -> MeshInstance3D:
	if unit_box == null:
		unit_box = BoxMesh.new()
		unit_box.size = Vector3.ONE
	var node = mesh_node(parent, unit_box, color)
	node.position = position
	node.scale = size
	return node

static func span(node: Node3D, a: Vector3, b: Vector3, up: Vector3, width: float, height: float) -> void:
	node.transform = Transform3D(frame(b - a, up).scaled_local(Vector3(maxf(a.distance_to(b), 0.00001), height, width)), (a + b) * 0.5)

func setup(cars: Array, catalog: RailCatalog, ratio: float) -> void:
	name = "Connections"
	factor = 10.0 / ratio
	for id in cars:
		var def: Dictionary = catalog.vehicles[id]
		definitions.append(def)
		var pair = {}
		for end in [-1, 1]:
			var housing = box(self, Vector3(0.40, 0.28, 0.42) * factor, Vector3.ZERO, DARK)
			var shank = box(self, Vector3.ONE, Vector3.ZERO, STEEL)
			var head = Node3D.new()
			add_child(head)
			# Open-sided knuckle with a locking pin; the paired jaws interlock.
			box(head, Vector3(0.20, 0.24, 0.16) * factor, Vector3(-0.05, 0, -0.08) * factor, STEEL)
			box(head, Vector3(0.12, 0.24, 0.26) * factor, Vector3(0.06, 0, -0.02) * factor, STEEL)
			box(head, Vector3(0.13, 0.24, 0.09) * factor, Vector3(-0.025, 0, 0.10) * factor, STEEL)
			var pin = RailGeometry.cylinder(head, 0.045 * factor, 0.29 * factor, Vector3(-0.065, 0, -0.07) * factor, DARK)
			pin.name = "LockPin"
			pair[end] = {"anchor":mount(def, end, ratio), "housing":housing, "shank":shank, "head":head}
		ends.append(pair)
	for i in range(cars.size() - 1):
		var drawbar = cars[i] == "core:steam" and cars[i + 1] == "core:steam_tender"
		var link = {"a":i, "b":i + 1, "drawbar":drawbar, "hose":make_hose(), "bar":null, "pins":[], "gangway":null}
		if drawbar:
			link.bar = box(self, Vector3.ONE, Vector3.ZERO, STEEL)
			for end in 2:
				link.pins.append(RailGeometry.cylinder(self, 0.09 * factor, 0.35 * factor, Vector3.ZERO, STEEL))
			ends[i][-1].head.visible = false
			ends[i + 1][1].head.visible = false
			ends[i][-1].shank.visible = false
			ends[i + 1][1].shank.visible = false
		if definitions[i].kind == "coach" and definitions[i + 1].kind == "coach":
			link.gangway = mesh_node(self, ImmediateMesh.new(), RUBBER)
			link.gangway.name = "Gangway"
		links.append(link)

func make_hose() -> MultiMeshInstance3D:
	if unit_cylinder == null:
		unit_cylinder = CylinderMesh.new()
		unit_cylinder.top_radius = 1.0
		unit_cylinder.bottom_radius = 1.0
		unit_cylinder.height = 1.0
		unit_cylinder.radial_segments = 8
	var node = MultiMeshInstance3D.new()
	node.multimesh = MultiMesh.new()
	node.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	node.multimesh.mesh = unit_cylinder
	node.multimesh.instance_count = 8
	node.material_override = RailGeometry.material(RUBBER)
	add_child(node)
	return node

func update_from_cars(cars: Array) -> void:
	if cars.is_empty():
		return
	transform = cars[0].transform
	var inverse = transform.affine_inverse()
	var poses: Array = []
	var changed = last_poses.size() != cars.size()
	for i in cars.size():
		var pose: Transform3D = inverse * cars[i].transform
		poses.append(pose)
		if not changed and not pose.is_equal_approx(last_poses[i]):
			changed = true
	if not changed:
		return
	last_poses = poses
	for i in ends.size():
		var pose: Transform3D = poses[i]
		for end in [-1, 1]:
			var fitting: Dictionary = ends[i][end]
			var anchor: Vector3 = pose * fitting.anchor
			fitting.housing.transform = Transform3D(pose.basis.scaled_local(Vector3(0.40, 0.28, 0.42) * factor), anchor)
			var neighbor: int = i - end
			var target: Vector3
			if neighbor >= 0 and neighbor < ends.size():
				var other: Vector3 = poses[neighbor] * ends[neighbor][-end].anchor
				target = (anchor + other) * 0.5
			else:
				target = pose * Vector3(end * (definitions[i].length_m * 0.5 + 0.23) * factor, fitting.anchor.y, 0)
			var basis = frame(target - anchor, pose.basis.y)
			# Offset the two jaw centres just enough for their open sides to mesh.
			var jaw = target - basis.x * 0.055 * factor + basis.z * 0.055 * factor
			fitting.head.transform = Transform3D(basis, jaw)
			span(fitting.shank, anchor, jaw - basis.x * 0.1 * factor, pose.basis.y, 0.15 * factor, 0.16 * factor)
	for link in links:
		var pose_a: Transform3D = poses[link.a]
		var pose_b: Transform3D = poses[link.b]
		var a: Vector3 = pose_a * ends[link.a][-1].anchor
		var b: Vector3 = pose_b * ends[link.b][1].anchor
		var up = (pose_a.basis.y + pose_b.basis.y).normalized()
		if up.length_squared() < 0.1:
			up = pose_a.basis.y
		if link.drawbar:
			span(link.bar, a, b, up, 0.24 * factor, 0.12 * factor)
			link.pins[0].transform = Transform3D(pose_a.basis, a)
			link.pins[1].transform = Transform3D(pose_b.basis, b)
		update_hose(link.hose, a + pose_a.basis * Vector3(0, -0.16, 0.38) * factor, b + pose_b.basis * Vector3(0, -0.16, 0.38) * factor, up)
		if link.gangway != null:
			update_gangway(link, pose_a, pose_b)

func update_hose(hose: MultiMeshInstance3D, a: Vector3, b: Vector3, up: Vector3) -> void:
	var previous = a
	for i in 8:
		var t = (i + 1) / 8.0
		var point = a.lerp(b, t) - up * sin(t * PI) * 0.28 * factor
		var delta = point - previous
		var basis = Basis(Quaternion(Vector3.UP, delta.normalized())) if delta.length_squared() > 0.00000001 else Basis.IDENTITY
		hose.multimesh.set_instance_transform(i, Transform3D(basis.scaled_local(Vector3(0.045 * factor, maxf(delta.length(), 0.00001), 0.045 * factor)), (previous + point) * 0.5))
		previous = point

func update_gangway(link: Dictionary, a: Transform3D, b: Transform3D) -> void:
	# Interpolate the four doorway corners, not just the centre: both ends
	# stay flush with their own car on horizontal and vertical transitions.
	var mesh: ImmediateMesh = link.gangway.mesh
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array = []
	for i in 13:
		var t = i / 12.0
		var fold = 0.07 if i % 2 else 0.0
		var corners = []
		for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var def_a: Dictionary = definitions[link.a]
			var def_b: Dictionary = definitions[link.b]
			var pa = Vector3(-def_a.length_m * 0.48, def_a.height_m * (0.57 + corner.y * 0.27), corner.x * minf(0.67, def_a.width_m * 0.24)) * factor
			var pb = Vector3(def_b.length_m * 0.48, def_b.height_m * (0.57 + corner.y * 0.27), corner.x * minf(0.67, def_b.width_m * 0.24)) * factor
			var corrugation = a.basis.slerp(b.basis, t) * Vector3(0, corner.y * fold, corner.x * fold) * factor
			corners.append((a * pa).lerp(b * pb, t) + corrugation)
		rings.append(corners)
	for i in 12:
		for side in 4:
			var next = (side + 1) % 4
			var p: Vector3 = rings[i][side]
			var q: Vector3 = rings[i][next]
			var r: Vector3 = rings[i + 1][next]
			var s: Vector3 = rings[i + 1][side]
			for triangle in [[p, r, q], [p, s, r]]:
				mesh.surface_set_normal((triangle[2] - triangle[0]).cross(triangle[1] - triangle[0]).normalized())
				for vertex in triangle:
					mesh.surface_add_vertex(vertex)
	mesh.surface_end()
