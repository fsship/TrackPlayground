extends Node3D
## Original rolling-stock models in prototype metres. Shared static meshes
## are merged by material; bogies articulate and wheelsets roll independently.
const Builder = preload("res://scripts/steam_locomotive.gd").Builder
const RunningGear = preload("res://scripts/running_gear.gd")
static var kits: Dictionary = {}
var model: Node3D
var axles: Array = []
var wheel_travel = 0.0
var last_distance = -1.0

static func supports(def: Dictionary) -> bool:
	return def.id in ["core:diesel", "core:electric", "core:coach", "core:freight", "core:tanker", "alpine:mountain_diesel"]

static func create(def: Dictionary, ratio: float) -> Node3D:
	var key = str([def.id, def.length_m, def.width_m, def.height_m, def.get("color", "638c6a")])
	if not kits.has(key):
		kits[key] = _build(def)
	var kit: Dictionary = kits[key]
	var root = new()
	root.name = "DetailedVehicle"
	root.model = Node3D.new()
	root.model.name = "PrototypeMetres"
	root.model.scale = Vector3.ONE * (10.0 / ratio)
	root.add_child(root.model)
	root._mesh(kit.body, root.model, "Body")
	for center in kit.bogie_centers:
		var pivot = RunningGear.add_pivot(root, root.model, center, kit.pivot_height, 10.0 / ratio)
		var bogie = root._mesh(kit.bogie, pivot, "Bogie")
		bogie.position.y = -kit.pivot_height
		for offset in kit.axle_offsets:
			var wheel = root._mesh(kit.wheel, pivot, "Wheelset")
			wheel.position = Vector3(offset, kit.radius - kit.pivot_height, 0)
			root.axles.append({"node":wheel, "radius":kit.radius})
	for plate in kit.labels:
		root._label(plate[0], plate[1], plate[2], plate[3], plate[4])
	return root

func _mesh(mesh: Mesh, parent: Node3D, title: String) -> MeshInstance3D:
	var node = MeshInstance3D.new()
	node.name = title
	node.mesh = mesh
	parent.add_child(node)
	return node

func _label(text: String, pos: Vector3, yaw: float, size: float, color: Color) -> void:
	var label = Label3D.new()
	label.text = text
	label.font_size = 64
	label.pixel_size = size
	label.outline_size = 0
	label.modulate = color
	label.position = pos
	label.rotation.y = yaw
	model.add_child(label)

func sync_motion(distance: float, velocity: float, _paused: bool, derailed: bool) -> void:
	if last_distance >= 0 and not derailed and distance >= last_distance:
		wheel_travel += (distance - last_distance) * (-1.0 if velocity < 0 else 1.0)
	last_distance = distance
	for axle in axles:
		axle.node.rotation.z = fposmod(-wheel_travel / axle.radius, TAU)

static func _materials(color: Color) -> Dictionary:
	var result = {}
	var palette = {
		"paint":[color, 0.48, 0.40], "edge":[color.lightened(0.13), 0.48, 0.35],
		"shade":[color.darkened(0.30), 0.56, 0.35], "black":[Color("20282d"), 0.72, 0.3],
		"steel":[Color("a5b3ba"), 0.30, 0.82], "frame":[Color("414e55"), 0.58, 0.6],
		"darksteel":[Color("414e55"), 0.58, 0.6],
		"roof":[Color("aab3ad"), 0.52, 0.55], "rubber":[Color("121b20"), 0.88, 0.0],
		"glass":[Color("315968"), 0.18, 0.50], "cream":[Color("e9ddba"), 0.60, 0.2],
		"brass":[Color("b99354"), 0.40, 0.7], "ceramic":[Color("6b4438"), 0.30, 0.1],
		"red":[Color("9f4438"), 0.50, 0.35], "lamp":[Color("ffe7b2"), 0.3, 0.0],
		"seat":[Color("44747b"), 0.88, 0.0], "floor":[Color("685f50"), 0.85, 0.0],
		"glazing":[Color(0.32, 0.51, 0.57, 0.30), 0.20, 0.15]
	}
	for name in palette:
		var mat = StandardMaterial3D.new()
		mat.resource_name = name
		mat.albedo_color = palette[name][0]
		mat.roughness = palette[name][1]
		mat.metallic = palette[name][2]
		if name == "glazing":
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		if name == "roof":
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		if name == "lamp":
			mat.emission_enabled = true
			mat.emission = palette[name][0]
			mat.emission_energy_multiplier = 0.35
		result[name] = mat
	return result

static func _quad(b, points: Array, mat: String) -> void:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var normal: Vector3 = (points[2] - points[0]).cross(points[1] - points[0]).normalized()
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_normal(normal)
		st.add_vertex(points[i])
	# append_from must receive indexed geometry: once a shared material
	# surface has indices, subsequent non-indexed vertices would be orphaned.
	st.index()
	b.add(st.commit(), Vector3.ZERO, mat)

