extends RefCounted

var checks = 0
var failures = 0
var input = preload("res://tests/train_placement.gd").new()

func check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + message)
	else:
		failures += 1
		push_error("FAIL: " + message)

func run(app, screenshots: bool = false) -> int:
	test_curve_chains(app)
	var original_parent: Node = app.get_parent()
	var viewport = SubViewport.new()
	viewport.size = Vector2i(1600, 1000)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.gui_embed_subwindows = true
	original_parent.add_child(viewport)
	app.reparent(viewport)
	for scale_name in ["HO", "N"]:
		app.graph.scale_name = scale_name
		app.empty_scene()
		app.graph.add_part("core:" + scale_name + ":straight", Vector3(-2, 0.4, 0), 0.6, 0.02)
		var snap = app.graph.endpoint("1:0", 1)
		for kind in ["straight", "curve", "turnout"]:
			app.selected_track = "core:" + scale_name + ":" + kind
			for mirrored in [false, true]:
				app.mirror = mirrored
				app.grade = -0.06 if mirrored else 0.04
				var count = 3 if kind == "turnout" else 2
				var aligned = true
				var connected = true
				var free_anchored = true
				for index in count:
					app.track_placement_endpoint = index
					app.update_track_preview(snap.position, snap)
					var part = app.graph.add_part(app.selected_track, app.placement, app.placement_yaw, app.grade, app.mirror)
					var edge = str(part.uid) + ":" + str(maxi(0, index - 1))
					var actual = app.graph.endpoint(edge, 0 if index == 0 else 1)
					var actual_heading = Vector2(actual.out.x, actual.out.z).normalized()
					var snap_heading = Vector2(snap.out.x, snap.out.z).normalized()
					aligned = aligned and actual.position.distance_to(snap.position) < 0.0001 and actual.out.dot(snap.out) < -0.98 and actual_heading.distance_to(-snap_heading) < 0.00001
					connected = connected and not app.graph.connections[app.graph.endpoint_key(edge, 0 if index == 0 else 1)].is_empty()
					app.graph.remove_part(part.uid)
					app.placement_height = 0.6
					app.yaw = 0.9
					app.update_track_preview(Vector3(1, 0, 2), {})
					var paths = app.graph.make_paths(app.catalog.tracks[app.selected_track], app.placement, app.placement_yaw, app.grade, app.mirror)
					var anchors = RailGraph.placement_endpoints(paths, app.catalog.tracks[app.selected_track], app.placement_yaw, app.grade, app.mirror)
					free_anchored = free_anchored and anchors[index].position.distance_to(Vector3(1, 0.6, 2)) < 0.0001
				check(aligned and connected, "%s %s 镜像=%s 所有端点吸附后位置、朝向、高度匹配并建立连接" % [scale_name, kind, mirrored])
				check(free_anchored, "%s %s 镜像=%s 自由放置按选中端点定位和设置高程" % [scale_name, kind, mirrored])
	app.graph.scale_name = "HO"
	app.empty_scene()
	app.selected_track = "core:HO:turnout"
	app.mirror = false
	app.grade = 0.03
	app.yaw = 0
	app.graph.add_part("core:HO:straight", Vector3(-2.3, 0.5, 0), 0)
	app.rebuild_rails()
	app.camera_target = Vector3(0, 0.5, 0)
	app.camera_distance = 18
	app.camera_yaw = -0.2
	app.camera_pitch = 0.8
	app.update_camera()
	app.set_mode("track")
	for frame in 3:
		await app.get_tree().process_frame
	var endpoint_button: Button
	for child in app.left_body.get_children():
		if child is Button and child.text == "切换端点 Tab":
			endpoint_button = child
	endpoint_button.grab_focus()
	input.motion(app, app.camera.unproject_position(Vector3(0, 0.5, 0)))
	check(app.snapped and app.preview.visible and app.marker.position.is_equal_approx(Vector3(0, 0.6, 0)), "悬浮既有端点显示轨道预览与锚点")
	var first_transform: Transform3D = app.preview.transform
	for index in 3:
		check(app.track_placement_endpoint == index and app.status_label.text.contains(["入口", "直股端", "侧股端"][index]), "道岔 Tab 按入口、直股端、侧股端循环并显示提示")
		if screenshots:
			await input.capture(app, "track-endpoint-%d" % index, true)
		input.key(app, KEY_TAB)
	check(app.track_placement_endpoint == 0 and app.preview.transform.is_equal_approx(first_transform), "Tab 循环后回到原来的预览位置")
	input.key(app, KEY_TAB, true)
	check(app.track_placement_endpoint == 0 and viewport.gui_get_focus_owner() == endpoint_button, "长按 Tab 不连跳端点，按钮焦点不抢走快捷键")
	endpoint_button.pressed.emit()
	input.key(app, KEY_TAB)
	check(app.track_placement_endpoint == 2, "按钮与 Tab 共用端点切换")
	var expected_origin: Vector3 = app.placement
	var expected_yaw: float = app.placement_yaw
	input.click(app)
	check(app.graph.parts.size() == 2 and RailGraph.array_v(app.graph.parts[-1].position).is_equal_approx(expected_origin) and is_equal_approx(app.graph.parts[-1].yaw, expected_yaw), "使用道岔侧股端放置时实际轨道与虚影一致")
	check(app.graph.connections["2:1@1"].size() == 1, "侧股端放置后形成可通行的轨道连接")
	app.undo()
	check(app.graph.parts.size() == 1, "切换端点后的铺轨可撤销")
	app.redo()
	check(app.graph.parts.size() == 2 and app.graph.connections["2:1@1"].size() == 1, "重做保留侧股端连接")
	app.set_mode("track")
	app.selected_track = "core:HO:curve"
	input.key(app, KEY_TAB)
	check(app.track_placement_endpoint == 1, "弯轨 Tab 切换终点")
	input.key(app, KEY_TAB)
	check(app.track_placement_endpoint == 0, "弯轨只有两个放置端点")
	app.erase = true
	input.key(app, KEY_TAB)
	check(app.track_placement_endpoint == 0, "橡皮擦模式不切换端点")
	app.erase = false
	app.show_new_scene()
	input.key(app, KEY_TAB)
	check(app.track_placement_endpoint == 0, "弹窗中的 Tab 保留表单导航")
	app.new_scene_dialog.hide()
	viewport.gui_release_focus()
	app.set_mode("operate")
	input.key(app, KEY_TAB)
	check(app.track_placement_endpoint == 0, "离开铺轨模式后 Tab 不切换轨道端点")
	var report = FileAccess.open("res://test-results/track-placement.json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks, "failures":failures}, "  "))
	print("TRACK_PLACEMENT_RESULT checks=%d failures=%d" % [checks, failures])
	app.reparent(original_parent)
	viewport.queue_free()
	# Flush deferred scene/collision cleanup before the next physics fixture.
	app.empty_scene()
	await app.get_tree().process_frame
	return failures

func test_curve_chains(app) -> void:
	app.empty_scene()
	app.grade = 0.0
	var origin = Vector3(1, 0.2, -1)
	var initial_yaw = 0.37
	var forward = Vector3.RIGHT.rotated(Vector3.UP, initial_yaw)
	for scale_name in ["HO", "N"]:
		app.graph.scale_name = scale_name
		for kind in ["curve", "inner_demo", "wide", "flex_arc"]:
			app.selected_track = "core:" + scale_name + ":" + kind
			app.flex_options = {"radius_mm":375.0, "angle_deg":30.0} if kind == "flex_arc" else {}
			var definition: Dictionary = app.catalog.tracks[app.selected_track]
			var angle: float = app.flex_options.get("angle_deg", definition.angle_deg)
			var radius: float = app.flex_options.get("radius_mm", definition.radius_mm) / 100.0
			var half_count = roundi(180.0 / angle)
			for mirrored in [false, true]:
				app.mirror = mirrored
				for anchor in [0, 1]:
					app.track_placement_endpoint = anchor
					app.graph.parts.clear()
					app.graph.next_uid = 1
					app.graph.rebuild()
					var snap = {"position":origin, "out":forward}
					var turn_sign = (-1.0 if mirrored else 1.0) * (1.0 if anchor == 0 else -1.0)
					var label = "%s %s 镜像=%s 锚点=%d" % [scale_name, kind, mirrored, anchor]
					for i in range(half_count * 2):
						app.update_track_preview(snap.position, snap)
						var part = app.graph.add_part(app.selected_track, app.placement, app.placement_yaw, 0, mirrored, app.flex_options)
						snap = app.graph.endpoint(str(part.uid) + ":0", 1 - anchor)
						if i + 1 == half_count:
							var expected = origin + Vector3(0, 0, 2.0 * radius * turn_sign).rotated(Vector3.UP, initial_yaw)
							var heading_error = rad_to_deg(atan2(snap.out.z, snap.out.x) - atan2(-forward.z, -forward.x))
							print("CURVE_HALF %s heading_error_deg=%.6f position_error_mm=%.6f" % [label, wrapf(heading_error, -180, 180), snap.position.distance_to(expected) * 100])
							check(snap.position.distance_to(expected) < 0.0001 and snap.out.distance_to(-forward) < 0.00001, "%s：%d 段精确组成 180° 半圆，端点相距两倍半径" % [label, half_count])
					check(snap.position.distance_to(origin) < 0.0001 and snap.out.distance_to(forward) < 0.00001 and app.graph.open_end_count() == 0, "%s：%d 段闭合成圆且所有接缝可通行" % [label, half_count * 2])
					app.graph.parts = JSON.parse_string(JSON.stringify(app.graph.parts))
					app.graph.rebuild()
					check(app.graph.open_end_count() == 0, "%s：保存数据往返后仍然闭合" % label)
	app.flex_options = {}
