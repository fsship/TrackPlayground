extends Node3D

signal layout_changed
signal scenery_placed(definition_id: String, position: Vector3)

const Catalog = preload("res://scripts/catalog.gd")
const Graph = preload("res://scripts/rail_graph.gd")
const Simulation = preload("res://scripts/simulation.gd")
const Geometry = preload("res://scripts/geometry.gd")
const Terrain = preload("res://scripts/terrain.gd")
const Derailment = preload("res://scripts/derailment.gd")
const VehicleConnections = preload("res://scripts/vehicle_connections.gd")
const AMBER = Color("e9b56b")
const MINT = Color("78dcc1")
const MUTED = Color("91a5ac")
const TRAIN_PREVIEW_VALID = Color(0.15, 0.55, 1.0, 0.42)
const TRAIN_PREVIEW_INVALID = Color(1.0, 0.18, 0.16, 0.42)
const OPERATE_HINT = "点击列车选中 · 点击道岔切换 · 空格暂停 · 右键旋转 / 中键平移 / 滚轮缩放"
const TRACK_HINT = "Tab 切换端点 · 左键铺轨 · R 旋转 15° · F 镜像 · Esc 取消 · Ctrl+Z 撤销"
var catalog: RailCatalog
var graph: RailGraph
var simulation: RailSimulation
var terrain: RailTerrain
var table_base: MeshInstance3D
var table_trim: MeshInstance3D
var water: MeshInstance3D
var camera: Camera3D
var rail_root: Node3D
var scenery_root: Node3D
var train_root: Node3D
var train_nodes: Dictionary = {}
var train_connections: Dictionary = {}
var derailment: Node3D
var scenery_items: Array = []
var preview: Node3D
var marker: MeshInstance3D
var brush_ring: MeshInstance3D
var camera_target = Vector3(0, 0, 0)
var camera_yaw = -0.63
var camera_pitch = 0.82
var camera_distance = 33.0
var follow_train = false
var mode = "operate"
var selected_track = "core:HO:straight"
var track_placement_endpoint = 0
var flex_options: Dictionary = {}
var auto_connect = false
var connection_start: Dictionary = {}
var connection_plan: Dictionary = {}
var connection_key = ""
var connection_min_radius = 180.0
var connection_marker: MeshInstance3D
var selected_scenery = "core:tree"
var selected_train = 1
var yaw = 0.0
var mirror = false
var placement_height = 0.0
var grade = 0.0
var placement = Vector3.ZERO
var placement_yaw = 0.0
var valid_placement = false
var snapped = false
var erase = false
var terrain_mode = "raise"
var brush_radius = 1.4
var brush_strength = 0.7
var flatten_height = 0.0
var brush_active = false
var preview_key = ""
var draft_cars: Array = ["core:diesel", "core:coach", "core:coach"]
var placing_train = false
var train_placement_reversed = false
var train_preview_material: StandardMaterial3D
var undo_stack: Array = []
var redo_stack: Array = []
var ui: Control
var top_panel: PanelContainer
var bottom_panel: PanelContainer
var left_panel: PanelContainer
var right_panel: PanelContainer
var layout_pending = false
var left_body: VBoxContainer
var right_body: VBoxContainer
var mode_buttons: Dictionary = {}
var train_buttons: VBoxContainer
var speed_slider: HSlider
var speed_label: Label
var telemetry: Label
var selected_label: Label
var status_label: Label
var toast_label: Label
var scale_label: Label
var pause_button: Button
var mode_label: Label
var draft_label: Label
var rail_count: Label
var performance_label: Label
var mod_dialog: AcceptDialog
var file_dialog: FileDialog
var confirm_dialog: ConfirmationDialog
var new_scene_dialog: ConfirmationDialog
var new_scene_width: SpinBox
var new_scene_depth: SpinBox
var toast_time = 0.0
var ui_time = 0.0
var preview_time = 0.0
var pending_confirm: Callable
var user_dir = "user://layouts"

func _ready() -> void:
	update_window_scale()
	get_window().size_changed.connect(update_window_scale)
	catalog = Catalog.new()
	catalog.load_mods("res://mods")
	if OS.has_feature("standalone"):
		catalog.load_mods(OS.get_executable_path().get_base_dir().path_join("mods"))
	catalog.load_mods("user://mods")
	graph = Graph.new(catalog)
	simulation = Simulation.new(graph, catalog)
	simulation.train_event.connect(func(_id, message): toast(message))
	simulation.train_added.connect(func(_train): rebuild_trains())
	simulation.train_removed.connect(func(_id): rebuild_trains())
	create_world()
	create_ui()
	if "--scale=N" in OS.get_cmdline_user_args():
		graph.scale_name = "N"
		selected_track = "core:N:straight"
	empty_scene()
	set_mode(mode)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(user_dir))
	toast("欢迎来到轨道工坊。右键旋转视角，滚轮缩放；选择顶部工具开始搭建。", 8.0)
	if "--self-test" in OS.get_cmdline_user_args():
		call_deferred("integration_test")
	if "--flex-test" in OS.get_cmdline_user_args():
		call_deferred("flex_test")
	if "--steam-test" in OS.get_cmdline_user_args():
		call_deferred("steam_test")
	if "--connections-test" in OS.get_cmdline_user_args():
		call_deferred("connections_test")
	if "--capture" in OS.get_cmdline_user_args():
		call_deferred("capture_preview")

func create_world() -> void:
	var env = WorldEnvironment.new()
	var environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("18292f")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("d7e4e2")
	environment.ambient_light_energy = 0.28
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.environment = environment
	add_child(env)
	var light = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -30, 0)
	light.light_color = Color("ffe4bd")
	light.light_energy = 0.72
	light.shadow_enabled = true
	light.directional_shadow_max_distance = 70
	add_child(light)
	var fill = DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-35, 140, 0)
	fill.light_color = Color("b4dce1")
	fill.light_energy = 0.16
	add_child(fill)
	table_base = Geometry.box(self, Vector3(Terrain.WIDTH + 0.3, 0.6, Terrain.DEPTH + 0.3), Vector3(0, -0.72, 0), Color("4a3c30"))
	table_trim = Geometry.box(self, Vector3(Terrain.WIDTH + 0.5, 0.10, Terrain.DEPTH + 0.5), Vector3(0, -1.06, 0), Color("9b7950"))
	Geometry.box(self, Vector3(200, 0.15, 200), Vector3(0, -2.0, 0), Color("23383b"))
	var floor_body = StaticBody3D.new()
	var floor_shape = CollisionShape3D.new()
	var floor_box = BoxShape3D.new()
	floor_box.size = Vector3(200, 0.15, 200)
	floor_shape.shape = floor_box
	floor_body.position.y = -2.0
	floor_body.add_child(floor_shape)
	add_child(floor_body)
	derailment = Derailment.new()
	add_child(derailment)
	terrain = Terrain.new()
	add_child(terrain)
	water = Geometry.box(self, Vector3(Terrain.WIDTH - 0.1, 0.025, Terrain.DEPTH - 0.1), Vector3(0, -0.24, 0), Color("588d92"))
	water.material_override = Geometry.material(Color("365d66"), 0.85, 0.0)
	rail_root = Node3D.new()
	add_child(rail_root)
	scenery_root = Node3D.new()
	add_child(scenery_root)
	train_root = Node3D.new()
	add_child(train_root)
	marker = Geometry.cylinder(self, 0.18, 0.035, Vector3.ZERO, MINT)
	marker.visible = false
	connection_marker = Geometry.cylinder(self, 0.23, 0.05, Vector3.ZERO, AMBER)
	connection_marker.visible = false
	brush_ring = MeshInstance3D.new()
	var ring = TorusMesh.new()
	ring.inner_radius = 0.97
	ring.outer_radius = 1.0
	ring.rings = 48
	ring.ring_segments = 8
	brush_ring.mesh = ring
	brush_ring.material_override = Geometry.material(MINT)
	brush_ring.visible = false
	add_child(brush_ring)
	camera = Camera3D.new()
	camera.fov = 42
	camera.near = 0.04
	camera.far = 500
	add_child(camera)
	update_camera()