static func _shell(b, length: float, profile: Array, mat: String, slope: float = 0.0, center_x: float = 0.0) -> void:
	var rings = []
	for end in [-1, 1]:
		var ring = []
		for point in profile:
			ring.append(Vector3(center_x + end * (length * 0.5 - maxf(0, point.x - 2.65) * slope), point.x, point.y))
		rings.append(ring)
	for i in profile.size():
		var j = (i + 1) % profile.size()
		_quad(b, [rings[0][i], rings[1][i], rings[1][j], rings[0][j]], mat)
	for end in 2:
		var center = Vector3.ZERO
		for point in rings[end]:
			center += point
		center /= rings[end].size()
		var st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in profile.size():
			var triangle = [center, rings[end][i], rings[end][(i + 1) % profile.size()]]
			if end == 1:
				triangle.reverse()
			var normal: Vector3 = (triangle[2] - triangle[0]).cross(triangle[1] - triangle[0]).normalized()
			for point in triangle:
				st.set_normal(normal)
				st.add_vertex(point)
		st.index()
		b.add(st.commit(), Vector3.ZERO, mat)

static func _roof(b, length: float, half_width: float, base: float, rise: float, mat: String, center_x: float = 0.0) -> void:
	# Smooth normals across the arch, with distinct flat end caps.
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var profile = []
	for i in 33:
		var a = PI * i / 32
		profile.append(Vector2(base + sin(a) * rise, -cos(a) * half_width))
	for i in 32:
		for v in [[-1, i], [1, i], [1, i + 1], [-1, i], [1, i + 1], [-1, i + 1]]:
			var a = PI * v[1] / 32
			st.set_normal(Vector3(0, sin(a) / rise, -cos(a) / half_width).normalized())
			st.add_vertex(Vector3(center_x + v[0] * length * 0.5, profile[v[1]].x, profile[v[1]].y))
	st.index()
	b.add(st.commit(), Vector3.ZERO, mat)
	for end in [-1, 1]:
		for i in 32:
			var x = center_x + end * length * 0.5
			var points = [Vector3(x, base, 0), Vector3(x, profile[i].x, profile[i].y), Vector3(x, profile[i + 1].x, profile[i + 1].y)]
			if end == 1:
				points.reverse()
			points.append(points[2])
			_quad(b, points, mat)

static func _build(def: Dictionary) -> Dictionary:
	var l: float = def.length_m
	var w: float = def.width_m
	var h: float = def.height_m
	var loco = def.kind == "locomotive"
	var mountain = loco and def.id != "core:diesel" and def.id != "core:electric"
	var electric = def.id == "core:electric"
	var running_gear = RunningGear.layout(def)
	var radius: float = running_gear.radius
	var center: float = running_gear.center
	var offsets: Array = running_gear.axles
	var materials = _materials(Color(str(def.get("color", "638c6a"))))
	var b = Builder.new()
	_chassis(b, def, center, offsets, radius)
	var labels = []
	if loco:
		if mountain:
			_mountain(b, l, w, h)
		else:
			_locomotive(b, l, w, h, electric)
		var title = "EL 0186" if electric else ("DF 2008" if not mountain else "ALPINE 07")
		for side in [-1, 1]:
			labels.append([title, Vector3(-l * 0.29 if mountain else -l * 0.18, 1.68, side * (w * 0.47 + 0.016)), 0.0 if side > 0 else PI, 0.0045, Color("f2e5bf")])
	elif def.kind == "coach":
		_coach(b, l, w, h)
		for side in [-1, 1]:
			labels.append(["TRACK PLAYGROUND   ·   025", Vector3(0, 1.70, side * (w * 0.47 + 0.075)), 0.0 if side > 0 else PI, 0.0048, Color("34565d")])
	elif def.kind == "freight":
		_container(b, l, w, h)
		for side in [-1, 1]:
			labels.append(["TRACK  /  RAIL", Vector3(0, 2.83, side * 1.305), 0.0 if side > 0 else PI, 0.009, Color("eee5ca")])
			labels.append(["TPWU 200836  4", Vector3(-3.2, 1.67, side * 1.305), 0.0 if side > 0 else PI, 0.0038, Color("eee5ca")])
	else:
		_tanker(b, l, w, h)
		for side in [-1, 1]:
			labels.append(["TP  70418", Vector3(-1.85, 2.20, side * 1.055), 0.0 if side > 0 else PI, 0.006, Color("263940")])
	return {"body":b.finish(materials), "bogie":_bogie(offsets, radius, materials), "wheel":_wheelset(radius, materials), "bogie_centers":[-center, center], "pivot_height":running_gear.height, "axle_offsets":offsets, "radius":radius, "labels":labels}

