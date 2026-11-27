class_name RailSteamLocomotive
extends Node3D
## Original 2-8-2 model in prototype metres. Static details are merged by
## material and cached; only axles and valve gear remain separate drawables.
## SY-inspired proportions and livery, not a measured replica of a real engine.

const DRIVER_X = [-2.65, -0.9, 0.85, 2.6]
const DRIVER_RADIUS = 0.78
const CRANK = 0.29
const SAND_PIPE_RADIUS = 0.016
const SAND_PIPE_FRAME_Z = 0.842
const PALETTE = {
	"boiler": [Color("293236"), 0.48, 0.55],
	"black": [Color("171e22"), 0.68, 0.35],
	"red": [Color("8d302c"), 0.45, 0.45],
	"steel": [Color("9ca9ae"), 0.3, 0.8],
	"darksteel": [Color("4d5b60"), 0.52, 0.65],
	"brass": [Color("c19852"), 0.32, 0.7],
	"glass": [Color("517985"), 0.2, 0.55],
	"coal": [Color("24282b"), 0.92, 0.12],
	"lamp": [Color("ffe7af"), 0.35, 0.1],
	"fire": [Color("f88830"), 0.65, 0.0]
}
static var meshes: Dictionary = {}
static var shared_materials: Dictionary = {}
var model: Node3D
var axles: Array = []
var gear: Array = []
var tender = false
var factor = 1.0
var wheel_travel = 0.0
var last_distance = -1.0
var smoke: Node3D

class ChimneySmoke extends Node3D:
	# Small reusable world-space sprite pool. No particle renderer dependency;
	# old puffs stay behind the moving train and freeze with the simulation.
	var emitting = false
	var speed_scale = 1.0
	var factor = 1.0
	var puffs: Array = []
	var emission_clock = 0.0
	var next_puff = 0
	var rng = RandomNumberGenerator.new()

	func _ready() -> void:
		rng.seed = 808
		var texture_image = Image.create(64, 64, false, Image.FORMAT_RGBA8)
		for y in 64:
			for x in 64:
				var uv = (Vector2(x, y) + Vector2.ONE * 0.5) / 32.0 - Vector2.ONE
				var falloff = pow(maxf(0.0, 1.0 - uv.length_squared()), 2.0)
				var noise = 0.78 + 0.12 * sin(x * 0.36 + sin(y * 0.21)) + 0.10 * cos(y * 0.47 + x * 0.12)
				texture_image.set_pixel(x, y, Color(1, 1, 1, falloff * noise))
		var texture = ImageTexture.create_from_image(texture_image)
		var quad = QuadMesh.new()
		quad.size = Vector2.ONE * factor
		for i in 24:
			var puff = MeshInstance3D.new()
			puff.mesh = quad
			puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var mat = StandardMaterial3D.new()
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
			mat.albedo_texture = texture
			puff.material_override = mat
			add_child(puff)
			puff.set_as_top_level(true)
			puff.visible = false
			puffs.append({"node":puff, "material":mat, "age":4.0, "origin":Vector3.ZERO, "drift":Vector3.ZERO})

	func _process(dt: float) -> void:
		dt *= speed_scale
		if dt <= 0.0:
			return
		emission_clock += dt if emitting else 0.0
		if emitting and emission_clock >= 0.14:
			emission_clock = fmod(emission_clock, 0.14)
			var puff: Dictionary = puffs[next_puff]
			next_puff = (next_puff + 1) % puffs.size()
			puff.age = 0.0
			puff.origin = global_position
			puff.drift = Vector3(rng.randf_range(-0.18, 0.18), rng.randf_range(1.0, 1.5), rng.randf_range(-0.16, 0.16)) * factor
		for puff in puffs:
			puff.age += dt
			puff.node.visible = puff.age < 3.0
			if not puff.node.visible:
				continue
			var age: float = puff.age
			puff.node.global_position = puff.origin + puff.drift * age + Vector3(0.06, 0.08, 0.035) * factor * age * age
			puff.node.scale = Vector3.ONE * (0.38 + age * 0.60)
			var opacity = 0.50 * minf(age / 0.18, 1.0) * pow(1.0 - age / 3.0, 0.7)
			puff.material.albedo_color = Color(0.76, 0.78, 0.79, opacity)

class Builder extends RefCounted:
	var surfaces: Dictionary = {}

	func add(mesh: Mesh, pos: Vector3, mat: String, basis: Basis = Basis.IDENTITY) -> void:
		if not surfaces.has(mat):
			var st = SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			surfaces[mat] = st
		surfaces[mat].append_from(mesh, 0, Transform3D(basis, pos))

	func box(size: Vector3, pos: Vector3, mat: String, basis: Basis = Basis.IDENTITY) -> void:
		var mesh = BoxMesh.new()
		mesh.size = size
		add(mesh, pos, mat, basis)

	func cylinder(r: float, h: float, pos: Vector3, mat: String, axis: Vector3 = Vector3.UP, top: float = -1, segments: int = 32) -> void:
		var mesh = CylinderMesh.new()
		mesh.bottom_radius = r
		mesh.top_radius = r if top < 0 else top
		mesh.height = h
		mesh.radial_segments = segments
		mesh.rings = 1
		add(mesh, pos, mat, Basis(Quaternion(Vector3.UP, axis)))

	func sphere(r: float, pos: Vector3, mat: String, size: Vector3 = Vector3.ONE, segments: int = 16) -> void:
		var mesh = SphereMesh.new()
		mesh.radius = r
		mesh.height = r * 2
		mesh.radial_segments = segments
		mesh.rings = 8
		add(mesh, pos, mat, Basis.from_scale(size))

	func ring(inner: float, outer: float, depth: float, pos: Vector3, mat: String, axis: Vector3 = Vector3.UP) -> void:
		var mesh = TorusMesh.new()
		mesh.inner_radius = inner
		mesh.outer_radius = outer
		mesh.rings = 48
		mesh.ring_segments = 8
		add(mesh, pos, mat, Basis(Quaternion(Vector3.UP, axis)).scaled_local(Vector3(1, depth / (outer - inner), 1)))

	func pipe(a: Vector3, b: Vector3, r: float, mat: String) -> void:
		cylinder(r, a.distance_to(b), (a + b) / 2, mat, (b - a).normalized(), -1, 10)

	func line(points: Array, r: float, mat: String) -> void:
		for i in range(points.size() - 1):
			pipe(points[i], points[i + 1], r, mat)
			if i > 0:
				sphere(r, points[i], mat, Vector3.ONE, 8)

	func rivet(pos: Vector3, axis: Vector3 = Vector3.BACK, mat: String = "darksteel") -> void:
		cylinder(0.026, 0.022, pos, mat, axis, 0.020, 8)

	func finish(materials: Dictionary) -> ArrayMesh:
		var mesh = ArrayMesh.new()
		for key in surfaces:
			surfaces[key].index()
			surfaces[key].commit(mesh)
			mesh.surface_set_material(mesh.get_surface_count() - 1, materials[key])
		return mesh

