extends SceneTree

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://runtime"))
	var license_file = FileAccess.open("res://runtime/GODOT_LICENSE.txt", FileAccess.WRITE)
	license_file.store_string(Engine.get_license_text())
	license_file.close()
	var third_party = FileAccess.open("res://runtime/THIRD_PARTY_NOTICES.json", FileAccess.WRITE)
	third_party.store_string(JSON.stringify({"copyright":Engine.get_copyright_info(),"licenses":Engine.get_license_info()}, "  "))
	third_party.close()
	print("Runtime license notices extracted from the bundled engine.")
	quit()