static func _wheelset(r: float, materials: Dictionary) -> ArrayMesh:
	var b = Builder.new()
	b.cylinder(0.085, 1.95, Vector3.ZERO, "frame", Vector3.BACK)
	for side in [-1, 1]:
		var z = side * 0.745
		b.cylinder(r - 0.055, 0.09, Vector3(0, 0, z), "frame", Vector3.BACK, -1, 48)
		b.ring(r - 0.07, r, 0.13, Vector3(0, 0, z), "steel", Vector3.BACK)
		b.ring(r - 0.025, r + 0.025, 0.03, Vector3(0, 0, z - side * 0.072), "frame", Vector3.BACK)
		b.ring(r * 0.42, r * 0.76, 0.06, Vector3(0, 0, z + side * 0.045), "black", Vector3.BACK)
		b.cylinder(0.135, 0.15, Vector3(0, 0, z), "steel", Vector3.BACK)
		for i in 8:
			var a = TAU * i / 8
			b.cylinder(0.032, 0.015, Vector3(cos(a) * r * 0.60, sin(a) * r * 0.60, z + side * 0.082), "rubber", Vector3.BACK, -1, 12)
		b.box(Vector3(0.025, 0.12, 0.014), Vector3(0.18, 0, z + side * 0.09), "cream")
	return b.finish(materials)

static func _bogie(offsets: Array, r: float, materials: Dictionary) -> ArrayMesh:
	var b = Builder.new()
	var length: float = offsets[-1] - offsets[0] + 1.05
	b.box(Vector3(length, 0.18, 0.40), Vector3(0, 0.86, 0), "black")
	b.cylinder(0.30, 0.18, Vector3(0, 1.07, 0), "frame")
	for side in [-1, 1]:
		b.box(Vector3(length, 0.17, 0.13), Vector3(0, 0.97, side * 1.04), "frame")
		b.box(Vector3(length - 0.20, 0.10, 0.12), Vector3(0, 0.71, side * 1.04), "black")
		for x in offsets:
			b.box(Vector3(0.34, 0.30, 0.21), Vector3(x, r, side * 1.02), "frame")
			b.cylinder(0.11, 0.035, Vector3(x, r, side * 1.145), "black", Vector3.BACK)
			for dx in [-0.12, 0.12]:
				b.rivet(Vector3(x + dx, r + 0.10, side * 1.155), Vector3.BACK, "steel")
			b.box(Vector3(0.095, 0.22, 0.13), Vector3(x + r + 0.09, r, side * 0.745), "black")
			b.pipe(Vector3(x + r + 0.09, r, side * 0.745), Vector3(x + r + 0.09, 0.95, side * 0.745), 0.026, "frame")
			for dx in [-0.28, 0.28]:
				b.pipe(Vector3(x + dx, 0.72, side * 1.04), Vector3(x + dx, 0.99, side * 1.04), 0.026, "steel")
		for i in range(offsets.size() - 1):
			var x: float = (offsets[i] + offsets[i + 1]) * 0.5
			b.box(Vector3(0.67, 0.09, 0.30), Vector3(x, 0.63, side * 1.04), "frame")
			for dx in [-0.17, 0.17]:
				for j in 6:
					b.ring(0.062, 0.10, 0.025, Vector3(x + dx, 0.70 + j * 0.045, side * 1.04), "steel")
			b.pipe(Vector3(x - 0.38, 0.65, side * 1.14), Vector3(x - 0.19, 0.99, side * 1.14), 0.045, "frame")
	for x in offsets:
		b.box(Vector3(0.12, 0.10, 1.95), Vector3(x, 1.10, 0), "frame")
	return b.finish(materials)

static func _chassis(b, def: Dictionary, bogie_center: float, offsets: Array, r: float) -> void:
	var l: float = def.length_m
	var w: float = def.width_m
	var loco = def.kind == "locomotive"
	var deck = 1.29 if loco else 1.16
	if def.kind != "tanker":
		b.box(Vector3(l * 0.96, 0.16, w * 0.95), Vector3(0, deck, 0), "black")
	for side in [-1, 1]:
		b.box(Vector3(l * 0.96, 0.26, 0.12), Vector3(0, deck - 0.12, side * w * 0.45), "frame")
		b.box(Vector3(l * 0.96, 0.045, 0.20), Vector3(0, deck - 0.265, side * w * 0.45), "steel")
		var rivet_count = maxi(2, ceili(l / 0.55))
		for i in rivet_count:
			b.rivet(Vector3(lerpf(-l * 0.45, l * 0.45, float(i) / (rivet_count - 1)), deck - 0.12, side * (w * 0.45 + 0.07)))
	var middle: float = bogie_center - absf(offsets[0]) - r - 0.45
	for x in [-middle * 0.6, 0, middle * 0.6]:
		b.box(Vector3(0.16, 0.20, w * 0.84), Vector3(x, deck - 0.12, 0), "frame")
	if loco:
		b.box(Vector3(middle * 1.5, 0.58, 1.50), Vector3(0, 0.80, 0), "frame")
		for side in [-1, 1]:
			b.box(Vector3(1.05, 0.45, 0.35), Vector3(-middle * 0.65, 0.89, side * 0.98), "black")
			b.cylinder(0.18, middle * 0.70, Vector3(middle * 0.35, 0.79, side * 0.98), "black", Vector3.RIGHT)
			b.line([Vector3(-middle, 1.10, side * 1.22), Vector3(0, 1.10, side * 1.22), Vector3(middle * 0.50, 0.95, side * 1.12)], 0.025, "steel")
	else:
		b.box(Vector3(1.35, 0.43, 0.75), Vector3(-middle * 0.50, 0.82, 0.48), "frame")
		b.cylinder(0.18, 1.40, Vector3(middle * 0.40, 0.80, -0.45), "black", Vector3.RIGHT)
		b.line([Vector3(-middle, 0.98, -0.85), Vector3(middle, 0.98, -0.85), Vector3(middle, 0.68, -0.55)], 0.026, "frame")
	for end in [-1, 1]:
		var height: float = def.height_m * 0.22
		b.box(Vector3(0.15, 0.28, w * 0.92), Vector3(end * (l * 0.48 - 0.04), height, 0), "frame")
		for side in [-1, 1]:
			b.box(Vector3(0.14, 0.18, 0.32), Vector3(end * l * 0.48, height + 0.18, side * w * 0.33), "cream")
			b.line([Vector3(end * (l * 0.48 + 0.02), height, side * 0.50), Vector3(end * (l * 0.48 + 0.06), height - 0.26, side * 0.55)], 0.035, "rubber")

