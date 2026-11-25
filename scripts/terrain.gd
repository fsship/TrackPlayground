class_name RailTerrain
extends MeshInstance3D

const NX = 85
const NZ = 65
const WIDTH = 34.0
const DEPTH = 26.0
# One world unit is 100 model millimetres. Keep the original grid density.
const MIN_SIZE = 5.0
const MAX_SIZE = 100.0
var width = WIDTH
var depth = DEPTH
var nx = NX
var nz = NZ
var heights = PackedFloat32Array()
var paints = PackedFloat32Array()
var dirty = true
var refresh_time = 0.0
var collision_shape: CollisionShape3D

func _init() -> void:
	configure_size(WIDTH, DEPTH)
	var mat = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	material_override = mat

static func grid_size(new_width: float, new_depth: float) -> Vector2i:
	return Vector2i(roundi(new_width * (NX - 1) / WIDTH) + 1, roundi(new_depth * (NZ - 1) / DEPTH) + 1)

func configure_size(new_width: float, new_depth: float) -> void:
	width = clampf(new_width, MIN_SIZE, MAX_SIZE)
	depth = clampf(new_depth, MIN_SIZE, MAX_SIZE)
	var grid = grid_size(width, depth)
	nx = grid.x
	nz = grid.y
	heights.resize(nx * nz)
	paints.resize(nx * nz)
	heights.fill(0.0)
	paints.fill(0.0)
	dirty = true

func contains_point(point: Vector3, margin: float = 0.0) -> bool:
	return absf(point.x) <= width * 0.5 - margin and absf(point.z) <= depth * 0.5 - margin

func seed_landscape() -> void:
	for z in nz:
		for x in nx:
			var p = grid_point(x, z)
			var hill = 1.8 * exp(-((p.x + 1.0) * (p.x + 1.0) / 7.0 + (p.z + 0.5) * (p.z + 0.5) / 3.5))
			heights[z * nx + x] = hill
			paints[z * nx + x] = 0.0
	dirty = true

func grid_point(x: int, z: int) -> Vector3:
	return Vector3(float(x) / (nx - 1) * width - width * 0.5, heights[z * nx + x], float(z) / (nz - 1) * depth - depth * 0.5)

func height_at(x: float, z: float) -> float:
	var gx = clampf((x / width + 0.5) * (nx - 1), 0, nx - 1.001)
	var gz = clampf((z / depth + 0.5) * (nz - 1), 0, nz - 1.001)
	var ix = int(gx)
	var iz = int(gz)
	return lerpf(lerpf(heights[iz * nx + ix], heights[iz * nx + ix + 1], gx - ix), lerpf(heights[(iz + 1) * nx + ix], heights[(iz + 1) * nx + ix + 1], gx - ix), gz - iz)

func brush(center: Vector3, radius: float, strength: float, mode: String, dt: float, flatten_height: float = 0.0) -> void:
	var old = heights.duplicate() if mode == "smooth" else heights
	var x0 = clampi(floori(((center.x - radius) / width + 0.5) * (nx - 1)), 0, nx - 1)
	var x1 = clampi(ceili(((center.x + radius) / width + 0.5) * (nx - 1)), 0, nx - 1)
	var z0 = clampi(floori(((center.z - radius) / depth + 0.5) * (nz - 1)), 0, nz - 1)
	var z1 = clampi(ceili(((center.z + radius) / depth + 0.5) * (nz - 1)), 0, nz - 1)
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			var idx = z * nx + x
			var p = grid_point(x, z)
			var d = Vector2(p.x - center.x, p.z - center.z).length() / radius
			if d >= 1.0:
				continue
			var weight = pow(1.0 - d * d, 2) * strength * dt
			if mode == "raise":
				heights[idx] = minf(4.0, heights[idx] + weight)
			elif mode == "lower":
				heights[idx] = maxf(-0.8, heights[idx] - weight)
			elif mode == "flatten":
				heights[idx] = lerpf(heights[idx], flatten_height, minf(weight * 4.0, 1.0))
			elif mode == "smooth":
				var average = (old[z * nx + maxi(x - 1, 0)] + old[z * nx + mini(x + 1, nx - 1)] + old[maxi(z - 1, 0) * nx + x] + old[mini(z + 1, nz - 1) * nx + x]) * 0.25
				heights[idx] = lerpf(old[idx], average, minf(weight * 5.0, 1.0))
			elif mode == "paint":
				paints[idx] = minf(1.0, paints[idx] + weight)
			elif mode == "grass":
				paints[idx] = maxf(0.0, paints[idx] - weight)
	dirty = true

func _process(delta: float) -> void:
	refresh_time += delta
	if dirty and refresh_time > 0.08:
		rebuild()
		refresh_time = 0.0

func rebuild() -> void:
	var vertices = PackedVector3Array()
	var normals = PackedVector3Array()
	var colors = PackedColorArray()
	var indices = PackedInt32Array()
	for z in nz:
		for x in nx:
			var p = grid_point(x, z)
			vertices.append(p)
			var dx = height_at(p.x + 0.2, p.z) - height_at(p.x - 0.2, p.z)
			var dz = height_at(p.x, p.z + 0.2) - height_at(p.x, p.z - 0.2)
			normals.append(Vector3(-dx, 0.4, -dz).normalized())
			var noise = sin(x * 12.78 + z * 77.13) * 0.025
			var color = Color("788a5b").lerp(Color("a0a18a"), clampf(p.y / 4.0, 0, 0.8)).lightened(noise)
			color = color.lerp(Color("ad9671"), paints[z * nx + x])
			if p.y < -0.1:
				color = Color("b4a786")
			colors.append(color)
			if x < nx - 1 and z < nz - 1:
				var a = z * nx + x
				indices.append_array(PackedInt32Array([a, a + 1, a + nx, a + 1, a + nx + 1, a + nx]))
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var result = ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh = result
	if not is_instance_valid(collision_shape):
		var body = StaticBody3D.new()
		collision_shape = CollisionShape3D.new()
		body.add_child(collision_shape)
		add_child(body)
	var ground_shape = mesh.create_trimesh_shape()
	ground_shape.backface_collision = true
	collision_shape.shape = ground_shape
	dirty = false

func ray_hit(origin: Vector3, direction: Vector3) -> Vector3:
	var prev = origin
	var ray_length = origin.length() + Vector2(width, depth).length() + 8.0
	for i in range(1, ceili(ray_length / 0.13)):
		var p = origin + direction * (i * 0.13)
		if contains_point(p) and p.y <= height_at(p.x, p.z):
			var lo = prev
			var hi = p
			for j in range(9):
				var mid = (lo + hi) * 0.5
				if mid.y > height_at(mid.x, mid.z):
					lo = mid
				else:
					hi = mid
			return (lo + hi) * 0.5
		prev = p
	return Vector3.INF