func create_ui() -> void:
	var layer = CanvasLayer.new()
	add_child(layer)
	ui = Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui)
	var theme = Theme.new()
	var font = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC"])
	theme.default_font = font
	theme.default_font_size = 15
	theme.set_color("font_color", "Label", Color("e0e9e9"))
	theme.set_color("font_color", "Button", Color("c8d5d8"))
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_pressed_color", "Button", Color("102d2c"))
	theme.set_stylebox("normal", "Button", style(Color("263b43"), 7, Color("344950")))
	theme.set_stylebox("hover", "Button", style(Color("36515a"), 7, Color("64817e")))
	theme.set_stylebox("pressed", "Button", style(MINT, 7, MINT))
	theme.set_stylebox("focus", "Button", style(Color(0,0,0,0), 7, AMBER))
	theme.set_stylebox("normal", "OptionButton", style(Color("263b43"), 7, Color("3c5158")))
	theme.set_stylebox("panel", "PopupMenu", style(Color("1c3039"), 8, Color("50666a")))
	theme.set_stylebox("panel", "AcceptDialog", style(Color("1c3039"), 8, Color("50666a")))
	theme.set_stylebox("panel", "PanelContainer", style(Color("182b33"), 12, Color("344950")))
	theme.set_stylebox("slider", "HSlider", style(Color("3d535c"), 3))
	theme.set_stylebox("grabber_area", "HSlider", style(MINT, 3))
	theme.set_stylebox("grabber_area_highlight", "HSlider", style(AMBER, 3))
	ui.theme = theme

	var top = panel(Vector2(16, 16), Vector2(-16, 86), Vector2(0, 0), Vector2(1, 0))
	top_panel = top
	var top_row = HFlowContainer.new()
	top_row.add_theme_constant_override("h_separation", 10)
	top_row.add_theme_constant_override("v_separation", 6)
	top.add_child(top_row)
	var brand = VBoxContainer.new()
	brand.custom_minimum_size.x = 180
	top_row.add_child(brand)
	label(brand, "轨道工坊", 24, Color("f2dfbb"))
	label(brand, "T R A C K   P L A Y G R O U N D", 10, MUTED)
	for item in [["operate", "01  行车"], ["track", "02  轨道"], ["terrain", "03  地形"], ["scenery", "04  布景"]]:
		var b = button(top_row, item[1], func(): set_mode(item[0]))
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(90, 40)
		mode_buttons[item[0]] = b
	button(top_row, "Mod", show_mods)
	button(top_row, "保存", func(): show_file(true))
	button(top_row, "打开", func(): show_file(false))
	pause_button = button(top_row, "Ⅱ 暂停", toggle_pause)
	pause_button.custom_minimum_size.x = 100

	var left = panel(Vector2(16, 100), Vector2(288, -110), Vector2(0, 0), Vector2(0, 1))
	left_panel = left
	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	left_body = VBoxContainer.new()
	left_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_body.add_theme_constant_override("separation", 12)
	scroll.add_child(left_body)
	var right = panel(Vector2(-304, 100), Vector2(-16, -110), Vector2(1, 0), Vector2(1, 1))
	right_panel = right
	var right_scroll = ScrollContainer.new()
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(right_scroll)
	right_body = VBoxContainer.new()
	right_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_body.add_theme_constant_override("separation", 12)
	right_scroll.add_child(right_body)
	label(right_body, "运行调度", 20)
	label(right_body, "每个编组拥有独立的速度与方向", 12, MUTED)
	train_buttons = VBoxContainer.new()
	train_buttons.add_theme_constant_override("separation", 7)
	right_body.add_child(train_buttons)
	separator(right_body)
	selected_label = label(right_body, "选中列车", 17, AMBER)
	speed_label = label(right_body, "0.0", 38, Color("edf3e5"))
	label(right_body, "km/h  原型等效速度", 12, MUTED)
	speed_slider = HSlider.new()
	speed_slider.min_value = 0
	speed_slider.max_value = 120
	speed_slider.step = 1
	speed_slider.custom_minimum_size.y = 26
	speed_slider.value_changed.connect(func(v):
		var t = current_train()
		if not t.is_empty():
			t.target = v
	)
	right_body.add_child(speed_slider)
	var row = HBoxContainer.new()
	right_body.add_child(row)
	button(row, "停车", func(): command_stop())
	button(row, "换向", func():
		var t = current_train()
		if not t.is_empty() and simulation.reverse(t):
			toast("已切换为" + ("正向" if t.direction == 1 else "反向") + "；调高目标速度即可运行")
	)
	button(row, "急停", func():
		var t = current_train()
		if not t.is_empty():
			simulation.emergency(t)
	)
	telemetry = label(right_body, "", 13, MUTED)
	telemetry.custom_minimum_size.y = 170
	telemetry.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var follow = CheckButton.new()
	follow.text = "跟随选中列车"
	follow.toggled.connect(func(value): follow_train = value)
	right_body.add_child(follow)
	button(right_body, "复位 / 脱轨列车重新上轨", func():
		var t = current_train()
		if not t.is_empty():
			simulation.reset_train(t)
	)
	button(right_body, "移除选中编组", func():
		var t = current_train()
		if not t.is_empty():
			push_undo()
			simulation.remove_train(t.id)
			selected_train = simulation.trains[0].id if not simulation.trains.is_empty() else -1
			refresh_train_list()
	)
	separator(right_body)
	label(right_body, "线路概况", 15)
	rail_count = label(right_body, "", 13, MUTED)
	rail_count.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var bottom = panel(Vector2(16, -96), Vector2(-16, -16), Vector2(0, 1), Vector2(1, 1))
	bottom_panel = bottom
	var br = HBoxContainer.new()
	br.add_theme_constant_override("separation", 18)
	bottom.add_child(br)
	var state_col = VBoxContainer.new()
	state_col.custom_minimum_size.x = 245
	br.add_child(state_col)
	scale_label = label(state_col, "HO  /  1:87.1  /  16.5 mm", 17, AMBER)
	mode_label = label(state_col, "行车模式", 12, MUTED)
	var instructions = VBoxContainer.new()
	instructions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	br.add_child(instructions)
	status_label = label(instructions, "", 14)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast_label = label(instructions, "", 12, MINT)
	toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var actions = VBoxContainer.new()
	br.add_child(actions)
	var ar = HBoxContainer.new()
	actions.add_child(ar)
	button(ar, "↶ 撤销", undo)
	button(ar, "俯视", func(): camera_pitch = 1.49; follow_train = false)
	button(ar, "全景", reset_camera)
	performance_label = label(actions, "", 11, MUTED)
	performance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	file_dialog = FileDialog.new()
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.filters = PackedStringArray(["*.railway ; 轨道工坊场景"])
	file_dialog.size = Vector2i(1000, 650)
	file_dialog.file_selected.connect(file_chosen)
	ui.add_child(file_dialog)
	confirm_dialog = ConfirmationDialog.new()
	confirm_dialog.title = "确认更改"
	confirm_dialog.ok_button_text = "继续"
	confirm_dialog.cancel_button_text = "取消"
	confirm_dialog.confirmed.connect(func():
		if pending_confirm.is_valid():
			pending_confirm.call()
	)
	ui.add_child(confirm_dialog)
	new_scene_dialog = ConfirmationDialog.new()
	new_scene_dialog.title = "新建空白沙盘"
	new_scene_dialog.ok_button_text = "创建"
	new_scene_dialog.cancel_button_text = "取消"
	new_scene_dialog.min_size = Vector2i(420, 280)
	var new_scene_body = VBoxContainer.new()
	new_scene_body.add_theme_constant_override("separation", 12)
	new_scene_dialog.add_child(new_scene_body)
	label(new_scene_body, "沙盘实际尺寸 / 米（每边 0.5–10.0 m）", 15, AMBER)
	label(new_scene_body, "宽度", 14)
	new_scene_width = spin(new_scene_body, Terrain.MIN_SIZE / 10.0, Terrain.MAX_SIZE / 10.0, 0.1, Terrain.WIDTH / 10.0, func(_v): pass)
	label(new_scene_body, "深度", 14)
	new_scene_depth = spin(new_scene_body, Terrain.MIN_SIZE / 10.0, Terrain.MAX_SIZE / 10.0, 0.1, Terrain.DEPTH / 10.0, func(_v): pass)
	label(new_scene_body, "创建后清空当前场景；可通过撤销恢复。", 13, MUTED)
	new_scene_dialog.confirmed.connect(create_new_scene)
	ui.add_child(new_scene_dialog)
	mod_dialog = AcceptDialog.new()
	mod_dialog.title = "Mod 管理 · API v1"
	mod_dialog.min_size = Vector2i(720, 430)
	ui.add_child(mod_dialog)
	set_mode("operate")
	get_viewport().size_changed.connect(responsive_layout)
	top.resized.connect(responsive_layout)
	bottom.resized.connect(responsive_layout)
	for hud in [top_panel, bottom_panel, left_panel, right_panel]:
		hud.minimum_size_changed.connect(responsive_layout)
		hud.clip_contents = true
	left_panel.resized.connect(responsive_layout)
	right_panel.resized.connect(responsive_layout)
	left_body.minimum_size_changed.connect(responsive_layout)
	right_body.minimum_size_changed.connect(responsive_layout)
	responsive_layout()

func responsive_layout() -> void:
	if not layout_pending:
		layout_pending = true
		apply_responsive_layout.call_deferred()

func update_window_scale() -> void:
	var window = get_window()
	# Keep native-size text on normal windows; scale down only when the HUD
	# would otherwise run out of room. EXPAND always fills either aspect ratio.
	var base = Vector2i(maxi(1100, window.size.x), maxi(700, window.size.y))
	if window.content_scale_size != base:
		window.content_scale_size = base