static func _side_window(b, x: float, y: float, z: float, width: float, height: float, glazing: String = "glass") -> void:
	b.box(Vector3(width + 0.13, height + 0.13, 0.025), Vector3(x, y, z), "rubber")
	b.box(Vector3(width, height, 0.03), Vector3(x, y, z + signf(z) * 0.015), glazing)
	for dx in [-1, 1]:
		b.box(Vector3(0.025, height + 0.10, 0.04), Vector3(x + dx * (width + 0.08) * 0.5, y, z + signf(z) * 0.018), "steel")

static func _louver(b, x: float, y: float, z: float, width: float, height: float, rows: int) -> void:
	b.box(Vector3(width + 0.12, height + 0.10, 0.026), Vector3(x, y, z), "shade")
	b.box(Vector3(width, height, 0.035), Vector3(x, y, z + signf(z) * 0.025), "rubber")
	for i in rows:
		b.box(Vector3(width - 0.04, 0.033, 0.045), Vector3(x, y - height * 0.44 + height * 0.88 * i / maxf(rows - 1, 1), z + signf(z) * 0.055), "frame", Basis(Vector3.RIGHT, signf(z) * 0.20))

static func _steps(b, x: float, half_width: float) -> void:
	for side in [-1, 1]:
		for i in 3:
			b.box(Vector3(0.62, 0.055, 0.25), Vector3(x, 0.55 + i * 0.28, side * (half_width - 0.13)), "steel")
		for dx in [-0.33, 0.33]:
			b.pipe(Vector3(x + dx, 1.18, side * (half_width - 0.035)), Vector3(x + dx, 2.55, side * (half_width - 0.035)), 0.024, "steel")

static func _fan(b, x: float, y: float, radius: float) -> void:
	b.cylinder(radius, 0.08, Vector3(x, y, 0), "black", Vector3.UP, -1, 48)
	b.ring(radius - 0.045, radius + 0.035, 0.08, Vector3(x, y + 0.04, 0), "steel")
	for i in 12:
		var angle = TAU * i / 12
		b.box(Vector3(radius * 0.72, 0.023, 0.13), Vector3(x + cos(angle) * radius * 0.45, y + 0.045, sin(angle) * radius * 0.45), "frame", Basis(Vector3.UP, -angle + 0.45))
	for i in range(-5, 6):
		var z = i * radius / 6
		var extent = sqrt(radius * radius - z * z) * 0.96
		b.pipe(Vector3(x - extent, y + 0.085, z), Vector3(x + extent, y + 0.085, z), 0.012, "steel")
	b.cylinder(radius * 0.15, 0.11, Vector3(x, y + 0.035, 0), "frame")

