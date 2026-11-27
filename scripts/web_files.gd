extends Node
## Browser-only file I/O. Desktop keeps the native FileDialog and save_layout.

var app: Node
var bridge: JavaScriptObject
var import_callback: JavaScriptObject

func setup(owner_app: Node) -> void:
	app = owner_app
	bridge = JavaScriptBridge.get_interface("TrackPlaygroundFiles")
	if bridge == null:
		app.toast("网页文件接口未加载，请检查 scene-files.js 是否存在。", 10)
		return
	# Keep the callback alive for the entire browser session.
	import_callback = JavaScriptBridge.create_callback(_receive_text)
	bridge.register(import_callback)

func open() -> void:
	if bridge != null:
		bridge.open()

func download() -> void:
	JavaScriptBridge.download_buffer(JSON.stringify(app.snapshot()).to_utf8_buffer(), "我的铁路.railway", "application/json")
	app.toast("已请求下载场景文件，请在浏览器下载列表中查看。", 7)
	app.sound.play_effect("confirm")

func _receive_text(arguments: Array) -> void:
	if arguments.size() == 1 and arguments[0] is String:
		# Leave the JavaScript callback before rebuilding the Godot scene.
		call_deferred("_load_text", arguments[0])

func _load_text(text: String) -> void:
	var success: bool = app.load_layout_text(text)
	bridge.complete(success, app.toast_label.text)
