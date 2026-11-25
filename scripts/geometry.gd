class_name RailGeometry
extends RefCounted

static var materials: Dictionary = {}

static func material(color: Color, roughness: float = 0.85, metallic: float = 0.0) -> StandardMaterial3D:
	var key = str(color) + str(roughness) + str(metallic)
	if not materials.has(key):
		var mat = StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = roughness
		mat.metallic = metallic
		if color.a < 0.99:
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		materials[key] = mat
	return materials[key]

static func box(parent: Node3D, size: Vector3, pos: Vector3, color: Color, metal: float = 0.0) -> MeshInstance3D:
	var node = MeshInstance3D.new()
	var mesh = BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = pos
	node.material_override = material(color, 0.8, metal)
	parent.add_child(node)
	return node

static func cylinder(parent: Node3D, radius: float, height: float, pos: Vector3, color: Color, top: float = -1.0) -> MeshInstance3D:
	var node = MeshInstance3D.new()
	var mesh = CylinderMesh.new()
	mesh.bottom_radius = radius
	mesh.top_radius = radius if top < 0.0 else top
	mesh.height = height
	mesh.radial_segments = 12
	node.mesh = mesh
	node.position = pos
	node.material_override = material(color)
	parent.add_child(node)
	return node

static func multibox(parent: Node3D, size: Vector3, transforms: Array, color: Color, metal: float = 0.0) -> void:
	if transforms.is_empty():
		return
	var mesh = BoxMesh.new()
	mesh.size = size
	mesh.material = material(color, 0.75, metal)
	var multi = MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = transforms.size()
	for i in transforms.size():
		multi.set_instance_transform(i, transforms[i])
	var instance = MultiMeshInstance3D.new()
	instance.multimesh = multi
	parent.add_child(instance)

static func track(paths: Array, gauge: float, preview: bool = false) -> Node3D:
	var root = Node3D.new()
	var sleeper_transforms = []
	var rail_transforms = []
	var ballast_transforms = []
	for pts in paths:
		var traversed = 0.0
		var next_tie = 0.0
		for i in range(pts.size() - 1):
			var a: Vector3 = pts[i]
			var b: Vector3 = pts[i + 1]
			var tangent = (b - a).normalized()
			var side = tangent.cross(Vector3.UP).normalized()
			var up = side.cross(tangent).normalized()
			var basis = Basis(tangent, up, side)
			var length = a.distance_to(b)
			var center = (a + b) * 0.5
			ballast_transforms.append(Transform3D(basis.scaled_local(Vector3(length + 0.008, 1, 1)), center + Vector3.UP * 0.018))
			for sign_value in [-1, 1]:
				rail_transforms.append(Transform3D(basis.scaled_local(Vector3(length + 0.006, 1, 1)), center + side * gauge * 0.5 * sign_value + Vector3.UP * 0.066))
			while next_tie < traversed + length:
				var p = a + tangent * (next_tie - traversed)
				sleeper_transforms.append(Transform3D(basis, p + Vector3.UP * 0.042))
				next_tie += gauge * 0.60
			traversed += length
	var tint = Color("65e0bc") if preview else Color("777e75")
	multibox(root, Vector3(1, 0.045, gauge * 2.45), ballast_transforms, tint)
	multibox(root, Vector3(gauge * 0.20, 0.028, gauge * 1.85), sleeper_transforms, Color("81efd2") if preview else Color("605344"))
	multibox(root, Vector3(1, 0.032, gauge * 0.115), rail_transforms, Color("b8ffdf") if preview else Color("bcc3ba"), 0.65)
	return root

static func custom_model(def: Dictionary, factor: float) -> Node3D:
	if not def.has("model_path"):
		return null
	var doc = GLTFDocument.new()
	var state = GLTFState.new()
	if doc.append_from_file(def.model_path, state) != OK:
		return null
	var model = doc.generate_scene(state)
	if model:
		model.scale = Vector3.ONE * factor * float(def.get("model_scale", 1.0))
	return model