static func create(is_tender: bool, ratio: float) -> Node3D:
	_prepare_meshes()
	var root = new()
	root.name = "SteamTender" if is_tender else "SteamLocomotive"
	root.tender = is_tender
	root.factor = 10.0 / ratio
	root.model = Node3D.new()
	root.model.name = "PrototypeMetres"
	root.model.scale = Vector3.ONE * root.factor
	root.add_child(root.model)
	root._instance("tender" if is_tender else "body", root.model)
	if is_tender:
		var spec = preload("res://scripts/running_gear.gd").layout({"id":"core:steam_tender"})
		for x in [-spec.center, spec.center]:
			var pivot = preload("res://scripts/running_gear.gd").add_pivot(root, root.model, x, spec.height, root.factor)
			root._instance("tender_bogie", pivot).position.y = -spec.height
			for offset in spec.axles:
				root._axle(offset, spec.radius, "small_wheel", pivot, spec.height)
		root._nameplate("SY 0808", Vector3(0, 2.45, 1.535), 0.0, 0.008)
		root._nameplate("SY 0808", Vector3(0, 2.45, -1.535), PI, 0.008)
	else:
		for x in DRIVER_X:
			root._axle(x, DRIVER_RADIUS, "driver")
		root._axle(5.35, 0.48, "small_wheel")
		root._axle(-5.45, 0.48, "small_wheel")
		for side in [-1, 1]:
			var coupling = root._instance("coupling", root.model)
			var connecting = root._instance("connecting", root.model)
			var slider = root._instance("slider", root.model)
			var valve = root._instance("valve", root.model)
			var links = []
			for i in 4:
				links.append(root._instance("valve_link", root.model))
			root.gear.append({"side":side, "coupling":coupling, "connecting":connecting, "slider":slider, "valve":valve, "links":links})
		root._nameplate("SY 0808", Vector3(-4.78, 2.30, 1.567), 0.0, 0.005)
		root._nameplate("SY 0808", Vector3(-4.78, 2.30, -1.567), PI, 0.005)
		root._nameplate("0808", Vector3(5.245, 2.39, 0), PI / 2, 0.004)
	root.set_travel(0.0)
	return root

func _instance(key: String, parent: Node3D) -> MeshInstance3D:
	var node = MeshInstance3D.new()
	node.name = key
	node.mesh = meshes[key]
	parent.add_child(node)
	return node

func _axle(x: float, radius: float, key: String, parent: Node3D = null, pivot_height: float = 0.0) -> void:
	var wheel = _instance(key, model if parent == null else parent)
	wheel.position = Vector3(x, radius - pivot_height, 0)
	axles.append({"node":wheel, "radius":radius})

func _nameplate(text: String, pos: Vector3, yaw: float, pixel: float) -> void:
	var plate = Label3D.new()
	plate.text = text
	plate.font_size = 64
	plate.pixel_size = pixel
	plate.modulate = Color("f3dfaa")
	plate.outline_size = 0
	plate.no_depth_test = false
	plate.position = pos
	plate.rotation.y = yaw
	model.add_child(plate)

func sync_motion(distance: float, velocity: float, paused: bool, derailed: bool) -> void:
	# Odometer deltas survive route trimming and do not jump on reverse. Rebuilds
	# establish a fresh baseline; preview nodes never receive this call.
	if last_distance >= 0 and not derailed:
		var delta_distance = distance - last_distance
		if delta_distance >= 0:
			wheel_travel += delta_distance * (-1.0 if velocity < 0 else 1.0)
	last_distance = distance
	set_travel(wheel_travel)
	if not tender and is_inside_tree() and DisplayServer.get_name() != "headless":
		if not smoke:
			_create_smoke()
		smoke.global_position = model.to_global(Vector3(4.05, 4.24, 0))
		smoke.emitting = absf(velocity) > 0.15 and not derailed
		smoke.speed_scale = 0.0 if paused else 1.0

