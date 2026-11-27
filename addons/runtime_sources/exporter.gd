@tool
extends EditorExportPlugin

func _get_name() -> String:
	return "TrackPlaygroundRuntimeSources"

func _export_file(path: String, _type: String, _features: PackedStringArray) -> void:
	# include_filter alone does not keep originals of imported resources.
	# audio.gd reads PCM bytes; geometry.gd parses Mod GLB files at runtime.
	if (path.begins_with("res://assets/audio/") and path.ends_with(".wav")) or (path.begins_with("res://mods/") and path.ends_with(".glb")):
		add_file(path, FileAccess.get_file_as_bytes(path), false)