static func _locomotive(b, l: float, w: float, h: float, electric: bool) -> void:
	var roof_y = h - (0.83 if electric else 0.34)
	var shoulder = roof_y - 0.30
	var half = w * 0.465
	var profile = [Vector2(1.42, -half), Vector2(shoulder, -half), Vector2(roof_y - 0.06, -half * 0.82), Vector2(roof_y, -half * 0.55), Vector2(roof_y, half * 0.55), Vector2(roof_y - 0.06, half * 0.82), Vector2(shoulder, half), Vector2(1.42, half)]
	_shell(b, l * 0.96, profile, "paint", 0.30)
	for side in [-1, 1]:
		var z = side * (half + 0.018)
		b.box(Vector3(l * 0.94, 0.14, 0.025), Vector3(0, 1.88, z), "cream")
		b.box(Vector3(l * 0.93, 0.035, 0.025), Vector3(0, 2.02, z), "shade")
		for end in [-1, 1]:
			_side_window(b, end * l * 0.397, 3.04 if not electric else 2.89, z, l * 0.063, 0.65)
			var door_x = end * l * 0.323
			b.box(Vector3(0.80, 1.83, 0.035), Vector3(door_x, 2.34, z), "shade")
			_side_window(b, door_x, 2.92, z + side * 0.027, 0.56, 0.50)
			b.pipe(Vector3(door_x - 0.25, 2.06, z + side * 0.055), Vector3(door_x - 0.25, 2.24, z + side * 0.055), 0.021, "steel")
			for y in [1.66, 2.60]:
				b.box(Vector3(0.07, 0.10, 0.05), Vector3(door_x + 0.37, y, z + side * 0.03), "steel")
		for i in (5 if electric else 7):
			var x = -l * 0.23 + i * l * 0.46 / (4.0 if electric else 6.0)
			_louver(b, x, 2.73, z + side * 0.01, l * (0.065 if electric else 0.047), 0.94 if electric else 1.06, 13)
		for i in 16:
			b.rivet(Vector3(-l * 0.45 + i * l * 0.06, 1.54, z + side * 0.03))
	for end in [-1, 1]:
		_steps(b, end * l * 0.323, w * 0.495)
		for side in [-1, 1]:
			var z = side * 0.61
			var y0 = 2.65
			var y1 = 3.27 if not electric else 3.17
			var x0 = end * (l * 0.48 + 0.015)
			var x1 = end * (l * 0.48 - (y1 - 2.65) * 0.30 + 0.015)
			var pane = [Vector3(x0, y0, z - 0.49), Vector3(x1, y1, z - 0.49), Vector3(x1, y1, z + 0.49), Vector3(x0, y0, z + 0.49)]
			if end < 0:
				pane.reverse()
			_quad(b, pane, "glass")
			b.line(pane + [pane[0]], 0.035, "rubber")
			b.pipe(Vector3(end * (l * 0.48 - 0.025), y0 + 0.06, z - 0.23), Vector3(end * (l * 0.48 - 0.11), y0 + 0.39, z + 0.17), 0.016, "steel")
			b.cylinder(0.105, 0.06, Vector3(end * (l * 0.48 + 0.045), 2.14, side * 0.96), "lamp", Vector3.RIGHT)
			b.cylinder(0.055, 0.07, Vector3(end * (l * 0.48 + 0.05), 2.14, side * 1.19), "red", Vector3.RIGHT)
		b.box(Vector3(0.06, 0.16, 0.78), Vector3(end * (l * 0.48 + 0.05), 2.40, 0), "shade")
		b.pipe(Vector3(end * (l * 0.48 + 0.06), 1.70, -1.0), Vector3(end * (l * 0.48 + 0.06), 1.70, 1.0), 0.025, "steel")
		b.box(Vector3(0.16, 0.30, 2.20), Vector3(end * (l * 0.48 - 0.12), 0.63, 0), "frame")
	if electric:
		for x in [-l * 0.24, l * 0.24]:
			_pantograph(b, x, roof_y + 0.06, h - 0.045)
		for x in [-1.2, -0.4, 0.4, 1.2]:
			_insulator(b, Vector3(x, roof_y + 0.11, 0.65))
		b.pipe(Vector3(-l * 0.24, roof_y + 0.28, 0.65), Vector3(l * 0.24, roof_y + 0.28, 0.65), 0.026, "brass")
		b.box(Vector3(1.1, 0.20, 0.9), Vector3(0, roof_y + 0.15, -0.25), "frame")
	else:
		for x in [-1.85, 0.0, 1.85]:
			_fan(b, x, roof_y + 0.03, 0.64)
		for x in [-3.3, 3.3]:
			b.box(Vector3(0.66, 0.18, 0.36), Vector3(x, roof_y + 0.10, 0), "black")
			b.box(Vector3(0.48, 0.015, 0.21), Vector3(x, roof_y + 0.20, 0), "rubber")
	for end in [-1, 1]:
		b.cylinder(0.07, 0.36, Vector3(end * l * 0.32, roof_y + 0.15, 0.42), "brass", Vector3.RIGHT, 0.13)

static func _insulator(b, pos: Vector3) -> void:
	b.cylinder(0.055, 0.24, pos, "ceramic")
	for j in 4:
		b.cylinder(0.10, 0.025, pos + Vector3(0, -0.08 + j * 0.055, 0), "ceramic", Vector3.UP, 0.075)

static func _pantograph(b, x: float, base: float, top: float) -> void:
	for z in [-0.45, 0.45]:
		_insulator(b, Vector3(x - 0.57, base + 0.08, z))
		_insulator(b, Vector3(x + 0.57, base + 0.08, z))
		b.pipe(Vector3(x - 0.70, base + 0.18, z), Vector3(x + 0.70, base + 0.18, z), 0.034, "frame")
		for sign_x in [-1, 1]:
			var low = Vector3(x, base + 0.20, z)
			var elbow = Vector3(x + sign_x * 0.76, (base + top) * 0.5, z)
			var high = Vector3(x, top - 0.05, z)
			b.pipe(low, elbow, 0.027, "red")
			b.pipe(elbow, high, 0.021, "steel")
			b.cylinder(0.055, 0.06, elbow, "steel", Vector3.BACK)
	for dx in [-0.12, 0.12]:
		b.box(Vector3(0.085, 0.045, 1.45), Vector3(x + dx, top, 0), "black")

