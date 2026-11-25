class_name RailCatalog
extends RefCounted

const SCALES = {"HO": {"ratio": 87.1, "gauge_mm": 16.5}, "N": {"ratio": 160.0, "gauge_mm": 9.0}}
var tracks: Dictionary = {}
var vehicles: Dictionary = {}
var scenery: Dictionary = {}
var packages: Array = []
var errors: Array[String] = []

func _init() -> void:
	for scale in SCALES:
		var n = scale == "N"
		var pieces = [
			{"key":"straight", "name":"标准直轨", "kind":"straight", "length_mm":140.0 if n else 230.0},
			{"key":"short", "name":"半长直轨", "kind":"straight", "length_mm":70.0 if n else 115.0},
			{"key":"curve", "name":"30° 标准弯轨", "kind":"curve", "radius_mm":280.0 if n else 430.0, "angle_deg":30.0},
			{"key":"inner_demo", "name":"30° 内圈弯轨", "kind":"curve", "radius_mm":200.0 if n else 330.0, "angle_deg":30.0},
			{"key":"wide", "name":"15° 大半径弯轨", "kind":"curve", "radius_mm":350.0 if n else 550.0, "angle_deg":15.0},
			{"key":"turnout", "name":"18° 左道岔", "kind":"turnout", "length_mm":180.0 if n else 280.0, "radius_mm":500.0 if n else 800.0, "angle_deg":18.0}
		]
		for p in pieces:
			p.id = "core:" + scale + ":" + p.key
			p.scale = scale
			p.source = "内置"
			tracks[p.id] = p
	vehicles = {
		"core:diesel": {"id":"core:diesel", "name":"DF · 柴油机车", "kind":"locomotive", "length_m":20.0, "width_m":3.1, "height_m":4.3, "mass_kg":120000.0, "power_w":2400000.0, "tractive_n":280000.0, "max_kmh":120.0, "color":"d97d48", "source":"内置"},
		"core:electric": {"id":"core:electric", "name":"EL · 电力机车", "kind":"locomotive", "length_m":19.0, "width_m":3.1, "height_m":4.3, "mass_kg":88000.0, "power_w":4200000.0, "tractive_n":240000.0, "max_kmh":160.0, "color":"3a8f94", "source":"内置"},
		"core:coach": {"id":"core:coach", "name":"客运车厢", "kind":"coach", "length_m":25.0, "width_m":3.1, "height_m":4.1, "mass_kg":46000.0, "max_kmh":160.0, "color":"ddc99f", "source":"内置"},
		"core:freight": {"id":"core:freight", "name":"集装箱平车", "kind":"freight", "length_m":16.0, "width_m":3.0, "height_m":3.8, "mass_kg":62000.0, "max_kmh":100.0, "color":"a45f4c", "source":"内置"},
		"core:tanker": {"id":"core:tanker", "name":"罐式货车", "kind":"tanker", "length_m":14.0, "width_m":3.0, "height_m":3.9, "mass_kg":70000.0, "max_kmh":90.0, "color":"a8b4aa", "source":"内置"}
	}
	for item in [{"id":"core:tree", "name":"针叶树", "kind":"tree", "color":"436b50"}, {"id":"core:station", "name":"乡间车站", "kind":"station", "color":"e6d0a6"}, {"id":"core:house", "name":"红顶小屋", "kind":"house", "color":"e0c393"}, {"id":"core:rock", "name":"山石", "kind":"rock", "color":"8e9690"}, {"id":"core:platform", "name":"站台", "kind":"platform", "color":"9caaac"}]:
		item.source = "内置"
		scenery[item.id] = item

func load_mods(root: String) -> void:
	var dir = DirAccess.open(root)
	if not dir:
		return
	for folder in dir.get_directories():
		var path = root.path_join(folder).path_join("manifest.json")
		if not FileAccess.file_exists(path):
			continue
		var json = JSON.new()
		if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
			errors.append(folder + ": manifest.json 不是有效 JSON 对象")
			continue
		register_package(json.data, root.path_join(folder))

func register_package(data: Dictionary, base: String = "") -> bool:
	var id = str(data.get("id", ""))
	if data.get("api_version", 0) != 1 or id.is_empty() or id == "core" or ":" in id:
		errors.append(id + ": 不支持的 api_version 或非法包 ID")
		return false
	for p in packages:
		if p.id == id:
			errors.append(id + ": 重复包 ID")
			return false
	var staged = {"tracks":{}, "vehicles":{}, "scenery":{}}
	for group in staged:
		if not data.get(group, []) is Array:
			errors.append(id + ": " + group + " 必须是数组")
			return false
		for raw in data.get(group, []):
			if not raw is Dictionary or str(raw.get("id", "")).is_empty():
				errors.append(id + ": 缺少零件 ID")
				return false
			var item = raw.duplicate(true)
			item.id = id + ":" + str(raw.id)
			item.name = str(item.get("name", raw.id))
			item.source = str(data.get("name", id))
			if staged[group].has(item.id) or not _validate(group, item):
				errors.append(item.id + ": 重复 ID 或零件参数不合法")
				return false
			if item.has("model"):
				var model = str(item.model).replace("\\", "/")
				if model.is_absolute_path() or ".." in model or not model.ends_with(".glb") or not FileAccess.file_exists(base.path_join(model)):
					errors.append(item.id + ": GLB 必须位于 Mod 目录内且文件存在")
					return false
				item.model_path = base.path_join(model)
			staged[group][item.id] = item
	tracks.merge(staged.tracks)
	vehicles.merge(staged.vehicles)
	scenery.merge(staged.scenery)
	packages.append({"id":id, "name":str(data.get("name", id)), "version":str(data.get("version", "1.0")), "base":base})
	return true

func _positive(item: Dictionary, key: String, low: float, high: float) -> bool:
	var v = item.get(key, -1)
	return (v is float or v is int) and is_finite(float(v)) and float(v) >= low and float(v) <= high

func _validate(group: String, item: Dictionary) -> bool:
	if item.has("model_scale") and not _positive(item, "model_scale", 0.001, 1000):
		return false
	if item.has("color") and (not item.color is String or not Color.html_is_valid(item.color)):
		return false
	if group == "tracks":
		if not SCALES.has(str(item.get("scale", ""))) or not item.get("kind", "") in ["straight", "curve", "turnout"]:
			return false
		if item.kind in ["straight", "turnout"] and not _positive(item, "length_mm", 10, 2000):
			return false
		if item.kind in ["curve", "turnout"] and (not _positive(item, "radius_mm", 80, 5000) or not _positive(item, "angle_deg", 1, 90)):
			return false
	elif group == "vehicles":
		if not item.get("kind", "") in ["locomotive", "coach", "freight", "tanker"]:
			return false
		for spec in [["length_m", 1, 40], ["width_m", 1, 5], ["height_m", 1, 7], ["mass_kg", 100, 500000], ["max_kmh", 1, 600]]:
			if not _positive(item, spec[0], spec[1], spec[2]):
				return false
		if item.kind == "locomotive" and (not _positive(item, "power_w", 1, 20000000) or not _positive(item, "tractive_n", 1, 1000000)):
			return false
	elif group == "scenery":
		if not item.get("kind", "") in ["tree", "house", "station", "rock", "platform", "custom"]:
			return false
		if item.kind == "custom" and not item.has("model"):
			return false
	return true

func tracks_for_scale(scale: String) -> Array:
	return tracks.values().filter(func(p): return p.scale == scale)
