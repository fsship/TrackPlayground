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

func transform_error(a: Transform3D, b: Transform3D) -> float:
	return maxf(a.origin.distance_to(b.origin), maxf(a.basis.x.distance_to(b.basis.x), maxf(a.basis.y.distance_to(b.basis.y), a.basis.z.distance_to(b.basis.z))))

func advance(app, steps: int) -> void:
	for i in steps:
		app.simulation.tick(1.0 / 30.0)
	app.update_train_visuals()
	app.update_camera()

func run(app, capture: bool = false) -> int:
	app.empty_scene()
	check(app.follow_button.disabled and app.follow_car_picker.disabled, "空场景禁用跟随与车辆选择")
	app.set_follow_enabled(true)
	check(not app.follow_train and not app.follow_button.button_pressed, "没有车辆时不能开启跟随")
	for scale_name in ["HO", "N"]:
		app.graph.scale_name = scale_name
		app.make_demo()
		var train = app.simulation.trains[0]
		app.select_train_car(train.id, 2)
		app.set_follow_rotation(false)
		app.follow_button.button_pressed = true
		var car: Node3D = app.train_nodes[train.id][2]
		check(app.follow_car_picker.item_count == 3 and app.follow_car_picker.selected == 2, "%s 下拉框按顺序列出全部车辆，可选末辆" % scale_name)
		check(app.camera_target.distance_to(car.global_position) < 0.0001 and app.camera_target.distance_to(app.train_nodes[train.id][0].global_position) > 1.0, "%s 跟随目标确为所选车厢而非车头" % scale_name)
		app.pan_camera(Vector2(28, -19))
		app.update_camera()
		var offset: Vector3 = app.camera.global_position - car.global_position
		var basis: Basis = app.camera.global_basis
		var target_offset: Vector3 = app.camera_target - car.global_position
		advance(app, 1500)
		check(app.follow_train and app.follow_button.button_pressed and not target_offset.is_zero_approx(), "%s 手动平移保留跟随状态与偏移" % scale_name)
		check((app.camera.global_position - car.global_position).distance_to(offset) < 0.001 and app.camera.global_basis.is_equal_approx(basis), "%s 普通跟随保持世界方向和移动后的偏移" % scale_name)
		var before: Transform3D = app.camera.global_transform
		app.follow_rotation_button.button_pressed = true
		app.update_camera()
		check(transform_error(before, app.camera.global_transform) < 0.001, "%s 开启相对朝向锁定不跳动" % scale_name)
		var relative: Transform3D = car.global_transform.affine_inverse() * app.camera.global_transform
		var start_basis = car.global_basis
		var largest_error = 0.0
		var largest_turn = 0.0
		for frame in 80:
			advance(app, 30)
			largest_error = maxf(largest_error, transform_error(relative, car.global_transform.affine_inverse() * app.camera.global_transform))
			largest_turn = maxf(largest_turn, start_basis.x.distance_to(car.global_basis.x))
		check(largest_turn > 0.5 and largest_error < 0.001 and not train.fault, "%s 连续过弯时相机相对车厢的位置和三轴朝向固定" % scale_name)
		app.pan_camera(Vector2(-17, 24))
		app.camera_yaw += 0.3
		app.camera_pitch = 0.5
		app.camera_distance *= 0.9
		app.update_camera()
		var adjusted: Transform3D = car.global_transform.affine_inverse() * app.camera.global_transform
		advance(app, 900)
		check(app.follow_train and transform_error(relative, adjusted) > 0.1 and transform_error(adjusted, car.global_transform.affine_inverse() * app.camera.global_transform) < 0.001, "%s 平移旋转缩放后持续保持新的相对视角" % scale_name)
		train.velocity = 0
		train.target = 0
		check(app.simulation.reverse(train), "%s 跟随目标可停车换向" % scale_name)
		train.target = 15
		advance(app, 600)
		check(app.follow_car_index == 2 and transform_error(adjusted, car.global_transform.affine_inverse() * app.camera.global_transform) < 0.001, "%s 倒车仍锁定原车厢与相对视角" % scale_name)
		before = app.camera.global_transform
		app.follow_rotation_button.button_pressed = false
		app.update_camera()
		check(transform_error(before, app.camera.global_transform) < 0.001 and app.follow_train, "%s 关闭朝向锁定保持当前画面并继续跟随" % scale_name)
		app.follow_car_picker.item_selected.emit(1)
		check(app.follow_car_index == 1 and app.camera_target.distance_to(app.train_nodes[train.id][1].global_position) < 0.001, "%s 下拉框可切换具体车厢" % scale_name)
		app.select_train_car(app.simulation.trains[1].id, 0)
		check(app.follow_train and app.follow_bound_train == app.selected_train and app.follow_car_picker.selected == 0, "%s 切换列车更新跟随目标和车辆选项" % scale_name)

	# Full body attitude, including pitch and roll, must come from the rendered
	# car transform rather than a track tangent or direction-of-travel sign.
	app.set_follow_rotation(true)
	var car = app.follow_car_node()
	var relative: Transform3D = car.global_transform.affine_inverse() * app.camera.global_transform
	car.global_transform = Transform3D(Basis.from_euler(Vector3(0.32, -1.2, 0.48)), Vector3(4, 2, -3))
	app.update_camera()
	check(transform_error(relative, car.global_transform.affine_inverse() * app.camera.global_transform) < 0.001, "坡度、侧倾及脱轨车体姿态均保持完整相对变换")
	app.simulation.paused = true
	var saved_view: Transform3D = app.camera.global_transform
	var saved = app.snapshot()
	check(app.validate_snapshot(saved).is_empty(), "倾斜跟随视角可保存为合法场景")
	check(app.apply_snapshot(JSON.parse_string(JSON.stringify(saved))), "跟随视角场景可重新加载")
	app.update_camera()
	check(transform_error(saved_view, app.camera.global_transform) < 0.001 and not app.follow_train and not app.follow_button.button_pressed, "加载保持保存时的画面并同步退出跟随")
	for i in app.simulation.trains.size():
		var loaded_train: Dictionary = app.simulation.trains[i]
		check(loaded_train.id is int and app.train_nodes.has(int(loaded_train.id)), "JSON 载入后列车与车体索引统一使用整数 ID")
		app.train_buttons.get_child(i).pressed.emit()
		app.follow_button.button_pressed = true
		app.update_camera()
		check(app.follow_train and app.follow_button.button_pressed and app.follow_car_node() != null and app.follow_bound_train == loaded_train.id, "载入存档后从列表选择列车仍能打开跟随开关")
		app.select_train_car(loaded_train.id, loaded_train.cars.size() - 1)
		app.set_follow_rotation(true)
		check(app.follow_car_node() == app.train_nodes[loaded_train.id][-1] and app.follow_train, "载入存档后选中具体车厢仍保持跟随")
		app.follow_button.button_pressed = false
	var legacy = saved.duplicate(true)
	legacy.camera.erase("orbit_rotation")
	check(app.apply_snapshot(legacy) and app.camera_orbit_basis.is_equal_approx(Basis.IDENTITY), "旧场景默认使用世界坐标相机")
	for invalid in [[0, 0, 0, 0], [1, 1, 1, 1], [0, 0], ["x", 0, 0, 1]]:
		var bad = saved.duplicate(true)
		bad.camera.orbit_rotation = invalid
		check(not app.apply_snapshot(bad), "拒绝非法相机旋转 " + str(invalid))
	var train = app.current_train()
	app.select_train_car(train.id, 2)
	app.set_follow_enabled(true)
	train.velocity = 0
	train.target = 0
	check(app.simulation.reconfigure(train, [train.cars[0]]), "停车后缩短被跟随的编组")
	app.rebuild_trains()
	app.refresh_train_list()
	app.update_camera()
	check(app.follow_train and app.follow_car_index == 0 and app.follow_car_picker.item_count == 1, "移除末辆后回退到有效车辆，无越界或旧目标")
	app.simulation.remove_train(train.id)
	app.update_camera()
	check(not app.follow_train and not app.follow_button.button_pressed, "移除被跟随编组后安全退出并同步开关")
	app.select_train_car(app.simulation.trains[0].id)
	app.set_follow_enabled(true)
	app.reset_camera()
	check(not app.follow_train and not app.follow_button.button_pressed and app.camera_orbit_basis.is_equal_approx(Basis.IDENTITY), "全景明确退出跟随并恢复世界坐标")
	app.set_follow_enabled(true)
	app.empty_scene()
	check(not app.follow_train and app.follow_button.disabled and app.follow_car_picker.disabled, "新建场景清除跟随状态与车辆选项")
	if capture:
		app.graph.scale_name = "HO"
		app.make_demo()
		app.simulation.paused = true
		app.select_train_car(app.simulation.trains[0].id, 1)
		app.set_follow_enabled(true)
		app.set_follow_rotation(true)
		app.camera_distance = 12
		app.update_camera()
		app.update_ui()
		for frame in 5:
			await app.get_tree().process_frame
		await RenderingServer.frame_post_draw
		app.get_viewport().get_texture().get_image().save_png("res://screenshots/camera-follow.png")
	var report = FileAccess.open("res://test-results/camera-follow.json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks, "failures":failures}, "  "))
	print("CAMERA_FOLLOW_RESULT checks=%d failures=%d" % [checks, failures])
	return failures