static func _mountain(b, l: float, w: float, h: float) -> void:
	var hood_width = w * 0.60
	var hood_end = l * 0.43
	var cab_x = -l * 0.25
	var cab_length = l * 0.19
	var hood_start = cab_x + cab_length * 0.5
	b.box(Vector3(hood_end - hood_start, h * 0.43, hood_width), Vector3((hood_start + hood_end) * 0.5, 1.40 + h * 0.215, 0), "paint")
	b.box(Vector3(l * 0.10, 0.85, hood_width), Vector3(-l * 0.405, 1.82, 0), "paint")
	b.box(Vector3(cab_length, h - 1.60, w * 0.91), Vector3(cab_x, (h + 1.20) * 0.5, 0), "paint")
	_roof(b, cab_length + 0.16, w * 0.47, h - 0.20, 0.16, "roof", cab_x)
	for side in [-1, 1]:
		_side_window(b, cab_x + 0.30, h - 0.85, side * (w * 0.455 + 0.02), cab_length * 0.55, 0.70)
		b.box(Vector3(cab_length * 0.85, 0.12, 0.03), Vector3(cab_x, 2.10, side * (w * 0.455 + 0.035)), "cream")
		for i in 6:
			var x = hood_start + 0.7 + i * (hood_end - hood_start - 1.4) / 5
			_louver(b, x, 2.53, side * (hood_width * 0.5 + 0.02), 0.68, 0.82, 11)
			b.box(Vector3(0.78, 0.50, 0.035), Vector3(x, 1.80, side * (hood_width * 0.5 + 0.02)), "shade")
			b.pipe(Vector3(x + 0.23, 1.88, side * (hood_width * 0.5 + 0.06)), Vector3(x + 0.23, 2.02, side * (hood_width * 0.5 + 0.06)), 0.018, "steel")
		var z = side * (w * 0.5 - 0.045)
		for i in 8:
			var x = hood_start + i * (hood_end - hood_start) / 7
			b.pipe(Vector3(x, 1.40, z), Vector3(x, 2.28, z), 0.025, "cream")
		b.pipe(Vector3(hood_start, 2.28, z), Vector3(hood_end, 2.28, z), 0.027, "cream")
	for end in [-1, 1]:
		var x = cab_x + end * cab_length * 0.5 + end * 0.015
		b.box(Vector3(0.035, 0.68, w * 0.70), Vector3(x, h - 0.85, 0), "glass")
		b.box(Vector3(0.05, 0.72, 0.07), Vector3(x + end * 0.02, h - 0.85, 0), "steel")
		_steps(b, end * l * 0.445, w * 0.495)
		b.cylinder(0.13, 0.06, Vector3(end * l * 0.475, 2.04, 0), "lamp", Vector3.RIGHT)
	_fan(b, l * 0.26, 1.40 + h * 0.43 + 0.035, 0.54)
	b.cylinder(0.105, 0.48, Vector3(l * 0.03, 1.40 + h * 0.43 + 0.22, 0), "black")