func set_travel(distance: float) -> void:
	for axle in axles:
		axle.node.rotation.z = fposmod(-distance / axle.radius, TAU)
	var phase = fposmod(-distance / DRIVER_RADIUS, TAU)
	for linkage in gear:
		var side: int = linkage.side
		var angle = phase + (PI / 2 if side < 0 else 0.0)
		var offset = Vector3(cos(angle) * CRANK, sin(angle) * CRANK, 0)
		linkage.coupling.position = Vector3(0, DRIVER_RADIUS, side * 0.95) + offset
		var crank = Vector3(0.85, DRIVER_RADIUS, side * 1.09) + offset
		var piston = Vector3(crank.x + sqrt(3.35 * 3.35 - pow(0.90 - crank.y, 2)), 0.90, side * 1.09)
		linkage.connecting.position = (crank + piston) / 2
		linkage.connecting.rotation.z = atan2(piston.y - crank.y, piston.x - crank.x)
		linkage.slider.position = piston
		linkage.valve.position = Vector3(3.65 + cos(angle + 0.45) * 0.13, 1.34, side * 1.15)
		var gear_z = side * 1.23
		var crank_outer = Vector3(crank.x, crank.y, gear_z)
		var eccentric = crank_outer + Vector3(cos(angle + 1.2), sin(angle + 1.2), 0) * 0.21
		var rocker = Vector3(3.03 + cos(angle + 0.5) * 0.12, 1.35 + sin(angle + 0.5) * 0.07, gear_z)
		_set_link(linkage.links[0], crank_outer, eccentric)
		_set_link(linkage.links[1], eccentric, rocker)
		_set_link(linkage.links[2], rocker, Vector3(3.18, 1.73, gear_z))
		_set_link(linkage.links[3], Vector3(piston.x, piston.y, gear_z), Vector3(linkage.valve.position.x + 0.70, 1.34, gear_z))

func _set_link(node: Node3D, a: Vector3, b: Vector3) -> void:
	node.position = (a + b) * 0.5
	node.basis = Basis(Vector3.BACK, atan2(b.y - a.y, b.x - a.x)).scaled_local(Vector3(a.distance_to(b), 1, 1))

func _create_smoke() -> void:
	smoke = ChimneySmoke.new()
	smoke.name = "ChimneySmoke"
	smoke.factor = factor
	add_child(smoke)
	smoke.set_as_top_level(true)
	smoke.global_basis = Basis.IDENTITY

static func _prepare_meshes() -> void:
	if not meshes.is_empty():
		return
	for key in PALETTE:
		var mat = StandardMaterial3D.new()
		mat.albedo_color = PALETTE[key][0]
		mat.roughness = PALETTE[key][1]
		mat.metallic = PALETTE[key][2]
		if key in ["lamp", "fire"]:
			mat.emission_enabled = true
			mat.emission = PALETTE[key][0]
			mat.emission_energy_multiplier = 0.7
		shared_materials[key] = mat
	meshes.body = _body()
	meshes.tender = _tender()
	meshes.tender_bogie = _tender_bogie()
	meshes.driver = _wheelset(DRIVER_RADIUS, true)
	meshes.small_wheel = _wheelset(0.48, false)
	var b = Builder.new()
	b.box(Vector3(5.25, 0.12, 0.10), Vector3(-0.025, 0, 0), "steel")
	for x in DRIVER_X:
		b.ring(0.070, 0.142, 0.12, Vector3(x, 0, 0), "steel", Vector3.BACK)
	meshes.coupling = b.finish(shared_materials)
	b = Builder.new()
	b.box(Vector3(3.35, 0.135, 0.10), Vector3.ZERO, "steel")
	for x in [-1.675, 1.675]:
		b.cylinder(0.14, 0.13, Vector3(x, 0, 0), "steel", Vector3.BACK)
		b.cylinder(0.065, 0.15, Vector3(x, 0, 0), "brass", Vector3.BACK)
	meshes.connecting = b.finish(shared_materials)
	b = Builder.new()
	b.box(Vector3(0.34, 0.24, 0.22), Vector3.ZERO, "darksteel")
	b.cylinder(0.05, 1.25, Vector3(0.58, 0, 0), "steel", Vector3.RIGHT)
	meshes.slider = b.finish(shared_materials)
	b = Builder.new()
	b.box(Vector3(1.45, 0.055, 0.055), Vector3.ZERO, "steel")
	b.cylinder(0.085, 0.075, Vector3(-0.7, 0, 0), "brass", Vector3.BACK)
	meshes.valve = b.finish(shared_materials)
	b = Builder.new()
	b.box(Vector3(1, 0.06, 0.055), Vector3.ZERO, "steel")
	meshes.valve_link = b.finish(shared_materials)

static func _wheelset(radius: float, driven: bool) -> ArrayMesh:
	var b = Builder.new()
	b.cylinder(0.095, 1.65, Vector3.ZERO, "darksteel", Vector3.BACK)
	for side in [-1, 1]:
		var z = side * 0.745
		b.ring(radius - 0.10, radius, 0.14, Vector3(0, 0, z), "steel", Vector3.BACK)
		b.ring(radius - 0.055, radius + 0.025, 0.035, Vector3(0, 0, z - side * 0.075), "darksteel", Vector3.BACK)
		b.ring(radius - 0.16, radius - 0.09, 0.13, Vector3(0, 0, z), "red", Vector3.BACK)
		var phase = PI / 2 if side < 0 and driven else 0.0
		for i in (16 if driven else 10):
			var angle = TAU * i / (16.0 if driven else 10.0) + phase
			var p = Vector3(cos(angle), sin(angle), 0)
			b.box(Vector3(radius - 0.19, 0.062 if driven else 0.052, 0.10), p * (radius + 0.01) * 0.5 + Vector3(0, 0, z), "red", Basis(Vector3.BACK, angle))
		b.cylinder(0.17, 0.21, Vector3(0, 0, z), "red", Vector3.BACK)
		b.cylinder(0.09, 0.23, Vector3(0, 0, z), "steel", Vector3.BACK)
		if driven:
			var crank = Vector3(cos(phase) * CRANK, sin(phase) * CRANK, z + side * 0.10)
			b.box(Vector3(0.40, 0.18, 0.13), Vector3(cos(phase) * 0.15, sin(phase) * 0.15, z), "red", Basis(Vector3.BACK, phase))
			b.cylinder(0.085, 0.26, crank, "steel", Vector3.BACK)
			# Crescent counterweights opposite each crank; spokes stay open.
			for j in 9:
				var a = phase + PI + (j - 4) * 0.12
				b.box(Vector3(0.22, 0.10, 0.15), Vector3(cos(a) * 0.51, sin(a) * 0.51, z), "red", Basis(Vector3.BACK, a))
	return b.finish(shared_materials)

