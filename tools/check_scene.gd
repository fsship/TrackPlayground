extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var app = load("res://main.tscn").instantiate()
	root.add_child(app)
	var args = OS.get_cmdline_user_args()
	var path = args[0] if not args.is_empty() else "res://test-results/roundtrip.railway"
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		print("Invalid JSON")
		quit(1)
		return
	print("VALIDATION: ", app.validate_snapshot(data))
	var loaded = app.apply_snapshot(data)
	print("LOAD: ", loaded, " MESSAGE: ", app.toast_label.text)
	quit(0 if loaded else 1)