static func _coach(b, l: float, w: float, h: float) -> void:
	var half = w * 0.47
	var body_length = l * 0.96
	var window_step = l * 0.066
	var window_width = window_step * 0.73
	var y0 = 2.19
	var y1 = 3.10
	var roof_base = h - 0.53
	b.box(Vector3(body_length, 0.12, w * 0.91), Vector3(0, 1.35, 0), "floor")
	for side in [-1, 1]:
		var z = side * half
		b.box(Vector3(body_length, 0.78, 0.08), Vector3(0, 1.80, z), "paint")
		b.box(Vector3(body_length, roof_base - y1, 0.08), Vector3(0, (roof_base + y1) * 0.5, z), "paint")
		b.box(Vector3(body_length, 0.12, 0.025), Vector3(0, 2.08, z + side * 0.055), "shade")
		b.box(Vector3(body_length, 0.045, 0.025), Vector3(0, 1.45, z + side * 0.055), "steel")
		var previous = -body_length * 0.5
		for i in 11:
			var x = (i - 5) * window_step
			var left = x - window_width * 0.5
			b.box(Vector3(left - previous, y1 - y0, 0.08), Vector3((left + previous) * 0.5, (y0 + y1) * 0.5, z), "paint")
			b.box(Vector3(window_width, y1 - y0, 0.018), Vector3(x, (y0 + y1) * 0.5, z), "glazing")
			for edge in [-1, 1]:
				b.box(Vector3(0.035, y1 - y0 + 0.07, 0.07), Vector3(x + edge * window_width * 0.5, (y0 + y1) * 0.5, z + side * 0.025), "steel")
				b.box(Vector3(window_width + 0.07, 0.035, 0.07), Vector3(x, y0 if edge < 0 else y1, z + side * 0.025), "steel")
			b.box(Vector3(window_width, 0.028, 0.04), Vector3(x, 2.82, z + side * 0.028), "steel")
			previous = x + window_width * 0.5
			# Real seats behind the glazing, with an open centre aisle.
			for dx in [-0.34, 0.34]:
				b.box(Vector3(0.50, 0.12, 0.63), Vector3(x + dx, 1.83, side * 0.90), "seat")
				b.box(Vector3(0.10, 0.61, 0.63), Vector3(x + dx + signf(dx) * 0.23, 2.09, side * 0.90), "seat")
				b.box(Vector3(0.40, 0.035, 0.65), Vector3(x + dx, 1.54, side * 0.90), "frame")
		b.box(Vector3(body_length * 0.5 - previous, y1 - y0, 0.08), Vector3((body_length * 0.5 + previous) * 0.5, (y0 + y1) * 0.5, z), "paint")
		for end in [-1, 1]:
			var x = end * l * 0.432
			b.box(Vector3(0.88, 2.04, 0.035), Vector3(x, 2.40, z + side * 0.020), "shade")
			_side_window(b, x, 2.94, z + side * 0.034, 0.58, 0.56)
			b.pipe(Vector3(x - 0.26, 2.05, z + side * 0.065), Vector3(x - 0.26, 2.22, z + side * 0.065), 0.019, "steel")
			b.box(Vector3(0.12, 0.20, 0.02), Vector3(x + end * 0.68, 2.64, z + side * 0.05), "red")
	_roof(b, body_length, half + 0.025, roof_base, 0.47, "roof")
	for x in [-l * 0.25, 0.0, l * 0.25]:
		b.box(Vector3(0.95, 0.10, 0.52), Vector3(x, h - 0.065, 0), "frame")
		for i in 7:
			b.box(Vector3(0.045, 0.035, 0.48), Vector3(x - 0.36 + i * 0.12, h - 0.025, 0), "roof")
	for end in [-1, 1]:
		_steps(b, end * l * 0.432, w * 0.495)
		var x = end * l * 0.48
		b.box(Vector3(0.085, roof_base - 1.40, w * 0.92), Vector3(x - end * 0.05, (roof_base + 1.40) * 0.5, 0), "paint")
		b.box(Vector3(0.04, 2.10, 1.13), Vector3(x + end * 0.012, 2.32, 0), "frame")
		b.box(Vector3(0.045, 0.68, 0.70), Vector3(x + end * 0.04, 2.75, 0), "glass")
		# Match RailVehicleConnections' existing gangway attachment rectangle.
		for side in [-1, 1]:
			b.box(Vector3(0.10, h * 0.54, 0.09), Vector3(x, h * 0.57, side * 0.67), "rubber")
		for y in [h * 0.30, h * 0.84]:
			b.box(Vector3(0.10, 0.09, 1.43), Vector3(x, y, 0), "rubber")

static func _container(b, l: float, w: float, h: float) -> void:
	var length = minf(12.20, l * 0.80)
	var width = minf(2.44, w * 0.84)
	var bottom = 1.26
	var top = h - 0.10
	b.box(Vector3(length, top - bottom, width), Vector3(0, (top + bottom) * 0.5, 0), "shade")
	for side in [-1, 1]:
		var z = side * width * 0.5
		b.box(Vector3(length - 0.15, top - bottom - 0.18, 0.035), Vector3(0, (top + bottom) * 0.5, z + side * 0.024), "paint")
		for i in int(length / 0.26):
			b.box(Vector3(0.095, top - bottom - 0.18, 0.06), Vector3(-length * 0.5 + 0.18 + i * 0.26, (top + bottom) * 0.5, z + side * 0.04), "edge")
		for y in [bottom + 0.04, top - 0.04]:
			b.box(Vector3(length, 0.10, 0.10), Vector3(0, y, z), "shade")
		for end in [-1, 1]:
			b.box(Vector3(0.10, top - bottom, 0.10), Vector3(end * (length * 0.5 - 0.04), (top + bottom) * 0.5, z), "edge")
			for y in [bottom + 0.06, top - 0.06]:
				b.box(Vector3(0.17, 0.14, 0.16), Vector3(end * (length * 0.5 - 0.04), y, z), "steel")
			b.cylinder(0.075, 0.13, Vector3(end * (length * 0.5 - 0.04), bottom - 0.09, z), "brass")
	for i in int(length / 0.28):
		b.box(Vector3(0.10, 0.035, width - 0.16), Vector3(-length * 0.5 + 0.18 + i * 0.28, top + 0.015, 0), "edge")
	for end in [-1, 1]:
		var x = end * (length * 0.5 + 0.02)
		for side in [-1, 1]:
			b.box(Vector3(0.035, top - bottom - 0.16, width * 0.47), Vector3(x, (top + bottom) * 0.5, side * width * 0.25), "paint")
			for z in [side * width * 0.14, side * width * 0.36]:
				b.pipe(Vector3(x + end * 0.06, bottom + 0.18, z), Vector3(x + end * 0.06, top - 0.18, z), 0.026, "steel")
				b.pipe(Vector3(x + end * 0.09, bottom + 0.66, z), Vector3(x + end * 0.09, bottom + 0.66, z + side * 0.19), 0.024, "steel")
			for y in [bottom + 0.3, (bottom + top) * 0.5, top - 0.3]:
				b.box(Vector3(0.07, 0.08, 0.22), Vector3(x + end * 0.04, y, side * width * 0.45), "steel")
		b.pipe(Vector3(end * l * 0.445, 1.26, -w * 0.39), Vector3(end * l * 0.445, 1.26, w * 0.39), 0.035, "steel")
		_steps(b, end * l * 0.445, w * 0.49)
	_handwheel(b, Vector3(l * 0.43, 1.87, w * 0.37), Vector3.BACK)