static func _buffers(b: Builder, x: float, width: float) -> void:
	b.box(Vector3(0.20, 0.36, width), Vector3(x, 0.97, 0), "red")
	var sign_x = signf(x)
	for z in [-1.02, 1.02]:
		b.cylinder(0.11, 0.28, Vector3(x + sign_x * 0.20, 0.98, z), "darksteel", Vector3.RIGHT)
		b.cylinder(0.23, 0.075, Vector3(x + sign_x * 0.36, 0.98, z), "black", Vector3.RIGHT)
		b.line([Vector3(x + sign_x * 0.16, 0.92, z * 0.45), Vector3(x + sign_x * 0.22, 0.52, z * 0.45), Vector3(x + sign_x * 0.32, 0.46, z * 0.34)], 0.046, "black")
	# Central shanks are articulated by RailVehicleConnections.
	for z in [-1.3, -0.8, 0.8, 1.3]:
		b.rivet(Vector3(x + sign_x * 0.11, 0.97, z), Vector3.RIGHT, "steel")

static func sand_pipe_paths(side: int) -> Array:
	var paths = []
	# Two outlets on the sand dome follow the boiler jacket, then descend
	# through wheel gaps on the frame side of the coupling rods. The running
	# board's inner edge is at |z| = 1.05, so these pipes pass behind it.
	for route in [[0.48, 0.0, -0.9], [0.82, 3.50, 2.6]]:
		var outlet_x: float = route[0]
		var drop_x: float = route[1]
		var axle_x: float = route[2]
		paths.append([
			Vector3(outlet_x, 3.65, side * 0.36),
			Vector3(outlet_x, 3.40, side * 0.64),
			Vector3(drop_x, 3.05, side * 0.99),
			Vector3(drop_x, 2.28, side * 0.99),
			Vector3(drop_x, 2.10, side * SAND_PIPE_FRAME_Z),
			Vector3(drop_x, 1.51, side * SAND_PIPE_FRAME_Z),
			Vector3(drop_x, 0.30, side * SAND_PIPE_FRAME_Z),
			Vector3(axle_x + 0.64, 0.16, side * 0.80),
			Vector3(axle_x + 0.52, 0.08, side * 0.745)
		])
	return paths