static func vehicle(def: Dictionary, ratio: float) -> Node3D:
	var root = Node3D.new()
	var f = 10.0 / ratio
	var custom = custom_model(def, f)
	if custom:
		root.add_child(custom)
		return root
	var l: float = def.length_m * f
	var w: float = def.width_m * f
	var h: float = def.height_m * f
	var color = Color(str(def.get("color", "638c6a")))
	var black = Color("263139")
	box(root, Vector3(l, h * 0.12, w), Vector3(0, h * 0.22, 0), black)
	for bx in [-0.32, 0.32]:
		box(root, Vector3(l * 0.18, h * 0.13, w * 0.66), Vector3(l * bx, h * 0.13, 0), Color("303a3a"))
		for axle in [-0.05, 0.05]:
			for side in [-1, 1]:
				var wheel = cylinder(root, h * 0.105, w * 0.1, Vector3(l * (bx + axle), h * 0.105, side * w * 0.38), black)
				wheel.rotation.x = PI / 2
	if def.kind == "tanker":
		var tank = cylinder(root, w * 0.47, l * 0.9, Vector3(0, h * 0.57, 0), color)
		tank.rotation.z = PI / 2
		cylinder(root, w * 0.18, h * 0.12, Vector3(0, h * 0.95, 0), black)
	elif def.kind == "freight":
		box(root, Vector3(l * 0.91, h * 0.65, w * 0.95), Vector3(0, h * 0.6, 0), color)
		for i in range(14):
			for side in [-1, 1]:
				box(root, Vector3(l * 0.015, h * 0.59, w * 0.015), Vector3(l * (-0.43 + i * 0.066), h * 0.61, side * w * 0.48), color.lightened(0.12))
	else:
		box(root, Vector3(l * 0.96, h * 0.62, w * 0.94), Vector3(0, h * 0.58, 0), color)
		box(root, Vector3(l * 0.96, h * 0.08, w), Vector3(0, h * 0.92, 0), Color("ccd1c4"))
		for side in [-1, 1]:
			box(root, Vector3(l * 0.96, h * 0.08, w * 0.012), Vector3(0, h * 0.44, side * w * 0.477), Color("eedcb7"))
			if def.kind == "coach":
				for i in range(10):
					box(root, Vector3(l * 0.058, h * 0.23, w * 0.015), Vector3(l * (-0.4 + i * 0.089), h * 0.70, side * w * 0.478), Color("254752"), 0.25)
			else:
				for x in [-0.36, 0.36]:
					box(root, Vector3(l * 0.14, h * 0.24, w * 0.018), Vector3(l * x, h * 0.71, side * w * 0.478), Color("254752"))
				for i in range(7):
					box(root, Vector3(l * 0.025, h * 0.30, w * 0.018), Vector3(l * (-0.2 + i * 0.066), h * 0.65, side * w * 0.478), color.darkened(0.35))
		if def.kind == "locomotive":
			for side in [-1, 1]:
				box(root, Vector3(l * 0.015, h * 0.12, w * 0.65), Vector3(side * l * 0.485, h * 0.72, 0), Color("254752"))
				for z in [-0.3, 0.3]:
					box(root, Vector3(0.012, h * 0.07, w * 0.1), Vector3(side * l * 0.498, h * 0.44, z * w), Color("fff2ba"))
			for x in [-0.16, 0.12]:
				cylinder(root, w * 0.28, h * 0.045, Vector3(l * x, h * 0.98, 0), black)
			if def.id == "core:electric":
				for x in [-0.2, 0.2]:
					box(root, Vector3(l * 0.14, h * 0.04, w * 0.7), Vector3(l * x, h * 1.12, 0), black)
	for x in [-0.5, 0.5]:
		box(root, Vector3(f * 0.65, h * 0.07, w * 0.18), Vector3(l * x, h * 0.22, 0), black)
	return root

static func apply_preview_material(node: Node, mat: Material) -> void:
	# Includes nested meshes in imported GLB vehicles without changing their
	# shared mesh resources or the materials on real trains.
	if node is GeometryInstance3D:
		node.material_override = mat
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		apply_preview_material(child, mat)

static func scenery_model(def: Dictionary, ratio: float) -> Node3D:
	var root = Node3D.new()
	var custom = custom_model(def, 10.0 / ratio)
	if custom:
		root.add_child(custom)
		return root
	var f = 87.1 / ratio
	var c = Color(str(def.get("color", "739574")))
	if def.kind == "tree":
		cylinder(root, 0.07, 0.9, Vector3(0, 0.45, 0), Color("77644c"))
		for i in range(3):
			cylinder(root, 0.55 - i * 0.12, 0.95, Vector3(0, 0.85 + i * 0.36, 0), c.lightened(i * 0.06), 0.02)
	elif def.kind == "rock":
		var mesh = SphereMesh.new()
		mesh.radius = 0.5
		mesh.height = 0.85
		mesh.radial_segments = 7
		mesh.rings = 4
		var rock = MeshInstance3D.new()
		rock.mesh = mesh
		rock.material_override = material(c)
		rock.position.y = 0.23
		rock.scale = Vector3(1.2, 0.8, 1.0)
		root.add_child(rock)
	elif def.kind == "platform":
		box(root, Vector3(6, 0.18, 0.8), Vector3(0, 0.09, 0), c)
		box(root, Vector3(6, 0.02, 0.05), Vector3(0, 0.19, -0.35), Color("edd18a"))
	else:
		var length = 2.8 if def.kind == "station" else 1.3
		box(root, Vector3(length, 1.05, 1.05), Vector3(0, 0.525, 0), c)
		for side in [-1, 1]:
			var roof = box(root, Vector3(length + 0.25, 0.11, 0.76), Vector3(0, 1.16, side * 0.29), Color("93634f"))
			roof.rotation.x = side * 0.48
			for i in range(4 if def.kind == "station" else 2):
				box(root, Vector3(0.26, 0.32, 0.025), Vector3(-length * 0.34 + i * length * 0.23, 0.64, side * 0.53), Color("365561"))
		box(root, Vector3(0.28, 0.65, 0.03), Vector3(length * 0.28, 0.325, 0.53), Color("64584a"))
		if def.kind == "station":
			box(root, Vector3(length + 1.1, 0.08, 0.8), Vector3(0, 0.95, 0.9), Color("4f6263"))
			for x in [-1.6, 1.6]:
				box(root, Vector3(0.05, 0.95, 0.05), Vector3(x, 0.475, 1.2), Color("4f6263"))
	root.scale = Vector3.ONE * f
	return root