static func _handwheel(b, pos: Vector3, axis: Vector3) -> void:
	b.ring(0.17, 0.205, 0.035, pos, "brass", axis)
	var basis = Basis(Quaternion(Vector3.BACK, axis))
	for i in 5:
		var a = TAU * i / 5
		b.pipe(pos, pos + basis * Vector3(cos(a), sin(a), 0) * 0.185, 0.014, "brass")
	b.pipe(pos - Vector3.UP * 0.65, pos, 0.035, "frame")

static func _tanker(b, l: float, w: float, h: float) -> void:
	var r = minf(1.04, w * 0.35)
	var center_y = 2.22
	var barrel = l * 0.68
	b.cylinder(r, barrel, Vector3(0, center_y, 0), "paint", Vector3.RIGHT, -1, 64)
	for end in [-1, 1]:
		b.sphere(r, Vector3(end * barrel * 0.5, center_y, 0), "paint", Vector3(0.47, 1, 1), 48)
		b.box(Vector3(1.10, 0.10, w * 0.85), Vector3(end * l * 0.43, 1.20, 0), "frame")
		for z in [-w * 0.40, w * 0.40]:
			b.pipe(Vector3(end * l * 0.45, 1.26, z), Vector3(end * l * 0.45, 2.03, z), 0.026, "steel")
		b.pipe(Vector3(end * l * 0.45, 2.03, -w * 0.40), Vector3(end * l * 0.45, 2.03, w * 0.40), 0.028, "steel")
	for x in [-l * 0.25, l * 0.25]:
		b.ring(r - 0.01, r + 0.045, 0.085, Vector3(x, center_y, 0), "frame", Vector3.RIGHT)
		b.box(Vector3(0.55, 0.28, 1.70), Vector3(x, 1.27, 0), "frame")
		for side in [-1, 1]:
			b.box(Vector3(0.40, 0.45, 0.12), Vector3(x, 1.38, side * 0.72), "frame", Basis(Vector3.RIGHT, side * -0.25))
	var platform_y = center_y + r + 0.075
	b.box(Vector3(2.15, 0.07, 1.45), Vector3(0, platform_y, 0), "frame")
	for x in range(-7, 8):
		b.box(Vector3(0.035, 0.012, 1.38), Vector3(x * 0.14, platform_y + 0.045, 0), "steel")
	b.cylinder(0.32, 0.22, Vector3(0, platform_y + 0.12, 0), "frame")
	b.cylinder(0.36, 0.055, Vector3(0, platform_y + 0.26, 0), "steel")
	for i in 8:
		var a = TAU * i / 8
		b.cylinder(0.025, 0.07, Vector3(cos(a) * 0.29, platform_y + 0.29, sin(a) * 0.29), "brass", Vector3.UP, -1, 8)
	for side in [-1, 1]:
		var z = side * 0.72
		for x in [-1.04, 1.04]:
			b.pipe(Vector3(x, platform_y, z), Vector3(x, h - 0.055, z), 0.025, "steel")
		b.pipe(Vector3(-1.04, h - 0.055, z), Vector3(1.04, h - 0.055, z), 0.025, "steel")
		# Ladder clear of the tank skin, wheels and the underside brake rods.
		for x in [-0.38, 0.38]:
			b.line([Vector3(x, 1.23, side * 1.28), Vector3(x, 3.02, side * 1.28), Vector3(x, platform_y + 0.03, side * 0.75)], 0.025, "steel")
		for i in 7:
			b.pipe(Vector3(-0.38, 1.30 + i * 0.26, side * 1.28), Vector3(0.38, 1.30 + i * 0.26, side * 1.28), 0.023, "steel")
		b.box(Vector3(1.60, 0.23, 0.025), Vector3(-2.1, 1.08, side * w * 0.46), "black")
	_handwheel(b, Vector3(l * 0.43, 1.79, -w * 0.28), Vector3.BACK)