static func _body() -> ArrayMesh:
	var b = Builder.new()
	# Frame, firebox and running boards.
	_underframe(b)
	for side in [-1, 1]:
		b.box(Vector3(11.7, 0.10, 0.40), Vector3(0.2, 1.78, side * 1.25), "black")
		b.box(Vector3(11.7, 0.055, 0.035), Vector3(0.2, 1.8, side * 1.46), "steel")
		for x in [-3.0, -1.25, 0.5, 2.25, 4.5]:
			b.box(Vector3(0.16, 0.54, 0.16), Vector3(x, 1.43, side * 1.04), "red", Basis(Vector3.RIGHT, side * -0.45))
		for x in DRIVER_X:
			for layer in 4:
				b.box(Vector3(0.91 - layer * 0.12, 0.035, 0.13), Vector3(x, 1.27 + layer * 0.045, side * 0.58), "darksteel")
		b.box(Vector3(1.7, 0.14, 0.18), Vector3(4.0, 0.70, side * 1.08), "darksteel")
		b.box(Vector3(0.12, 0.29, 0.26), Vector3(3.18, 1.62, side * 1.12), "black")
		b.cylinder(0.075, 0.12, Vector3(3.18, 1.73, side * 1.23), "brass", Vector3.BACK)
		# Twin cylinders with bolted end covers and valve chests.
		b.cylinder(0.36, 1.18, Vector3(4.92, 0.93, side * 1.05), "black", Vector3.RIGHT)
		for x in [4.30, 5.54]:
			b.cylinder(0.38, 0.07, Vector3(x, 0.93, side * 1.05), "darksteel", Vector3.RIGHT)
			for j in 12:
				var a = TAU * j / 12
				b.rivet(Vector3(x + 0.045, 0.93 + sin(a) * 0.30, side * 1.05 + cos(a) * 0.30), Vector3.RIGHT, "steel")
		b.cylinder(0.18, 1.06, Vector3(4.90, 1.37, side * 1.05), "boiler", Vector3.RIGHT)
		b.line([Vector3(4.72, 1.52, side * 1.03), Vector3(4.72, 2.16, side * 0.97), Vector3(4.05, 2.55, side * 0.75)], 0.10, "black")
		# Sand lines, brake pipes and handrail stanchions.
		for path in sand_pipe_paths(side):
			# Brass fittings above the footplate; the frame-mounted delivery
			# tubes are dark steel, with only a short rail-facing nozzle exposed.
			b.line(path.slice(0, 5), SAND_PIPE_RADIUS, "brass")
			b.line(path.slice(4), SAND_PIPE_RADIUS, "darksteel")
			var drop_x: float = path[5].x
			b.pipe(Vector3(drop_x, 1.51, side * 0.64), path[5], 0.012, "darksteel")
			b.ring(0.017, 0.029, 0.030, path[5], "darksteel")
			b.ring(0.017, 0.025, 0.035, path[4], "brass")
		b.line([Vector3(-3.6, 2.78, side * 1.05), Vector3(4.5, 2.78, side * 1.05), Vector3(4.96, 2.50, side * 0.86)], 0.027, "steel")
		for x in [-3.35, -1.8, -0.25, 1.3, 2.85, 4.4]:
			b.pipe(Vector3(x, 2.78, side * 0.85), Vector3(x, 2.78, side * 1.05), 0.023, "darksteel")
		b.line([Vector3(-5.5, 1.63, side * 1.43), Vector3(-3.7, 1.63, side * 1.43), Vector3(-3.25, 1.97, side * 1.0), Vector3(3.7, 1.97, side * 1.0)], 0.045, "darksteel")
	b.box(Vector3(2.3, 1.18, 1.65), Vector3(-3.25, 1.85, 0), "black")
	b.cylinder(0.92, 6.8, Vector3(-0.15, 2.65, 0), "boiler", Vector3.RIGHT, -1, 64)
	b.cylinder(0.94, 1.80, Vector3(4.15, 2.65, 0), "black", Vector3.RIGHT, -1, 64)
	for x in [-3.45, -2.30, -0.60, 1.15, 2.95, 3.28]:
		b.cylinder(0.941, 0.048, Vector3(x, 2.65, 0), "darksteel", Vector3.RIGHT, -1, 64)
	# Smokebox door, hinges, radial dogs and handwheel.
	b.cylinder(0.88, 0.09, Vector3(5.085, 2.65, 0), "darksteel", Vector3.RIGHT, -1, 64)
	b.cylinder(0.78, 0.08, Vector3(5.14, 2.65, 0), "black", Vector3.RIGHT, -1, 64)
	b.ring(0.76, 0.80, 0.04, Vector3(5.185, 2.65, 0), "steel", Vector3.RIGHT)
	for i in 16:
		var a = TAU * i / 16
		b.rivet(Vector3(5.20, 2.65 + cos(a) * 0.84, sin(a) * 0.84), Vector3.RIGHT)
	for i in 8:
		var a = TAU * i / 8
		b.box(Vector3(0.065, 0.17, 0.065), Vector3(5.22, 2.65 + cos(a) * 0.72, sin(a) * 0.72), "steel", Basis(Vector3.RIGHT, a))
	b.ring(0.135, 0.17, 0.026, Vector3(5.25, 2.73, 0), "brass", Vector3.RIGHT)
	for i in 4:
		var a = TAU * i / 4
		b.pipe(Vector3(5.25, 2.73, 0), Vector3(5.25, 2.73 + cos(a) * 0.15, sin(a) * 0.15), 0.013, "brass")
	for y in [2.23, 3.03]:
		b.box(Vector3(0.12, 0.10, 0.32), Vector3(5.21, y, 0.61), "darksteel")
	# Hollow chimney with flared rim, steam dome, sand dome and whistle.
	b.cylinder(0.37, 0.18, Vector3(4.05, 3.56, 0), "black", Vector3.UP, 0.30, 48)
	b.cylinder(0.25, 0.52, Vector3(4.05, 3.89, 0), "boiler", Vector3.UP, 0.31, 48)
	b.cylinder(0.258, 0.015, Vector3(4.05, 4.154, 0), "black")
	b.ring(0.25, 0.34, 0.12, Vector3(4.05, 4.19, 0), "darksteel")
	for x in [-1.9, 0.65]:
		b.cylinder(0.46, 0.37, Vector3(x, 3.57, 0), "boiler", Vector3.UP, 0.38, 48)
		b.sphere(0.39, Vector3(x, 3.75, 0), "boiler", Vector3(1, 0.65, 1), 32)
		b.ring(0.42, 0.47, 0.055, Vector3(x, 3.48, 0), "darksteel")
	for z in [-0.22, 0.22]:
		b.cylinder(0.075, 0.32, Vector3(-2.75, 3.70, z), "brass")
		b.cylinder(0.12, 0.065, Vector3(-2.75, 3.88, z), "brass")
	b.cylinder(0.055, 0.40, Vector3(-3.05, 3.89, 0.47), "brass")
	b.line([Vector3(-3.05, 3.71, 0.47), Vector3(-3.48, 3.71, 0.47), Vector3(-3.85, 3.2, 0.6)], 0.023, "brass")
	# Compressor and finned reservoirs beside the boiler.
	for y in [2.20, 2.65]:
		b.cylinder(0.20, 0.38, Vector3(2.7, y, 1.16), "black")
		for j in 7:
			b.cylinder(0.22, 0.025, Vector3(2.7, y - 0.15 + j * 0.05, 1.16), "darksteel")
	b.cylinder(0.07, 0.9, Vector3(2.7, 2.42, 1.16), "steel")
	b.line([Vector3(2.7, 2.87, 1.16), Vector3(2.35, 3.05, 1.1), Vector3(1.5, 3.05, 0.85)], 0.035, "brass")
	for side in [-1, 1]:
		b.cylinder(0.23, 1.40, Vector3(-2.6, 1.59, side * 1.07), "black", Vector3.RIGHT)
	# Headlight: dark housing, reflector, lit glass and protective rim.
	b.box(Vector3(0.48, 0.15, 0.42), Vector3(4.92, 3.54, 0), "black")
	b.cylinder(0.24, 0.33, Vector3(5.01, 3.78, 0), "black", Vector3.RIGHT)
	b.cylinder(0.194, 0.025, Vector3(5.19, 3.78, 0), "lamp", Vector3.RIGHT)
	b.ring(0.193, 0.24, 0.04, Vector3(5.21, 3.78, 0), "brass", Vector3.RIGHT)
	_cab(b)
	_buffers(b, 6.40, 3.05)
	_buffers(b, -6.40, 3.05)
	# Slatted front pilot and open steps.
	for z in range(-6, 7):
		b.pipe(Vector3(6.38, 0.79, z * 0.20), Vector3(6.75, 0.30, z * 0.22), 0.038, "black")
	b.pipe(Vector3(6.75, 0.3, -1.37), Vector3(6.75, 0.3, 1.37), 0.065, "darksteel")
	for side in [-1, 1]:
		for j in 3:
			b.box(Vector3(0.42, 0.055, 0.38), Vector3(5.92, 0.48 + j * 0.40, side * 1.36), "darksteel")
		b.pipe(Vector3(5.72, 0.43, side * 1.49), Vector3(5.72, 1.78, side * 1.49), 0.028, "steel")
	return b.finish(shared_materials)

