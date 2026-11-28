extends RefCounted

var checks = 0
var failures = 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + message)
	else:
		failures += 1
		push_error("FAIL: " + message)

func send(app, event: InputEvent) -> void:
	# Use the real Input pipeline, including Godot's touch-to-mouse emulation
	# and GUI dispatch. Input expects window coordinates, unlike push_input.
	Input.parse_input_event(event.xformed_by(app.get_viewport().get_screen_transform()))
	Input.flush_buffered_events()

func touch(app, index: int, position: Vector2, pressed: bool, canceled: bool = false) -> void:
	var event = InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = pressed
	event.canceled = canceled
	send(app, event)

func drag(app, index: int, position: Vector2) -> void:
	var event = InputEventScreenDrag.new()
	event.index = index
	event.position = position
	send(app, event)

func step(app, dt: float = 1.0 / 60.0) -> void:
	app.touch_camera.update(dt, app.mode == "terrain")
	app.update_camera()

func settle(app) -> void:
	for i in 3:
		await app.get_tree().process_frame

func run(app) -> int:
	var was_processing: bool = app.is_processing()
	var was_physics: bool = app.is_physics_processing()
	var was_emulating = Input.emulate_mouse_from_touch
	Input.emulate_mouse_from_touch = true
	app.set_process(false)
	app.set_physics_process(false)
	app.graph.scale_name = "HO"
	app.empty_scene()
	app.set_mode("scenery")
	app.set_ui_visible(true)
	await settle(app)
	var center: Vector2 = app.get_viewport().get_visible_rect().get_center()
	check(app.canvas_contains(center), "触屏测试起点位于沙盘")
	app.update_camera()
	var view: Transform3D = app.camera.global_transform
	touch(app, 4, center, true)
	check(app.scenery_items.is_empty(), "触屏按下及模拟鼠标事件不提前放置")
	drag(app, 4, center + Vector2(2, 1))
	step(app)
	check(view.is_equal_approx(app.camera.global_transform), "轻点抖动不改变视角")
	touch(app, 4, center + Vector2(2, 1), false)
	check(app.scenery_items.size() == 1 and not app.brush_active, "轻点抬手只放置一次，不重复执行模拟鼠标点击")
	var expected = app.terrain.ray_hit(app.camera.project_ray_origin(center + Vector2(2, 1)), app.camera.project_ray_normal(center + Vector2(2, 1)))
	check(app.Graph.array_v(app.scenery_items[0].position).distance_to(expected) < 0.001, "轻点使用触点坐标命中场景")

	app.empty_scene()
	app.set_mode("track")
	app.undo_stack.clear()
	await settle(app)
	app.update_camera()
	var yaw: float = app.camera_yaw
	var pitch: float = app.camera_pitch
	touch(app, 4, center, true)
	drag(app, 4, center + Vector2(65, 25))
	step(app)
	touch(app, 4, center + Vector2(65, 25), false)
	check(app.camera_yaw < yaw and app.camera_pitch > pitch, "单指水平及垂直拖动旋转相机")
	check(app.graph.parts.is_empty() and app.undo_stack.is_empty(), "铺轨模式旋转不放置轨道也不产生撤销记录")
	# A fast swipe can begin and end entirely between rendered frames.
	yaw = app.camera_yaw
	touch(app, 1, center, true)
	drag(app, 1, center + Vector2(50, 0))
	touch(app, 1, center + Vector2(50, 0), false)
	check(app.camera_yaw < yaw and app.graph.parts.is_empty(), "单帧内快速滑动仍旋转且不会误判为轻点")

	app.reset_camera()
	app.update_camera()
	var a = center + Vector2(-80, 0)
	var b = center + Vector2(80, 0)
	yaw = app.camera_yaw
	var distance: float = app.camera_distance
	var target: Vector3 = app.camera_target
	touch(app, 7, a, true)
	touch(app, 2, b, true)
	a += Vector2(30, 20)
	b += Vector2(30, 20)
	drag(app, 7, a)
	drag(app, 2, b)
	step(app)
	check(app.camera_target.distance_to(target) > 0.1 and is_equal_approx(app.camera_yaw, yaw) and is_equal_approx(app.camera_distance, distance), "双指同向拖动只平移，支持非连续触点编号")
	target = app.camera_target
	a.x -= 80
	b.x += 80
	drag(app, 7, a)
	drag(app, 2, b)
	step(app)
	check(is_equal_approx(app.camera_distance, distance * 0.5) and app.camera_target.is_equal_approx(target), "双指张开按距离比例放大，对称捏合不漂移")
	a.x += 80
	b.x -= 80
	drag(app, 7, a)
	drag(app, 2, b)
	step(app)
	check(is_equal_approx(app.camera_distance, distance), "双指合拢缩小")
	touch(app, 2, b, false)
	view = app.camera.global_transform
	drag(app, 7, a + Vector2(80, 40))
	step(app)
	touch(app, 7, a + Vector2(80, 40), false)
	check(view.is_equal_approx(app.camera.global_transform) and app.graph.parts.is_empty(), "双指变单指不突然旋转，抬手不误放置")

	# Ignore extra fingers, resume from the current two-finger baseline.
	touch(app, 0, a, true)
	touch(app, 1, b, true)
	touch(app, 8, center, true)
	view = app.camera.global_transform
	drag(app, 0, a + Vector2(20, 0))
	step(app)
	touch(app, 8, center, false)
	step(app)
	check(view.is_equal_approx(app.camera.global_transform), "第三指加入和移除不会导致跳变")
	touch(app, 0, a + Vector2(20, 0), false, true)
	check(app.touch_camera.points.is_empty() and app.graph.parts.is_empty(), "系统取消手势会清理所有触点且不点击")
	touch(app, 1, b, false)

	# Camera limits and degenerate pinches remain finite.
	app.camera_distance = 3.1
	touch(app, 0, center - Vector2(20, 0), true)
	touch(app, 1, center + Vector2(20, 0), true)
	drag(app, 0, center - Vector2(80, 0))
	drag(app, 1, center + Vector2(80, 0))
	step(app)
	check(is_equal_approx(app.camera_distance, 3.0), "触屏放大遵守最近距离")
	app.camera_distance = RailSceneFormat.MAX_CAMERA_DISTANCE * 0.9
	drag(app, 0, center - Vector2(20, 0))
	drag(app, 1, center + Vector2(20, 0))
	step(app)
	check(is_equal_approx(app.camera_distance, RailSceneFormat.MAX_CAMERA_DISTANCE), "触屏缩小遵守最远距离")
	drag(app, 0, center)
	drag(app, 1, center)
	step(app)
	check(is_finite(app.camera_distance) and app.camera.global_transform.is_finite(), "两指重合不产生无限缩放或无效变换")
	touch(app, 0, center, false)
	touch(app, 1, center, false)
	app.reset_camera()
	app.update_camera()

	# UI ownership survives fingers leaving a panel, and canvas ownership
	# survives crossing one. Synthetic events must not click UI on release.
	var panel_point: Vector2 = app.left_panel.get_global_rect().position + Vector2(10, 10)
	view = app.camera.global_transform
	touch(app, 0, panel_point, true)
	drag(app, 0, center)
	step(app)
	touch(app, 0, center, false)
	check(view.is_equal_approx(app.camera.global_transform) and app.graph.parts.is_empty(), "从面板开始拖到沙盘不抢占手势或触发场景操作")
	touch(app, 0, center, true)
	drag(app, 0, panel_point)
	step(app)
	touch(app, 0, panel_point, false)
	check(app.touch_camera.points.is_empty() and app.graph.parts.is_empty(), "沙盘拖动跨入面板仍能正确收尾")
	app.reset_camera()
	app.update_camera()
	touch(app, 0, center, true)
	app.sound_dialog.popup_centered()
	view = app.camera.global_transform
	drag(app, 0, center + Vector2(50, 0))
	step(app)
	touch(app, 0, center + Vector2(50, 0), false)
	check(view.is_equal_approx(app.camera.global_transform) and app.touch_camera.points.is_empty(), "弹窗打开取消手势并阻止背景相机运动")
	app.sound_dialog.hide()
	await settle(app)
	touch(app, 0, center, true)
	app.get_window().focus_exited.emit()
	touch(app, 0, center, false)
	check(app.touch_camera.points.is_empty() and app.graph.parts.is_empty(), "窗口失焦清理触点且恢复时不补发点击")

	# The hidden-HUD restore button must retain actual touch-to-mouse support.
	app.set_ui_visible(false)
	await settle(app)
	var restore_point: Vector2 = app.restore_ui_button.get_global_rect().get_center()
	touch(app, 0, restore_point, true)
	touch(app, 0, restore_point, false)
	check(app.ui.visible and not app.restore_ui_button.visible, "触摸显示 UI 按钮正常响应")
	app.set_ui_visible(false)
	yaw = app.camera_yaw
	touch(app, 0, center, true)
	drag(app, 0, center + Vector2(40, 0))
	step(app)
	touch(app, 0, center + Vector2(40, 0), false)
	check(app.camera_yaw < yaw, "隐藏 UI 时触屏视角保持可用")
	app.set_ui_visible(true)

	app.empty_scene()
	app.set_mode("terrain")
	app.undo_stack.clear()
	await settle(app)
	app.update_camera()
	var heights = app.terrain.heights.duplicate()
	touch(app, 0, center, true)
	drag(app, 0, center + Vector2(40, 0))
	step(app, 0.6)
	touch(app, 0, center + Vector2(40, 0), false)
	check(app.terrain.heights == heights and app.undo_stack.is_empty() and not app.brush_active, "地形模式直接滑动只旋转，不涂刷")
	touch(app, 0, center, true)
	step(app, 0.5)
	check(app.brush_active and app.undo_stack.size() == 1, "地形长按启动笔刷并记录一次撤销")
	app._process(0.1)
	check(app.terrain.heights != heights, "触屏长按实际修改地形")
	yaw = app.camera_yaw
	drag(app, 0, center + Vector2(30, 0))
	app._process(0.1)
	check(is_equal_approx(app.camera_yaw, yaw) and app.undo_stack.size() == 1, "长按后移动持续涂刷而不旋转或重复记录撤销")
	touch(app, 1, center - Vector2(80, 0), true)
	check(not app.brush_active, "涂刷中加入第二指立即结束笔刷")
	touch(app, 1, center - Vector2(80, 0), false)
	touch(app, 0, center + Vector2(30, 0), false)
	app.undo()
	check(app.terrain.heights == heights, "触屏笔刷可整体撤销")

	# Follow mode must retain the user's newly adjusted relative view.
	app.make_demo()
	app.simulation.paused = true
	app.set_mode("operate")
	app.set_ui_visible(false)
	app.select_train_car(app.simulation.trains[0].id, 1)
	app.set_follow_enabled(true)
	app.set_follow_rotation(true)
	app.update_camera()
	var car: Node3D = app.follow_car_node()
	var relative: Transform3D = car.global_transform.affine_inverse() * app.camera.global_transform
	touch(app, 0, center, true)
	drag(app, 0, center + Vector2(40, 15))
	step(app)
	touch(app, 1, center - Vector2(80, 0), true)
	drag(app, 0, center + Vector2(90, 30))
	drag(app, 1, center - Vector2(100, 0))
	step(app)
	touch(app, 1, center - Vector2(100, 0), false)
	touch(app, 0, center + Vector2(90, 30), false)
	var adjusted: Transform3D = car.global_transform.affine_inverse() * app.camera.global_transform
	car.position += Vector3(1, 0.5, -2)
	car.rotate_y(0.2)
	app.update_camera()
	check(app.follow_train and not adjusted.is_equal_approx(relative) and adjusted.is_equal_approx(car.global_transform.affine_inverse() * app.camera.global_transform), "跟随车辆时触屏旋转平移缩放保留新的相对视角")

	app.set_ui_visible(true)
	app.empty_scene()
	app.set_mode("operate")
	Input.emulate_mouse_from_touch = was_emulating
	app.set_process(was_processing)
	app.set_physics_process(was_physics)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test-results"))
	var report = FileAccess.open("res://test-results/touch-camera.json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks, "failures":failures}, "  "))
	print("TOUCH_CAMERA_RESULT checks=%d failures=%d" % [checks, failures])
	return failures