func apply_responsive_layout() -> void:
	layout_pending = false
	if not is_instance_valid(top_panel) or not is_instance_valid(bottom_panel):
		return
	top_panel.offset_bottom = top_panel.offset_top + maxf(70, top_panel.get_combined_minimum_size().y)
	var bottom_height = maxf(80, bottom_panel.get_combined_minimum_size().y)
	bottom_panel.offset_top = -16 - bottom_height
	# Rebuilding wrapped text can temporarily grow a panel; restore its width.
	left_panel.size.x = 272
	right_panel.size.x = 288
	for side in [left_panel, right_panel]:
		side.offset_top = top_panel.offset_top + top_panel.size.y + 14
		side.offset_bottom = bottom_panel.offset_top - 14
		side.queue_sort()
		var scroll: ScrollContainer = side.get_child(0)
		# Constrain the scroll viewport as content is rebuilt. Wrapped labels
		# can briefly report their unwrapped width before their first layout.
		scroll.position = Vector2(12, 10)
		scroll.size = Vector2(side.size.x - 24, maxf(0, side.size.y - 20))
		scroll.queue_sort()
	if is_instance_valid(new_scene_dialog) and new_scene_dialog.visible:
		new_scene_dialog.move_to_center()

func style(color: Color, radius: int = 8, border: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.set_border_width_all(1)
	s.border_color = border
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s

func panel(start: Vector2, end: Vector2, a: Vector2, b: Vector2) -> PanelContainer:
	var p = PanelContainer.new()
	p.anchor_left = a.x
	p.anchor_top = a.y
	p.anchor_right = b.x
	p.anchor_bottom = b.y
	p.offset_left = start.x
	p.offset_top = start.y
	p.offset_right = end.x
	p.offset_bottom = end.y
	ui.add_child(p)
	return p

func label(parent: Node, text: String, size: int = 15, color: Color = Color("dde6e6")) -> Label:
	var l = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l

func button(parent: Node, text: String, callback: Callable) -> Button:
	var b = Button.new()
	b.text = text
	b.custom_minimum_size.y = 36
	b.pressed.connect(callback)
	parent.add_child(b)
	return b

func separator(parent: Node) -> void:
	parent.add_child(HSeparator.new())

func spacer(parent: Node) -> void:
	var s = Control.new()
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(s)

func clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()

func set_mode(value: String) -> void:
	mode = value
	reset_connection()
	auto_connect = false
	placing_train = false
	track_placement_endpoint = 0
	erase = false
	preview_key = ""
	if preview:
		preview.queue_free()
		preview = null
	for key in mode_buttons:
		mode_buttons[key].button_pressed = key == mode
	clear_children(left_body)
	var titles = {"operate":"列车编组", "track":"轨道零件", "terrain":"地形工作台", "scenery":"场景布置"}
	mode_label.text = titles[mode] + "  ·  %.1f × %.1f m 沙盘" % [terrain.width / 10.0, terrain.depth / 10.0]
	label(left_body, titles[mode], 21)
	if mode == "track":
		build_track_ui()
	elif mode == "terrain":
		build_terrain_ui()
	elif mode == "scenery":
		build_scenery_ui()
	else:
		build_train_ui()
	separator(left_body)
	label(left_body, "场景", 14, AMBER)
	var scale_picker = OptionButton.new()
	scale_picker.add_item("HO · 1:87.1 · 16.5 mm")
	scale_picker.add_item("N · 1:160 · 9 mm")
	scale_picker.selected = 0 if graph.scale_name == "HO" else 1
	scale_picker.item_selected.connect(func(index):
		var chosen = "HO" if index == 0 else "N"
		if chosen != graph.scale_name:
			confirm("切换比例会新建相同尺寸的空白沙盘。当前场景可通过撤销恢复；建议先保存。", func():
				push_undo()
				graph.scale_name = chosen
				selected_track = "core:" + chosen + ":straight"
				empty_scene(true, terrain.width, terrain.depth)
				set_mode(mode)
			)
			scale_picker.select(0 if graph.scale_name == "HO" else 1)
	)
	left_body.add_child(scale_picker)
	button(left_body, "载入示例布局", func(): confirm("载入 3.4 × 2.6 m 示例布局？当前编辑可以撤销。", func(): push_undo(); make_demo()))
	button(left_body, "新建空白沙盘", show_new_scene)
	var hints = {"operate":OPERATE_HINT, "track":track_placement_hint(), "terrain":"按住左键刷地形 · Ctrl+Z 撤销整次笔刷 · 轨道高程独立，填挖地形后可手动整平路基", "scenery":"左键放置布景 · R 旋转 · 橡皮擦删除 · 右键旋转视角 / 中键平移"}
	status_label.text = hints[mode]
	responsive_layout()

func build_track_ui() -> void:
	button(left_body, "自动连接 · 选择两个端点", begin_auto_connect)
	label(left_body, "自动连接最小半径 / mm", 12, MUTED)
	spin(left_body, 80, 2000, 10, connection_min_radius, func(v): connection_min_radius = v; connection_key = "")
	separator(left_body)
	build_flex_options()
	label(left_body, "选择零件，再点击沙盘放置", 12, MUTED)
	for def in catalog.tracks_for_scale(graph.scale_name):
		if def.kind == "flex" and def.shape == "bezier":
			continue
		var caption = def.name
		if def.kind == "straight":
			caption += "  ·  %d mm" % def.length_mm
		elif def.kind != "flex":
			caption += "  ·  R%d" % def.radius_mm
		var b = button(left_body, caption, func(): select_track(def.id))
		b.modulate = MINT if def.id == selected_track else Color.WHITE
		b.tooltip_text = def.source + " / " + def.id
	separator(left_body)
	var r = HBoxContainer.new()
	left_body.add_child(r)
	button(r, "旋转 15°", func(): yaw += PI / 12; preview_key = "")
	button(r, "镜像 F", func(): mirror = not mirror; preview_key = "")
	button(left_body, "切换端点 Tab", cycle_track_endpoint)
	label(left_body, "放置端点高程 / 模型毫米", 12, MUTED)
	spin(left_body, -60, 400, 1, placement_height * 100, func(v): placement_height = v / 100; preview_key = "")
	label(left_body, "线路坡度 / %", 12, MUTED)
	spin(left_body, -8, 8, 0.1, grade * 100, func(v): grade = v / 100; preview_key = "")
	button(left_body, "橡皮擦 · 点击删除轨道", func(): reset_connection(); auto_connect = false; erase = not erase; preview_key = ""; toast("轨道橡皮擦" if erase else "恢复铺轨"))
	button(left_body, "整平全部轨道路基", conform_terrain)
	var tip = label(left_body, "道岔在行车模式中点击切换。占用中的轨道和道岔会锁定。", 12, MUTED)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func build_flex_options() -> void:
	var definition: Dictionary = catalog.tracks[selected_track]
	if definition.kind == "flex" and definition.shape != "bezier":
		label(left_body, definition.name + "参数", 14, AMBER)
		var options = RailFlexTrack.settings(definition, flex_options)
		if definition.shape != "arc":
			label(left_body, "长度 / mm" if definition.shape != "s" else "纵向跨度 / mm", 12, MUTED)
			spin(left_body, 10, 2000, 5, options.length_mm, func(v): flex_options.length_mm = v; preview_key = "")
		if definition.shape in ["arc", "transition"]:
			label(left_body, "半径 / mm" if definition.shape == "arc" else "末端半径 / mm", 12, MUTED)
			spin(left_body, 80, 5000, 10, options.radius_mm, func(v): flex_options.radius_mm = v; preview_key = "")
		if definition.shape == "arc":
			label(left_body, "转角 / °", 12, MUTED)
			spin(left_body, 1, 180, 1, options.angle_deg, func(v): flex_options.angle_deg = v; preview_key = "")
		if definition.shape == "s":
			label(left_body, "横向偏移 / mm", 12, MUTED)
			spin(left_body, -1000, 1000, 5, options.offset_mm, func(v): flex_options.offset_mm = v; preview_key = "")
		separator(left_body)

func select_track(id: String) -> void:
	selected_track = id
	flex_options = {}
	set_mode("track")
	update_preview()
	toast("已选中 " + catalog.tracks[id].name)

func reset_connection() -> void:
	connection_start = {}
	connection_plan = {}
	connection_key = ""
	if connection_marker:
		connection_marker.visible = false

func begin_auto_connect() -> void:
	reset_connection()
	auto_connect = true
	erase = false
	preview_key = ""
	update_preview()
	toast("依次点击两个开放端点；悬浮第二个端点预览连接，Esc 取消。", 7)

func connection_hint() -> String:
	return ("自动连接：请选择第一个开放端点" if connection_start.is_empty() else "自动连接：请选择第二个开放端点 · 点击已选端点可重选") + " · Esc 取消"

func track_placement_hint() -> String:
	var names = ["入口", "直股端", "侧股端"] if catalog.tracks[selected_track].kind == "turnout" else ["起点", "终点"]
	return "当前端点：" + names[track_placement_endpoint % names.size()] + " · " + TRACK_HINT

func cycle_track_endpoint() -> void:
	if auto_connect:
		return
	var count = 3 if catalog.tracks[selected_track].kind == "turnout" else 2
	track_placement_endpoint = (track_placement_endpoint + 1) % count
	update_preview()

func spin(parent: Node, low: float, high: float, step_value: float, value: float, callback: Callable) -> SpinBox:
	var control = SpinBox.new()
	control.min_value = low
	control.max_value = high
	control.step = step_value
	control.value = value
	control.value_changed.connect(callback)
	parent.add_child(control)
	return control

func build_terrain_ui() -> void:
	label(left_body, "雕刻地貌，铺设你的铁路世界", 12, MUTED)
	for item in [["raise","抬高 · 山丘"], ["lower","降低 · 河谷 / 湖泊"], ["flatten","整平 · 目标高度"], ["smooth","平滑 · 柔化坡面"], ["paint","涂抹 · 砂土"], ["grass","涂抹 · 草地"]]:
		button(left_body, item[1], func(): terrain_mode = item[0]; toast("笔刷：" + item[1]))
	label(left_body, "笔刷半径 / 模型毫米", 12, MUTED)
	spin(left_body, 30, 500, 10, brush_radius * 100, func(v): brush_radius = v / 100)
	label(left_body, "笔刷强度", 12, MUTED)
	spin(left_body, 0.1, 3.0, 0.1, brush_strength, func(v): brush_strength = v)
	label(left_body, "整平高度 / 模型毫米", 12, MUTED)
	spin(left_body, -70, 400, 5, flatten_height * 100, func(v): flatten_height = v / 100)
	label(left_body, "水面固定在 −24 mm。", 12, MUTED)
	button(left_body, "整平全部轨道路基", conform_terrain)

func build_scenery_ui() -> void:
	label(left_body, "布景随地表高度自动落位", 12, MUTED)
	for def in catalog.scenery.values():
		button(left_body, def.name + ("  · Mod" if def.source != "内置" else ""), func(): selected_scenery = def.id; erase = false; preview_key = "")
	button(left_body, "旋转 15°", func(): yaw += PI / 12; preview_key = "")
	button(left_body, "橡皮擦 · 点击删除布景", func(): erase = not erase; preview_key = "")

func build_train_ui() -> void:
	label(left_body, "从前到后添加车辆，自由组合", 12, MUTED)
	var picker = OptionButton.new()
	var ids = catalog.vehicles.keys()
	for id in ids:
		picker.add_item(catalog.vehicles[id].name)
	left_body.add_child(picker)
	button(left_body, "＋ 添加到编组", func():
		append_draft_vehicle(ids[picker.selected])
	)
	label(left_body, "蒸汽机车自动附带一辆煤水车。", 12, MUTED)
	draft_label = label(left_body, "", 13, MUTED)
	draft_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	update_draft()
	var row = HBoxContainer.new()
	left_body.add_child(row)
	button(row, "移除末辆", func(): if not draft_cars.is_empty(): draft_cars.pop_back(); update_draft())
	button(row, "清空", func(): draft_cars.clear(); update_draft())
	button(left_body, "将编组放上轨道 →", begin_train_placement)
	button(left_body, "用草稿替换选中编组", replace_consist)
	separator(left_body)
	label(left_body, "物理环境", 14, AMBER)
	var wet = CheckButton.new()
	wet.text = "湿轨 · 降低轮轨黏着"
	wet.button_pressed = simulation.wet_rails
	wet.toggled.connect(func(v): simulation.wet_rails = v)
	left_body.add_child(wet)
	var derails = CheckButton.new()
	derails.text = "启用脱轨保护"
	derails.button_pressed = simulation.derailments
	derails.toggled.connect(func(v): simulation.derailments = v)
	left_body.add_child(derails)
	var note = label(left_body, "保护开启：弯道超速、轨道尽头停车。关闭后，列车会冲出轨道尽头并坠落；可在右侧复位上轨。换向前请停车。", 12, MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func append_draft_vehicle(id: String) -> void:
	var addition = [id]
	if catalog.vehicles.has(catalog.vehicles[id].get("companion", "")):
		addition.append(catalog.vehicles[id].companion)
	if draft_cars.size() + addition.size() > 24:
		toast("每个编组最多 24 辆；蒸汽机车与煤水车需要 2 个空位" if addition.size() == 2 else "每个编组最多 24 辆车辆")
		return
	draft_cars.append_array(addition)
	update_draft()

func update_draft() -> void:
	if not is_instance_valid(draft_label):
		return
	var names: Array[String] = []
	for i in draft_cars.size():
		names.append("%02d  %s" % [i + 1, catalog.vehicles[draft_cars[i]].name])
	draft_label.text = "\n".join(names) + "\n\n%d 辆 · 模型长度 %.0f mm" % [draft_cars.size(), simulation.consist_length(draft_cars) * 100]

func begin_train_placement() -> void:
	placing_train = true
	train_placement_reversed = false
	update_preview()
	toast("蓝色虚影可放置，红色表示不可放置；Tab 切换方向，Esc 取消。", 7)

func make_demo() -> void:
	empty_scene(false)
	terrain.seed_landscape()
	var is_n = graph.scale_name == "N"
	var base = "core:" + graph.scale_name + ":"
	var r = 2.8 if is_n else 4.3
	var step = 1.4 if is_n else 2.3
	# Two concentric, electrically independent demonstration circuits.
	for loop in range(2):
		var radius = r if loop == 0 else (2.0 if is_n else 3.3)
		var curve_id = base + ("curve" if loop == 0 else "inner_demo")
		var pos = Vector3(-step * 2.0, 0.015, -radius)
		var angle = 0.0
		for side in range(2):
			for j in range(4):
				var p = graph.add_part(base + "straight", pos, angle)
				pos = graph.edges[str(int(p.uid)) + ":0"].points[-1]
			for j in range(6):
				var p = graph.add_part(curve_id, pos, angle)
				pos = graph.edges[str(int(p.uid)) + ":0"].points[-1]
				angle -= PI / 6
	# A short, usable demonstration turnout and siding outside the loops.
	var yard_z = r + 1.8
	var yard = graph.add_part(base + "straight", Vector3(-step * 2, 0.015, yard_z), 0)
	var yp: Vector3 = graph.edges[str(int(yard.uid)) + ":0"].points[-1]
	var turnout = graph.add_part(base + "turnout", yp, 0)
	for branch in [0, 1]:
		var edge = graph.edges[str(int(turnout.uid)) + ":" + str(branch)]
		var tail: Vector3 = edge.points[-1]
		var direction: Vector3 = (edge.points[-1] - edge.points[-2]).normalized()
		var y = atan2(-direction.z, direction.x)
		for j in range(3):
			var p = graph.add_part(base + "straight", tail, y)
			tail = graph.edges[str(int(p.uid)) + ":0"].points[-1]
	flatten_rail_bed()
	add_scenery("core:station", Vector3(-1.8, 0, -r - 1.2), PI)
	add_scenery("core:platform", Vector3(-1.8, 0, -r - 0.55), 0)
	add_scenery("core:house", Vector3(3.0, 0, -1.0), -0.3)
	add_scenery("core:house", Vector3(5.0, 0, -0.7), 0.2)
	if catalog.scenery.has("alpine:water_tower"):
		add_scenery("alpine:water_tower", Vector3(6.5, 0, 1.0), 0)
	var rng = RandomNumberGenerator.new()
	rng.seed = 8017
	for i in range(38):
		var x = rng.randf_range(-4.0, 1.2)
		var z = rng.randf_range(-1.6, 1.4)
		if graph.nearest(Vector3(x, 0.015, z), 0.8).is_empty():
			add_scenery("core:tree", Vector3(x, 0, z), rng.randf_range(0, TAU))
	for i in range(9):
		add_scenery("core:tree", Vector3(-11.0 + i * 0.45, 0, 4.5 + sin(i * 2.0)), i)
	for i in range(6):
		add_scenery("core:rock", Vector3(-2.5 + i * 0.7, 0, 0.8), i)
	# A shallow pond beside the yard, safely away from the rail formation.
	terrain.brush(Vector3(9, 0, -8), 2.0, 1.0, "lower", 0.6)
	terrain.rebuild()
	rebuild_rails()
	var passenger = simulation.add_train(["core:diesel", "core:coach", "core:coach"], "4:0", step * 0.8, "01 · 山谷旅客")
	var freight = simulation.add_train(["core:electric", "core:freight", "core:tanker"], str(int(graph.parts[30].uid)) + ":0", step * 0.8, "02 · 环线货运")
	if not passenger.is_empty():
		passenger.target = 23.0
	if not freight.is_empty():
		freight.target = 18.0
	selected_train = passenger.get("id", -1)
	simulation.paused = false
	rebuild_trains()
	refresh_train_list()
	refresh_stats()
	reset_camera()
	set_mode(mode)
	layout_changed.emit()

func show_new_scene() -> void:
	brush_active = false
	new_scene_width.value = terrain.width / 10.0
	new_scene_depth.value = terrain.depth / 10.0
	new_scene_dialog.popup_centered()
	new_scene_width.get_line_edit().grab_focus()
	new_scene_width.get_line_edit().select_all()

func create_new_scene() -> void:
	# Commit typed text too, even if the user clicks Create without leaving a field.
	new_scene_width.apply()
	new_scene_depth.apply()
	push_undo()
	empty_scene(true, new_scene_width.value * 10.0, new_scene_depth.value * 10.0)

func resize_sandbox(width: float, depth: float) -> void:
	terrain.configure_size(width, depth)
	table_base.mesh.size = Vector3(terrain.width + 0.3, 0.6, terrain.depth + 0.3)
	table_trim.mesh.size = Vector3(terrain.width + 0.5, 0.10, terrain.depth + 0.5)
	water.mesh.size = Vector3(terrain.width - 0.1, 0.025, terrain.depth - 0.1)

func empty_scene(refresh: bool = true, width: float = Terrain.WIDTH, depth: float = Terrain.DEPTH) -> void:
	brush_active = false
	placing_train = false
	follow_train = false
	selected_train = -1
	simulation.paused = true
	derailment.clear()
	graph.parts.clear()
	graph.next_uid = 1
	graph.rebuild()
	simulation.trains.clear()
	simulation.next_uid = 1
	scenery_items.clear()
	clear_children(scenery_root)
	clear_children(train_root)
	train_nodes.clear()
	train_connections.clear()
	clear_children(rail_root)
	resize_sandbox(width, depth)
	if refresh:
		terrain.rebuild()
		refresh_train_list()
		refresh_stats()
		reset_camera()
		update_camera()
		set_mode(mode)
		update_ui()
		layout_changed.emit()
		toast("空白沙盘已就绪。先铺设轨道，再添加列车。")

func rebuild_rails() -> void:
	connection_key = ""
	clear_children(rail_root)
	var gauge: float = RailCatalog.SCALES[graph.scale_name].gauge_mm / 100.0
	for p in graph.parts:
		var paths = graph.part_paths(p)
		var node = Geometry.track(paths, gauge)
		Derailment.track_collision(node, paths, gauge)
		rail_root.add_child(node)
		if paths.size() > 1:
			var point: Vector3 = paths[int(p.get("branch", 0))][mini(6, paths[0].size() - 1)]
			Geometry.cylinder(node, gauge * 0.4, 0.05, point + Vector3(0, 0.14, gauge), AMBER if p.get("branch", 0) == 0 else MINT)
		for branch in paths.size():
			for end in [0, 1]:
				if branch > 0 and end == 0:
					continue
				var id = str(int(p.uid)) + ":" + str(branch)
				if graph.connections[graph.endpoint_key(id, end)].is_empty():
					var ep = graph.endpoint(id, end)
					Geometry.cylinder(node, gauge * 0.32, 0.025, ep.position + Vector3.UP * 0.09, AMBER)
	refresh_stats()

func rebuild_trains() -> void:
	clear_children(train_root)
	train_nodes.clear()
	train_connections.clear()
	for train in simulation.trains:
		var nodes = []
		for id in train.cars:
			var node = Geometry.vehicle(catalog.vehicles[id], simulation.ratio())
			train_root.add_child(node)
			nodes.append(node)
		train_nodes[train.id] = nodes
		var connections = VehicleConnections.new()
		connections.setup(train.cars, catalog, simulation.ratio())
		train_root.add_child(connections)
		train_connections[train.id] = connections
	update_train_visuals()

func update_train_visuals() -> void:
	for train in simulation.trains:
		if not train_nodes.has(train.id):
			continue
		var samples = simulation.car_samples(train)
		for i in samples.size():
			var sample = samples[i]
			var node: Node3D = train_nodes[train.id][i]
			if train.has("derailed_cars"):
				node.basis = sample.basis
				node.position = sample.position
				if node.has_method("sync_motion"):
					node.sync_motion(train.distance_m, train.velocity, simulation.paused, true)
				continue
			var tangent: Vector3 = sample.tangent
			var side = tangent.cross(Vector3.UP).normalized()
			if side.length_squared() < 0.1:
				continue
			node.basis = Basis(tangent, side.cross(tangent).normalized(), side)
			node.position = sample.position + Vector3.UP * 0.08
			if train.fault and "脱轨" in train.state:
				node.rotate_object_local(Vector3.RIGHT, 0.14)
			if node.has_method("sync_motion"):
				node.sync_motion(train.distance_m, train.velocity, simulation.paused, false)
		train_connections[train.id].update_from_cars(train_nodes[train.id])

func add_scenery(id: String, pos: Vector3, angle: float) -> void:
	var item = {"definition":id, "position":Graph.v_array(pos), "yaw":angle}
	scenery_items.append(item)
	var node = Geometry.scenery_model(catalog.scenery[id], simulation.ratio())
	node.position = Vector3(pos.x, terrain.height_at(pos.x, pos.z), pos.z)
	node.rotation.y = angle
	scenery_root.add_child(node)
	scenery_placed.emit(id, node.position)

func refresh_scenery_heights() -> void:
	for i in scenery_items.size():
		var pos = Graph.array_v(scenery_items[i].position)
		scenery_root.get_child(i).position.y = terrain.height_at(pos.x, pos.z)

func current_train() -> Dictionary:
	for t in simulation.trains:
		if t.id == selected_train:
			return t
	return {}

func refresh_train_list() -> void:
	clear_children(train_buttons)
	for t in simulation.trains:
		var b = button(train_buttons, ("●  " if t.id == selected_train else "○  ") + t.name, func(): selected_train = t.id; refresh_train_list())
		if t.id == selected_train:
			b.add_theme_color_override("font_color", MINT)
	if simulation.trains.is_empty():
		label(train_buttons, "还没有列车，请从左侧添加。", 12, MUTED)
	var train = current_train()
	if not train.is_empty():
		var maximum = 600.0
		for id in train.cars:
			maximum = minf(maximum, catalog.vehicles[id].max_kmh)
		speed_slider.max_value = maximum
		speed_slider.set_value_no_signal(train.target)

func refresh_stats() -> void:
	if not is_instance_valid(rail_count):
		return
	var length = 0.0
	for edge in graph.edges.values():
		length += edge.length / 10.0
	rail_count.text = "%d 个轨道零件 · %.2f m\n%d 个开放端点 · %d 个编组\n%d 个布景 · %d 个 Mod" % [graph.parts.size(), length, graph.open_end_count(), simulation.trains.size(), scenery_items.size(), catalog.packages.size()]
	var spec = RailCatalog.SCALES[graph.scale_name]
	scale_label.text = "%s  /  1:%s  /  %s mm" % [graph.scale_name, str(spec.ratio), str(spec.gauge_mm)]

func update_ui() -> void:
	var t = current_train()
	if not t.is_empty():
		selected_label.text = t.name
		speed_slider.editable = not t.has("derailed_cars")
		speed_label.text = "%04.1f" % (absf(t.velocity) * 3.6)
		speed_slider.set_value_no_signal(t.target)
		var mass = 0.0
		for id in t.cars:
			mass += catalog.vehicles[id].mass_kg
		telemetry.text = "目标速度    %d km/h\n模型速度    %.1f mm/s\n运行方向    %s\n编组质量    %.0f t · %d 辆\n牵引 / 制动    %.1f / %.1f kN\n当前坡度    %+.2f %%\n状态    %s" % [t.target, absf(t.velocity) / simulation.ratio() * 1000, "正向 →" if t.direction == 1 else "← 反向", mass / 1000, t.cars.size(), t.traction / 1000, t.braking / 1000, t.grade, t.state]
	else:
		selected_label.text = "未选择列车"
		speed_label.text = "00.0"
		telemetry.text = "添加编组后即可独立控制速度与方向。"
	pause_button.text = "▶ 继续" if simulation.paused else "Ⅱ 暂停"
	performance_label.text = "%d FPS   ·   60 Hz 物理   ·   本地场景" % Engine.get_frames_per_second()

func _physics_process(dt: float) -> void:
	if simulation:
		simulation.tick(dt)
		derailment.sync(simulation)

func _process(dt: float) -> void:
	if not simulation:
		return
	update_train_visuals()
	if follow_train and not current_train().is_empty():
		var t = current_train()
		camera_target = camera_target.lerp(simulation.car_samples(t)[0].position, minf(dt * 3, 1))
	update_camera()
	preview_time += dt
	if preview_time > 0.04:
		update_preview()
		preview_time = 0.0
	if brush_active and mode == "terrain" and valid_placement:
		terrain.brush(placement, brush_radius, brush_strength, terrain_mode, dt, flatten_height)
		refresh_scenery_heights()
	ui_time += dt
	if ui_time > 0.2:
		update_ui()
		ui_time = 0.0
	if toast_time > 0:
		toast_time -= dt
		if toast_time <= 0:
			toast_label.text = ""

func update_camera() -> void:
	camera.position = camera_target + Vector3(sin(camera_yaw) * cos(camera_pitch), sin(camera_pitch), cos(camera_yaw) * cos(camera_pitch)) * camera_distance
	camera.look_at(camera_target)

func reset_camera() -> void:
	camera_target = Vector3(0, 0, 0)
	camera_yaw = -0.55
	camera_pitch = 0.88
	camera_distance = clampf(34.0 * maxf(terrain.width / Terrain.WIDTH, terrain.depth / Terrain.DEPTH), 3.0, RailSceneFormat.MAX_CAMERA_DISTANCE)
	follow_train = false

func pan_camera(relative: Vector2) -> void:
	var right = camera.global_basis.x
	var forward = Vector3(right.z, 0, -right.x)
	# Drag the ground with the cursor: screen-down is opposite to ground-forward.
	camera_target -= (right * relative.x - forward * relative.y) * camera_distance * 0.0013
	follow_train = false

func mouse_world() -> Vector3:
	var p = get_viewport().get_mouse_position()
	return terrain.ray_hit(camera.project_ray_origin(p), camera.project_ray_normal(p))

func over_canvas() -> bool:
	var p = get_viewport().get_mouse_position()
	for hud in [top_panel, bottom_panel, left_panel, right_panel]:
		if hud.get_global_rect().has_point(p):
			return false
	return not file_dialog.visible and not mod_dialog.visible and not confirm_dialog.visible and not new_scene_dialog.visible

func update_preview() -> void:
	valid_placement = false
	marker.visible = false
	brush_ring.visible = false
	if preview:
		preview.visible = false
	if placing_train:
		status_label.text = "悬浮轨道预览编组 · 蓝色可放置 / 红色不可放置 · Tab 切换方向 · Esc 取消"
	elif mode == "track" and not erase:
		status_label.text = connection_hint() if auto_connect else track_placement_hint()
	if not over_canvas():
		return
	if mode == "operate" and placing_train:
		update_train_preview(pick_track())
		return
	if mode == "track" and not erase:
		var snap = pick_endpoint()
		if auto_connect:
			update_connection_preview(snap)
			return
		var hit: Vector3 = mouse_world() if snap.is_empty() else snap.position
		if hit.is_finite():
			update_track_preview(hit, snap)
		return
	var hit = mouse_world()
	if not hit.is_finite():
		return
	placement = hit
	placement_yaw = yaw
	valid_placement = true
	snapped = false
	if mode == "terrain":
		brush_ring.position = hit + Vector3.UP * 0.08
		brush_ring.scale = Vector3(brush_radius, 0.2, brush_radius)
		brush_ring.visible = true
	elif mode == "scenery" and not erase:
		if selected_scenery != preview_key or preview == null:
			if preview:
				preview.queue_free()
			preview = Geometry.scenery_model(catalog.scenery[selected_scenery], simulation.ratio())
			add_child(preview)
			preview_key = selected_scenery
		preview.position = placement
		preview.rotation.y = yaw
		preview.visible = true
	elif erase:
		marker.position = hit + Vector3.UP * 0.1
		marker.visible = true

func update_track_preview(hit: Vector3, snap: Dictionary) -> void:
	var paths = graph.make_paths(catalog.tracks[selected_track], Vector3.ZERO, 0, grade, mirror, flex_options)
	var endpoints = Graph.placement_endpoints(paths, catalog.tracks[selected_track], 0, grade, mirror, flex_options)
	track_placement_endpoint %= endpoints.size()
	var endpoint: Dictionary = endpoints[track_placement_endpoint]
	var anchor = Vector3(snappedf(hit.x, 0.05), placement_height, snappedf(hit.z, 0.05))
	placement_yaw = yaw
	snapped = not snap.is_empty()
	if snapped:
		anchor = snap.position
		# Selected endpoint faces into the existing rail; the entire piece rotates
		# around that endpoint, including a turnout's curved exit.
		placement_yaw = atan2(snap.out.z, -snap.out.x) - atan2(-endpoint.out.z, endpoint.out.x)
	placement = anchor - endpoint.position.rotated(Vector3.UP, placement_yaw)
	valid_placement = true
	var key = selected_track + str(mirror) + str(grade) + str(flex_options)
	if key != preview_key or preview == null:
		if preview:
			preview.queue_free()
		preview = Geometry.track(paths, RailCatalog.SCALES[graph.scale_name].gauge_mm / 100, true)
		add_child(preview)
		preview_key = key
	preview.position = placement + Vector3.UP * 0.012
	preview.rotation.y = placement_yaw
	preview.visible = true
	marker.position = anchor + Vector3.UP * 0.10
	marker.visible = true
	if catalog.tracks[selected_track].kind == "flex":
		var world_paths = graph.make_paths(catalog.tracks[selected_track], placement, placement_yaw, grade, mirror, flex_options)
		var measured = RailFlexTrack.measure(world_paths[0], terrain.width, terrain.depth)
		valid_placement = measured.error.is_empty()
		if valid_placement and RailFlexTrack.self_crosses(world_paths[0]):
			valid_placement = false
			measured.error = "曲线自交，请减小长度或增大半径"
		Geometry.apply_preview_material(preview, Geometry.material(TRAIN_PREVIEW_VALID if valid_placement else TRAIN_PREVIEW_INVALID))
		status_label.text = ("柔轨 %.0f mm · " % (measured.length * 100) + track_placement_hint()) if valid_placement else measured.error

func update_connection_preview(target: Dictionary) -> void:
	if not connection_start.is_empty() and not graph.is_open_endpoint(connection_start):
		reset_connection()
	if target.is_empty():
		return
	marker.position = target.position + Vector3.UP * 0.12
	marker.visible = true
	# Clicking even an invalid candidate explains the failure and retains A.
	valid_placement = true
	if connection_start.is_empty():
		return
	var key = str(connection_start.edge) + str(connection_start.end) + str(target.edge) + str(target.end) + str(connection_min_radius)
	if key != connection_key:
		connection_plan = graph.plan_connection(connection_start, target, terrain.width, terrain.depth, connection_min_radius / 100.0)
		connection_key = key
		if preview:
			preview.queue_free()
		preview = null
		if connection_plan.has("points"):
			preview = Geometry.track([connection_plan.points], RailCatalog.SCALES[graph.scale_name].gauge_mm / 100, true)
			Geometry.apply_preview_material(preview, Geometry.material(TRAIN_PREVIEW_VALID if connection_plan.error.is_empty() else TRAIN_PREVIEW_INVALID))
			add_child(preview)
			preview.position.y = 0.012
	if preview:
		preview.visible = true
	if connection_plan.error.is_empty():
		status_label.text = "可连接 · 长 %.0f mm · 最大坡度 %.1f%% · 左键完成 · Esc 取消" % [connection_plan.length * 100, connection_plan.max_grade * 100]
	else:
		status_label.text = connection_plan.error + " · 可换选其他端点"

func choose_connection_endpoint(target: Dictionary) -> bool:
	if not graph.is_open_endpoint(target):
		toast("请选择开放端点")
		return false
	if connection_start.is_empty():
		connection_start = graph.endpoint(target.edge, target.end)
		connection_marker.position = connection_start.position + Vector3.UP * 0.14
		connection_marker.visible = true
		connection_key = ""
		toast("已选择起点，请点击第二个开放端点。")
		return false
	if target.position.distance_to(connection_start.position) < 0.0001:
		reset_connection()
		toast("已清除起点，请重新选择。")
		return false
	# Revalidate on commit so deleted/connected endpoints cannot use stale plans.
	var result = graph.plan_connection(connection_start, target, terrain.width, terrain.depth, connection_min_radius / 100.0)
	if not result.error.is_empty():
		toast("无法自动连接：" + result.error, 7)
		return false
	push_undo()
	graph.add_part("core:" + graph.scale_name + ":flex_link", connection_start.position, 0, 0, false, {"controls":result.controls})
	reset_connection()
	if preview:
		preview.queue_free()
		preview = null
	preview_key = ""
	rebuild_rails()
	layout_changed.emit()
	toast("已连接两个端点 · 柔轨 %.0f mm · Ctrl+Z 可撤销" % (result.length * 100), 6)
	return true

func update_train_preview(hit: Dictionary) -> void:
	valid_placement = false
	if preview:
		preview.visible = false
	if hit.is_empty():
		return
	var result = simulation.train_placement(draft_cars, hit.edge, hit.distance, train_placement_reversed)
	valid_placement = result.error.is_empty()
	status_label.text = ("可放置 · 左键确认" if valid_placement else result.error) + " · Tab 切换方向 · Esc 取消"
	if result.train.is_empty():
		return
	var key = "train:" + graph.scale_name + ":" + str(draft_cars)
	if preview == null or preview_key != key:
		if preview:
			preview.queue_free()
		preview = Node3D.new()
		train_preview_material = StandardMaterial3D.new()
		train_preview_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		train_preview_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		for id in draft_cars:
			var node = Geometry.vehicle(catalog.vehicles[id], simulation.ratio())
			Geometry.apply_preview_material(node, train_preview_material)
			preview.add_child(node)
		var connections = VehicleConnections.new()
		connections.setup(draft_cars, catalog, simulation.ratio())
		Geometry.apply_preview_material(connections, train_preview_material)
		preview.add_child(connections)
		add_child(preview)
		preview_key = key
	train_preview_material.albedo_color = TRAIN_PREVIEW_VALID if valid_placement else TRAIN_PREVIEW_INVALID
	var samples = simulation.car_samples(result.train, true)
	for i in samples.size():
		var sample = samples[i]
		var tangent: Vector3 = sample.tangent
		var side = tangent.cross(Vector3.UP).normalized()
		var node: Node3D = preview.get_child(i)
		node.basis = Basis(tangent, side.cross(tangent).normalized(), side)
		node.position = sample.position + Vector3.UP * 0.08
	preview.get_node("Connections").update_from_cars(preview.get_children().slice(0, samples.size()))
	preview.visible = true

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			camera_yaw -= event.relative.x * 0.006
			camera_pitch = clampf(camera_pitch + event.relative.y * 0.005, 0.15, 1.52)
		elif Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
			pan_camera(event.relative)
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			brush_active = false
		if not over_canvas():
			return
		if event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				camera_distance = maxf(3.0, camera_distance * 0.9)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				camera_distance = minf(RailSceneFormat.MAX_CAMERA_DISTANCE, camera_distance * 1.1)
			elif event.button_index == MOUSE_BUTTON_LEFT:
				update_preview()
				if valid_placement:
					canvas_click()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			toggle_pause()
		elif event.keycode == KEY_R:
			yaw += PI / 12
		elif event.keycode == KEY_F:
			mirror = not mirror
			preview_key = ""
		elif event.keycode == KEY_ESCAPE:
			placing_train = false
			brush_active = false
			set_mode("operate")
		elif event.keycode == KEY_Z and event.ctrl_pressed:
			if event.shift_pressed:
				redo()
			else:
				undo()
		elif event.keycode == KEY_S and event.ctrl_pressed:
			show_file(true)
		elif event.keycode == KEY_O and event.ctrl_pressed:
			show_file(false)
		elif event.keycode == KEY_F12:
			capture_frame()

func _input(event: InputEvent) -> void:
	# Handle Tab before GUI focus navigation consumes it. Keep normal Tab
	# navigation in dialogs, editors and tools that do not use placement anchors.
	if event is InputEventKey and event.keycode == KEY_TAB and ((placing_train and mode == "operate") or (mode == "track" and not erase and not auto_connect)):
		var focus = get_viewport().gui_get_focus_owner()
		if not file_dialog.visible and not mod_dialog.visible and not confirm_dialog.visible and not new_scene_dialog.visible and not (focus is LineEdit or focus is TextEdit):
			if event.pressed and not event.echo:
				if mode == "track":
					cycle_track_endpoint()
				else:
					train_placement_reversed = not train_placement_reversed
					update_preview()
			get_viewport().set_input_as_handled()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		brush_active = false

func canvas_click() -> void:
	if mode == "terrain":
		push_undo()
		brush_active = true
		return
	if mode == "track":
		if auto_connect:
			choose_connection_endpoint(pick_endpoint())
		elif erase:
			var hit = pick_track()
			if not hit.is_empty():
				remove_track(hit.part.uid)
		else:
			place_track()
	elif mode == "scenery":
		if erase:
			var best = -1
			var distance = 1.2
			for i in scenery_items.size():
				var pos = Graph.array_v(scenery_items[i].position)
				var d = Vector2(pos.x, pos.z).distance_to(Vector2(placement.x, placement.z))
				if d < distance:
					distance = d
					best = i
			if best >= 0:
				push_undo()
				scenery_items.remove_at(best)
				var child = scenery_root.get_child(best)
				scenery_root.remove_child(child)
				child.queue_free()
		else:
			push_undo()
			add_scenery(selected_scenery, placement, yaw)
		refresh_stats()
	elif mode == "operate":
		var hit = pick_track()
		if hit.is_empty():
			return
		if placing_train:
			var result = simulation.train_placement(draft_cars, hit.edge, hit.distance, train_placement_reversed)
			if not result.error.is_empty():
				toast("无法放置：" + result.error, 7)
				return
			push_undo()
			var t = simulation.add_train(draft_cars, hit.edge, hit.distance, "", train_placement_reversed)
			if t.is_empty():
				toast("无法放置：编组需要机车、足够的后方轨道，且不能与已有列车重叠。", 7)
			else:
				selected_train = t.id
				placing_train = false
				update_preview()
				status_label.text = OPERATE_HINT
				refresh_train_list()
				refresh_stats()
				toast("编组已就位，使用右侧滑块调速。")
			return
		for t in simulation.trains:
			for sample in simulation.car_samples(t):
				if sample.position.distance_to(hit.position) < 1.7:
					selected_train = t.id
					refresh_train_list()
					return
		if catalog.tracks[hit.part.definition].kind == "turnout":
			if simulation.occupied_part(hit.part.uid):
				toast("道岔正被列车占用，无法扳动。")
			else:
				push_undo()
				hit.part.branch = 1 - int(hit.part.get("branch", 0))
				for train in simulation.trains:
					simulation.refresh_route(train)
				rebuild_rails()
				toast("道岔已切换至" + ("直股" if hit.part.branch == 0 else "侧股"))

func place_track() -> bool:
	var paths = graph.make_paths(catalog.tracks[selected_track], placement, placement_yaw, grade, mirror, flex_options)
	if catalog.tracks[selected_track].kind == "flex":
		var measured = RailFlexTrack.measure(paths[0], terrain.width, terrain.depth)
		if not measured.error.is_empty() or RailFlexTrack.self_crosses(paths[0]):
			toast(measured.error if not measured.error.is_empty() else "柔性轨道不能自交", 7)
			return false
	for path in paths:
		for p in path:
			if not terrain.contains_point(p, 0.2):
				toast("轨道超出沙盘范围")
				return false
	for old in graph.parts:
		if Graph.array_v(old.position).distance_to(placement) < 0.02 and absf(angle_difference(old.yaw, placement_yaw)) < 0.02 and old.definition == selected_track and old.get("mirror", false) == mirror and old.get("flex", {}) == (RailFlexTrack.settings(catalog.tracks[selected_track], flex_options) if catalog.tracks[selected_track].kind == "flex" else {}):
			toast("这里已有相同轨道")
			return false
	push_undo()
	graph.add_part(selected_track, placement, placement_yaw, grade, mirror, flex_options)
	rebuild_rails()
	layout_changed.emit()
	toast("已铺设 " + catalog.tracks[selected_track].name + (" · 端点已连接" if snapped else ""))
	return true

func pick_track() -> Dictionary:
	var mouse = get_viewport().get_mouse_position()
	var best = {}
	var best_distance = 18.0
	for edge in graph.edges.values():
		for i in range(edge.points.size() - 1):
			if camera.is_position_behind(edge.points[i]):
				continue
			var a = camera.unproject_position(edge.points[i])
			var b = camera.unproject_position(edge.points[i + 1])
			var fraction = clampf((mouse - a).dot(b - a) / maxf((b - a).length_squared(), 0.00001), 0, 1)
			var distance = mouse.distance_to(a.lerp(b, fraction))
			if distance < best_distance:
				best_distance = distance
				best = {"edge":edge.id, "part":edge.part, "distance":lerpf(edge.distances[i], edge.distances[i + 1], fraction), "position":edge.points[i].lerp(edge.points[i + 1], fraction)}
	return best

func pick_endpoint() -> Dictionary:
	var mouse = get_viewport().get_mouse_position()
	var best = {}
	var distance = 24.0
	for id in graph.edges:
		for end in [0, 1]:
			if not graph.connections[graph.endpoint_key(id, end)].is_empty():
				continue
			var ep = graph.endpoint(id, end)
			if camera.is_position_behind(ep.position):
				continue
			var d = mouse.distance_to(camera.unproject_position(ep.position))
			if d < distance:
				distance = d
				best = ep
	return best

func remove_track(uid: int) -> void:
	if simulation.occupied_part(uid):
		toast("这段轨道正被列车占用，请先移走列车。")
		return
	push_undo()
	# Trim only unoccupied history/future entries; retain the complete path
	# under every vehicle so editing cannot teleport a consist at a switch.
	for t in simulation.trains:
		var base = 0.0
		var cut_front = 0
		var cut_back = t.route.size()
		var subtract = 0.0
		for i in t.route.size():
			var e = graph.edges[t.route[i].edge]
			if int(e.part.uid) == uid:
				if base + e.length < t.s - simulation.consist_length(t.cars):
					cut_front = i + 1
					subtract = base + e.length
				else:
					cut_back = mini(cut_back, i)
			base += e.length
		t.route = t.route.slice(cut_front, cut_back)
		t.s -= subtract
	graph.remove_part(uid)
	rebuild_rails()
	layout_changed.emit()

func conform_terrain() -> void:
	push_undo()
	flatten_rail_bed()
	terrain.rebuild()
	refresh_scenery_heights()
	toast("已按线路高程整平轨道路基")

func flatten_rail_bed() -> void:
	for edge in graph.edges.values():
		for i in range(0, edge.points.size(), 2):
			var p: Vector3 = edge.points[i]
			terrain.brush(p, 0.60, 3.0, "flatten", 1.0, p.y - 0.015)

func replace_consist() -> void:
	var t = current_train()
	if t.is_empty() or absf(t.velocity) > 0.05:
		toast("先选中列车并停车，再修改编组。")
		return
	push_undo()
	if not simulation.reconfigure(t, draft_cars):
		toast("编组不可用，或线路空闲长度不足；已保留原编组。")
	else:
		toast("已更新编组")
	rebuild_trains()
	refresh_train_list()

func command_stop() -> void:
	var t = current_train()
	if not t.is_empty():
		t.target = 0.0

func toggle_pause() -> void:
	simulation.paused = not simulation.paused
	update_ui()

func toast(message: String, duration: float = 4.0) -> void:
	toast_label.text = message
	toast_time = duration

func confirm(message: String, callback: Callable) -> void:
	pending_confirm = callback
	confirm_dialog.dialog_text = message
	confirm_dialog.popup_centered(Vector2i(600, 170))

func show_mods() -> void:
	var lines: Array[String] = ["已加载的本地数据包（API v1）：", ""]
	for pack in catalog.packages:
		lines.append("  ●  %s  v%s  [%s]" % [pack.name, pack.version, pack.id])
	lines.append("\n轨道 %d 种 · 车辆 %d 种 · 布景 %d 种" % [catalog.tracks.size(), catalog.vehicles.size(), catalog.scenery.size()])
	lines.append("\n安装：将 Mod 文件夹放入项目 mods/ 或用户目录 mods/，重启生效。\n支持 JSON 零件定义与 GLB 车辆 / 布景模型。\n开发说明：docs/MOD_API.md；示例：mods/alpine_pack/manifest.json")
	lines.append("\n用户目录：" + ProjectSettings.globalize_path("user://"))
	if not catalog.errors.is_empty():
		lines.append("\n未加载：\n" + "\n".join(catalog.errors))
	mod_dialog.dialog_text = "\n".join(lines)
	mod_dialog.popup_centered()

func snapshot() -> Dictionary:
	return {"format":"track-playground", "version":1, "scale":graph.scale_name, "sandbox":{"width":terrain.width,"depth":terrain.depth}, "parts":graph.parts.duplicate(true), "next_part":graph.next_uid, "scenery":scenery_items.duplicate(true), "terrain":Array(terrain.heights), "paint":Array(terrain.paints), "trains":simulation.trains.duplicate(true), "next_train":simulation.next_uid, "physics":{"wet":simulation.wet_rails,"derailments":simulation.derailments}, "camera":{"target":Graph.v_array(camera_target),"yaw":camera_yaw,"pitch":camera_pitch,"distance":camera_distance}, "required_mods":catalog.packages.map(func(p): return p.id)}

func push_undo() -> void:
	undo_stack.append(snapshot())
	if undo_stack.size() > 30:
		undo_stack.pop_front()
	redo_stack.clear()

func undo() -> void:
	if undo_stack.is_empty():
		toast("没有可撤销的编辑")
		return
	redo_stack.append(snapshot())
	apply_snapshot(undo_stack.pop_back())
	toast("已撤销；物理已暂停。Ctrl+Shift+Z 重做。")

func redo() -> void:
	if redo_stack.is_empty():
		return
	undo_stack.append(snapshot())
	apply_snapshot(redo_stack.pop_back())
	toast("已重做；物理已暂停。")

func show_file(save: bool) -> void:
	file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE if save else FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.title = "保存铁路场景" if save else "打开铁路场景"
	file_dialog.current_dir = ProjectSettings.globalize_path(user_dir)
	if save:
		file_dialog.current_file = "我的铁路.railway"
	file_dialog.popup_centered()

func file_chosen(path: String) -> void:
	if file_dialog.file_mode == FileDialog.FILE_MODE_SAVE_FILE:
		if save_layout(path):
			toast("已保存：" + path, 7)
	else:
		var json = JSON.new()
		if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
			toast("读取失败：不是有效场景文件", 7)
			return
		var problem = validate_snapshot(json.data)
		if not problem.is_empty():
			toast("读取失败：" + problem, 9)
			return
		push_undo()
		apply_snapshot(json.data)
		toast("场景已打开，物理处于暂停状态。", 6)

func save_layout(path: String) -> bool:
	var file = FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if not file:
		toast("保存失败：无法写入该目录")
		return false
	file.store_string(JSON.stringify(snapshot()))
	file.close()
	var err = DirAccess.rename_absolute(path + ".tmp", path)
	if err != OK:
		toast("保存失败：无法替换目标文件（%s）" % error_string(err))
		return false
	return true

func validate_snapshot(data: Dictionary) -> String:
	return RailSceneFormat.validate(data, catalog)

func apply_snapshot(data: Dictionary) -> bool:
	var problem = validate_snapshot(data)
	if not problem.is_empty():
		toast(problem, 7)
		return false
	# Validate all routes in a temporary graph before touching the scene.
	var check_graph = Graph.new(catalog)
	check_graph.scale_name = data.scale
	check_graph.parts = data.parts.duplicate(true)
	check_graph.rebuild()
	var check_sim = Simulation.new(check_graph, catalog)
	for t in data.trains:
		for i in t.route.size():
			var e = t.route[i]
			if not e is Dictionary or not check_graph.edges.has(e.get("edge", "")) or not e.get("rev") is bool:
				toast("场景中的列车引用了不存在的轨道")
				return false
			if i > 0:
				var previous = t.route[i - 1]
				var candidates = check_graph.connections[check_graph.endpoint_key(previous.edge, 0 if previous.rev else 1)]
				if not candidates.any(func(candidate): return candidate.edge == e.edge and candidate.rev == e.rev):
					toast("列车的轨道路径不连续")
					return false
		if t.s < check_sim.consist_length(t.cars) - 0.001 or t.s > check_sim.route_length(t) + 0.001:
			toast("列车位置超出轨道路径")
			return false
	var sandbox = data.get("sandbox", {"width":Terrain.WIDTH, "depth":Terrain.DEPTH})
	empty_scene(false, sandbox.width, sandbox.depth)
	graph.scale_name = data.scale
	graph.parts = data.parts.duplicate(true)
	graph.next_uid = int(data.get("next_part", 1))
	graph.rebuild()
	terrain.heights = PackedFloat32Array(data.terrain)
	terrain.paints = PackedFloat32Array(data.paint)
	terrain.rebuild()
	for item in data.scenery:
		add_scenery(item.definition, Graph.array_v(item.position), float(item.get("yaw", 0)))
	simulation.trains = data.trains.duplicate(true)
	for train in simulation.trains:
		simulation.refresh_route(train)
	simulation.next_uid = int(data.get("next_train", 1))
	simulation.paused = true
	simulation.wet_rails = data.get("physics", {}).get("wet", false)
	simulation.derailments = data.get("physics", {}).get("derailments", true)
	selected_train = simulation.trains[0].id if not simulation.trains.is_empty() else -1
	var cam = data.get("camera", {})
	camera_target = Graph.array_v(cam.get("target", [0,0,0]))
	camera_yaw = cam.get("yaw", -0.55)
	camera_pitch = cam.get("pitch", 0.88)
	camera_distance = cam.get("distance", 34.0)
	selected_track = "core:" + graph.scale_name + ":straight"
	rebuild_rails()
	rebuild_trains()
	refresh_train_list()
	refresh_stats()
	set_mode(mode)
	layout_changed.emit()
	return true

func capture_preview() -> void:
	await get_tree().create_timer(5.0).timeout
	await capture_frame()
	if "--capture-exit" in OS.get_cmdline_user_args():
		get_tree().quit()

func capture_frame() -> void:
	await RenderingServer.frame_post_draw
	var path = "res://screenshots/overview-n.png" if graph.scale_name == "N" else "res://screenshots/overview.png"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://screenshots"))
	get_viewport().get_texture().get_image().save_png(path)
	print("CAPTURE: " + ProjectSettings.globalize_path(path))
	toast("画面已保存到 screenshots/", 3)

func integration_test() -> void:
	await get_tree().process_frame
	var script = load("res://tests/integration.gd")
	if not script or not script.can_instantiate():
		get_tree().quit(1)
		return
	var test = script.new()
	var failures = test.run(self)
	var turnout_test = load("res://tests/turnout_routing.gd").new()
	failures += turnout_test.run(self)
	var placement_test = load("res://tests/train_placement.gd").new()
	failures += await placement_test.run(self)
	var derail_test = load("res://tests/derailment.gd").new()
	failures += await derail_test.run(self)
	var track_placement_test = load("res://tests/track_placement.gd").new()
	failures += await track_placement_test.run(self)
	var flex_track_test = load("res://tests/flex_track.gd").new()
	failures += await flex_track_test.run(self)
	var steam_locomotive_test = load("res://tests/steam_locomotive.gd").new()
	failures += await steam_locomotive_test.run(self)
	var connections_test = load("res://tests/vehicle_connections.gd").new()
	failures += await connections_test.run(self)
	print("INTEGRATION_RESULT failures=" + str(failures))
	get_tree().quit(1 if failures > 0 else 0)

func flex_test() -> void:
	await get_tree().process_frame
	var test = load("res://tests/flex_track.gd").new()
	var failures = await test.run(self, "--flex-capture" in OS.get_cmdline_user_args())
	get_tree().quit(1 if failures > 0 else 0)

func steam_test() -> void:
	await get_tree().process_frame
	var test = load("res://tests/steam_locomotive.gd").new()
	var failures = await test.run(self, "--steam-capture" in OS.get_cmdline_user_args())
	get_tree().quit(1 if failures > 0 else 0)

func connections_test() -> void:
	await get_tree().process_frame
	var test = load("res://tests/vehicle_connections.gd").new()
	var failures = await test.run(self, "--connections-capture" in OS.get_cmdline_user_args())
	get_tree().quit(1 if failures > 0 else 0)