static func _underframe(b: Builder) -> void:
	# The load-bearing frame sits inside the wheel backs (|z| < 0.65),
	# leaving the open spokes and outside valve gear unobstructed.
	for side in [-1, 1]:
		var z = side * 0.49
		b.box(Vector3(12.7, 0.50, 0.20), Vector3(0, 1.12, z), "red")
		b.box(Vector3(12.7, 0.09, 0.30), Vector3(0, 1.40, z), "darksteel")
		b.box(Vector3(7.25, 0.09, 0.25), Vector3(-0.05, 0.86, z), "red")
		for x in DRIVER_X:
			# Pedestal jaws, axlebox covers and spring hangers behind each wheel.
			b.box(Vector3(0.40, 0.35, 0.23), Vector3(x, 0.80, z), "darksteel")
			b.box(Vector3(0.23, 0.22, 0.025), Vector3(x, 0.80, z + side * 0.128), "steel")
			for offset in [-0.29, 0.29]:
				b.box(Vector3(0.12, 0.53, 0.21), Vector3(x + offset, 0.93, z), "red")
				b.pipe(Vector3(x + offset, 1.04, z), Vector3(x + offset, 1.49, z), 0.032, "steel")
				b.cylinder(0.060, 0.045, Vector3(x + offset, 1.48, z), "darksteel")
			# Brake shoes tangent to the tyre; the hangers stay inboard of rods.
			b.box(Vector3(0.095, 0.27, 0.15), Vector3(x + 0.835, 0.78, side * 0.75), "black")
			b.pipe(Vector3(x + 0.86, 1.34, side * 0.77), Vector3(x + 0.835, 0.77, side * 0.77), 0.032, "darksteel")
			b.cylinder(0.055, 0.09, Vector3(x + 0.86, 1.34, side * 0.77), "steel", Vector3.BACK)
		for x in [-3.55, -1.775, -0.025, 1.725, 3.50]:
			b.box(Vector3(0.20, 0.63, 0.23), Vector3(x, 1.03, z), "red")
			for y in [0.84, 1.20]:
				b.rivet(Vector3(x, y, z + side * 0.13), Vector3.BACK, "steel")
		# Equalising beams and the longitudinal brake pull rod.
		for x in [-1.775, -0.025, 1.725]:
			b.box(Vector3(1.25, 0.085, 0.10), Vector3(x, 1.22, side * 0.61), "darksteel")
		b.pipe(Vector3(-4.0, 0.43, side * 0.40), Vector3(3.5, 0.43, side * 0.40), 0.027, "steel")
	for x in [-3.55, -1.775, -0.025, 1.725, 3.50]:
		b.box(Vector3(0.20, 0.20, 1.20), Vector3(x, 1.25, 0), "red")
		b.pipe(Vector3(x, 0.44, -0.57), Vector3(x, 0.44, 0.57), 0.045, "darksteel")
	# Boiler bearers and the substantial smokebox/cylinder saddle.
	for x in [-1.8, 0.4, 2.55]:
		b.box(Vector3(0.42, 0.34, 1.20), Vector3(x, 1.57, 0), "black")
		b.box(Vector3(0.61, 0.075, 1.30), Vector3(x, 1.41, 0), "darksteel")
	b.box(Vector3(1.25, 0.42, 1.40), Vector3(4.40, 1.52, 0), "black")
	b.box(Vector3(2.12, 0.13, 2.10), Vector3(5.30, 1.32, 0), "darksteel")
	for side in [-1, 1]:
		b.box(Vector3(2.12, 0.25, 0.11), Vector3(5.30, 1.20, side * 0.99), "red")
		for x in [4.44, 4.87, 5.30, 5.73, 6.16]:
			b.rivet(Vector3(x, 1.20, side * 1.055), Vector3.BACK, "steel")
	# Firebox foundation and tapered ashpan underneath the cab. The taper
	# clears the trailing axle and keeps the lower pan between the wheel backs.
	b.box(Vector3(2.10, 0.42, 1.30), Vector3(-4.55, 1.43, 0), "black")
	var pan = CylinderMesh.new()
	pan.radial_segments = 4
	pan.rings = 1
	pan.top_radius = 1.0
	pan.bottom_radius = 0.62
	pan.height = 0.66
	b.add(pan, Vector3(-4.60, 1.00, 0), "black", Basis.from_scale(Vector3(2.20 / sqrt(2.0), 1, 1.25 / sqrt(2.0))) * Basis(Vector3.UP, PI / 4))
	b.box(Vector3(2.22, 0.08, 1.29), Vector3(-4.60, 1.33, 0), "darksteel")
	for side in [-1, 1]:
		b.box(Vector3(0.75, 0.26, 0.055), Vector3(-4.35, 1.12, side * 0.575), "darksteel")
		b.pipe(Vector3(-5.63, 1.30, side * 0.65), Vector3(-3.62, 1.30, side * 0.65), 0.028, "steel")
		for x in [-5.48, -5.12, -4.76, -4.40, -4.04, -3.68]:
			b.rivet(Vector3(x, 1.34, side * 0.655))
		b.line([Vector3(-5.9, 1.35, side * 1.07), Vector3(-5.25, 1.13, side * 0.92), Vector3(-4.85, 1.13, side * 0.66)], 0.035, "darksteel")
	# Leading and trailing pony trucks: axleboxes, springs, triangulated
	# drawbars and pivot bearings connect the small wheels to the main frame.
	for x in [-5.45, 5.35]:
		var pivot_x = x - signf(x) * 0.85
		b.box(Vector3(1.72, 0.15, 1.02), Vector3(x, 0.67, 0), "black")
		b.cylinder(0.19, 0.20, Vector3(pivot_x, 0.87, 0), "darksteel")
		b.cylinder(0.11, 0.38, Vector3(pivot_x, 0.97, 0), "steel")
		for side in [-1, 1]:
			b.box(Vector3(0.33, 0.29, 0.22), Vector3(x, 0.49, side * 0.49), "darksteel")
			b.pipe(Vector3(x, 0.62, side * 0.48), Vector3(pivot_x, 0.87, side * 0.20), 0.07, "red")
			for layer in 5:
				b.box(Vector3(0.96 - layer * 0.12, 0.032, 0.13), Vector3(x, 0.88 + layer * 0.038, side * 0.47), "darksteel")
			for offset in [-0.49, 0.49]:
				b.pipe(Vector3(x + offset, 0.68, side * 0.47), Vector3(x + offset, 1.07, side * 0.47), 0.028, "steel")
			b.box(Vector3(0.08, 0.20, 0.12), Vector3(x + 0.53, 0.48, side * 0.74), "black")

static func _cab(b: Builder) -> void:
	b.box(Vector3(2.65, 0.14, 3.02), Vector3(-4.87, 1.48, 0), "black")
	# Real window openings: lower panels and thin posts, not painted-on windows.
	for side in [-1, 1]:
		b.box(Vector3(2.60, 1.22, 0.085), Vector3(-4.87, 2.12, side * 1.49), "boiler")
		b.box(Vector3(2.65, 0.16, 0.09), Vector3(-4.87, 3.84, side * 1.49), "boiler")
		for x in [-6.15, -5.20, -3.58]:
			b.box(Vector3(0.10, 1.04, 0.09), Vector3(x, 3.26, side * 1.49), "boiler")
		b.box(Vector3(0.78, 0.76, 0.035), Vector3(-5.65, 3.26, side * 1.49), "glass")
		for y in [2.76, 3.76]:
			b.box(Vector3(1.50, 0.045, 0.11), Vector3(-4.39, y, side * 1.51), "brass")
		b.box(Vector3(1.37, 0.38, 0.022), Vector3(-4.78, 2.30, side * 1.544), "red")
		for j in 19:
			var x = -6.05 + j * 0.13
			for y in [1.62, 2.66, 3.84]:
				b.rivet(Vector3(x, y, side * 1.54))
		for j in 8:
			b.rivet(Vector3(-6.10, 1.72 + j * 0.26, side * 1.54))
		# Rear entry grab irons, steps and a seat visible through the open window.
		for x in [-6.17, -5.42]:
			b.pipe(Vector3(x, 1.48, side * 1.59), Vector3(x, 2.91, side * 1.59), 0.028, "steel")
		for j in 3:
			b.box(Vector3(0.72, 0.055, 0.29), Vector3(-5.8, 0.45 + j * 0.36, side * 1.39), "darksteel")
		b.box(Vector3(0.55, 0.12, 0.48), Vector3(-4.85, 2.05, side * 0.96), "black")
		b.cylinder(0.045, 0.58, Vector3(-4.85, 1.77, side * 0.96), "steel")
	# Front wall and framed glazed front windows, open rear gangway.
	b.box(Vector3(0.10, 1.14, 2.93), Vector3(-3.56, 2.1, 0), "boiler")
	b.box(Vector3(0.10, 0.15, 2.93), Vector3(-3.56, 3.84, 0), "boiler")
	for z in [-1.44, -0.48, 0.48, 1.44]:
		b.box(Vector3(0.10, 1.04, 0.10), Vector3(-3.56, 3.25, z), "boiler")
	for z in [-0.96, 0.96]:
		b.box(Vector3(0.045, 0.86, 0.81), Vector3(-3.56, 3.26, z), "glass")
	# Curved roof with rain gutters and ventilator.
	for i in 24:
		var a = lerpf(-0.66, 0.66, (i + 0.5) / 24.0)
		b.box(Vector3(2.95, 0.075, 0.151), Vector3(-4.88, 1.50 + cos(a) * 2.7, sin(a) * 2.7), "black", Basis(Vector3.RIGHT, a))
	for side in [-1, 1]:
		b.pipe(Vector3(-6.36, 3.67, side * 1.64), Vector3(-3.4, 3.67, side * 1.64), 0.035, "darksteel")
	b.box(Vector3(0.78, 0.12, 0.82), Vector3(-4.95, 4.23, 0), "darksteel")
	b.box(Vector3(0.86, 0.045, 0.90), Vector3(-4.95, 4.31, 0), "black")
	# Backhead, firebox glow, gauges, valves and copper plumbing.
	b.box(Vector3(0.22, 1.70, 1.64), Vector3(-3.80, 2.40, 0), "black")
	b.cylinder(0.29, 0.04, Vector3(-3.94, 1.98, 0), "darksteel", Vector3.RIGHT)
	b.cylinder(0.21, 0.05, Vector3(-3.97, 1.98, 0), "fire", Vector3.RIGHT)
	for z in [-0.18, 0.0, 0.18]:
		b.box(Vector3(0.06, 0.44, 0.045), Vector3(-4.01, 1.98, z), "black")
	for z in [-0.45, 0.0, 0.45]:
		b.cylinder(0.13, 0.05, Vector3(-3.96, 3.02, z), "brass", Vector3.RIGHT)
		b.cylinder(0.103, 0.055, Vector3(-4.0, 3.02, z), "lamp", Vector3.RIGHT)
		b.pipe(Vector3(-4.04, 3.02, z), Vector3(-4.04, 3.08, z + 0.025), 0.009, "black")
		b.line([Vector3(-3.98, 2.90, z), Vector3(-3.98, 2.6, z), Vector3(-4.03, 2.5, z + 0.12)], 0.025, "brass")
	for z in [-0.65, 0.65]:
		b.ring(0.11, 0.14, 0.025, Vector3(-4.05, 2.55, z), "red", Vector3.RIGHT)
		b.pipe(Vector3(-4.05, 2.42, z), Vector3(-4.05, 2.68, z), 0.018, "red")
		b.pipe(Vector3(-4.05, 2.55, z - 0.13), Vector3(-4.05, 2.55, z + 0.13), 0.018, "red")

static func _tender() -> ArrayMesh:
	var b = Builder.new()
	b.box(Vector3(7.8, 0.30, 2.94), Vector3(0, 1.07, 0), "black")
	# Underframe girders, bogie bolsters and brake equipment fill the otherwise
	# empty centre below the water tank without enclosing the wheelsets.
	b.box(Vector3(7.0, 0.28, 0.38), Vector3(0, 0.84, 0), "black")
	for side in [-1, 1]:
		b.box(Vector3(7.35, 0.24, 0.13), Vector3(0, 0.92, side * 1.25), "black")
		b.box(Vector3(7.35, 0.065, 0.21), Vector3(0, 0.79, side * 1.25), "darksteel")
		for x in [-3.5, -2.25, -0.9, 0.9, 2.25, 3.5]:
			b.rivet(Vector3(x, 0.93, side * 1.325))
		b.pipe(Vector3(-3.35, 0.49, side * 0.38), Vector3(3.35, 0.49, side * 0.38), 0.027, "steel")
	for x in [-2.25, 0.0, 2.25]:
		b.box(Vector3(0.26, 0.18, 2.40), Vector3(x, 0.88, 0), "darksteel")
	b.cylinder(0.18, 1.28, Vector3(0.0, 0.62, 0.74), "black", Vector3.RIGHT)
	b.cylinder(0.14, 0.62, Vector3(0.15, 0.65, -0.68), "darksteel", Vector3.RIGHT)
	b.line([Vector3(0.48, 0.65, -0.68), Vector3(1.10, 0.65, -0.68), Vector3(1.35, 0.49, -0.38)], 0.033, "steel")
	b.box(Vector3(7.3, 1.60, 2.96), Vector3(-0.10, 2.05, 0), "boiler")
	b.box(Vector3(7.30, 0.09, 3.04), Vector3(-0.10, 2.88, 0), "darksteel")
	# Coal bunker with a recessed top, visible individual irregular lumps.
	b.box(Vector3(4.35, 0.10, 2.60), Vector3(1.1, 2.94, 0), "coal")
	for side in [-1, 1]:
		b.box(Vector3(4.45, 0.55, 0.095), Vector3(1.12, 3.08, side * 1.43), "boiler")
		b.box(Vector3(7.4, 0.055, 0.045), Vector3(-0.1, 2.64, side * 1.515), "brass")
		b.box(Vector3(7.4, 0.055, 0.045), Vector3(-0.1, 1.40, side * 1.515), "brass")
		for i in 40:
			var x = -3.60 + i * 0.18
			for y in [1.29, 2.79]:
				b.rivet(Vector3(x, y, side * 1.515))
		for x in [-3.6, -1.25, 1.2, 3.5]:
			for i in 8:
				b.rivet(Vector3(x, 1.43 + i * 0.17, side * 1.515))
	b.box(Vector3(0.1, 0.55, 2.86), Vector3(-1.1, 3.08, 0), "boiler")
	b.box(Vector3(0.1, 0.55, 2.86), Vector3(3.35, 3.08, 0), "boiler")
	var rng = RandomNumberGenerator.new()
	rng.seed = 808
	for ix in 19:
		for iz in 10:
			var x = -0.92 + ix * 0.22 + rng.randf_range(-0.06, 0.06)
			var z = -1.18 + iz * 0.26 + rng.randf_range(-0.06, 0.06)
			var y = 3.04 + 0.27 * sin((x + 1.1) / 4.5 * PI) * cos(z * 0.8)
			var mesh = SphereMesh.new()
			mesh.radius = rng.randf_range(0.13, 0.21)
			mesh.height = mesh.radius * 1.5
			mesh.radial_segments = 5
			mesh.rings = 2
			b.add(mesh, Vector3(x, y, z), "coal", Basis.from_euler(Vector3(rng.randf(), rng.randf(), rng.randf())).scaled_local(Vector3(1.2, 0.8, 1)))
	# Water hatch and rear ladder.
	b.cylinder(0.48, 0.13, Vector3(-2.5, 2.99, 0), "black")
	b.cylinder(0.42, 0.045, Vector3(-2.5, 3.08, 0), "darksteel")
	b.pipe(Vector3(-2.69, 3.16, 0), Vector3(-2.31, 3.16, 0), 0.035, "steel")
	for z in [-0.35, 0.35]:
		b.line([Vector3(-3.88, 0.78, z), Vector3(-3.88, 3.16, z), Vector3(-3.50, 3.16, z)], 0.03, "steel")
	for i in 8:
		b.pipe(Vector3(-3.89, 0.85 + i * 0.30, -0.35), Vector3(-3.89, 0.85 + i * 0.30, 0.35), 0.027, "steel")
	_buffers(b, 3.5, 3.05)
	_buffers(b, -3.5, 3.05)
	return b.finish(shared_materials)

static func _tender_bogie() -> ArrayMesh:
	var b = Builder.new()
	b.box(Vector3(2.05, 0.28, 1.02), Vector3(0, 0.61, 0), "black")
	b.cylinder(0.22, 0.18, Vector3(0, 0.90, 0), "darksteel")
	for side in [-1, 1]:
		b.box(Vector3(2.08, 0.14, 0.12), Vector3(0, 0.62, side * 0.91), "darksteel")
		for axle in [-0.7, 0.7]:
			b.box(Vector3(0.24, 0.28, 0.15), Vector3(axle, 0.49, side * 0.91), "black")
		for spring in [-0.30, 0.0, 0.30]:
			for j in 5:
				b.ring(0.065, 0.095, 0.032, Vector3(spring, 0.73 + j * 0.045, side * 0.89), "steel")
	return b.finish(shared_materials)
