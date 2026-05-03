extends CanvasLayer

const MARKER := "UI-DIAG"
const BUILD_ID := "2026-05-03-device-debug"
const LABEL_NAME := "BuildDiagnosticsLabel"

var _last_scene: Node = null
var _logged_scene_ids := {}


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().node_added.connect(_on_node_added)
	call_deferred("_refresh")


func _process(_delta: float) -> void:
	var scene := get_tree().current_scene
	if scene != _last_scene:
		_refresh()


func _on_node_added(node: Node) -> void:
	if _is_scene_root(node):
		call_deferred("_refresh")


func _refresh() -> void:
	var scene := get_tree().current_scene
	if scene != null:
		_last_scene = scene
	_attach_scene_diagnostics(get_tree().root)


func _attach_scene_diagnostics(node: Node) -> void:
	if _is_scene_root(node):
		_attach_label(node)
		_log_scene_once(node)
	for child in node.get_children():
		_attach_scene_diagnostics(child)


func _is_scene_root(node: Node) -> bool:
	return node is Control and node.scene_file_path != "" and (node == get_tree().current_scene or node.get_parent() is Viewport)


func _attach_label(scene: Node) -> void:
	if not scene is Control:
		return
	var label := scene.get_node_or_null(LABEL_NAME) as Label
	if label == null:
		label = Label.new()
		label.name = LABEL_NAME
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.z_index = 4096
		label.add_theme_font_size_override("font_size", 10)
		label.modulate = Color(1.0, 1.0, 0.0, 0.78)
		(scene as Control).add_child(label)
	label.text = _diagnostic_text(scene)
	label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	label.offset_left = -360.0
	label.offset_top = -36.0
	label.offset_right = -4.0
	label.offset_bottom = -6.0
	label.custom_minimum_size = Vector2(0.0, 12.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


func _diagnostic_text(scene: Node) -> String:
	var size := _scene_viewport_size(scene)
	return "%s %s %s %dx%d" % [MARKER, BUILD_ID, _scene_name(scene), int(size.x), int(size.y)]


func _scene_name(scene: Node) -> String:
	var file := scene.scene_file_path.get_file().get_basename()
	match file:
		"main_menu":
			return "MainMenu"
		"local_setup":
			return "LocalSetup"
		"ai_setup":
			return "AiSetup"
		"ai_lab":
			return "AiLab"
		"game":
			return "Game"
		"replay":
			return "Replay"
		"lobby":
			return "Lobby"
		_:
			return scene.name


func _log_scene_once(scene: Node) -> void:
	var id := scene.get_instance_id()
	if _logged_scene_ids.has(id):
		return
	_logged_scene_ids[id] = true
	var size := _scene_viewport_size(scene)
	var text := _diagnostic_text(scene)
	if has_node("/root/Log"):
		Log.info("UI-DIAG", "%s scene_path=%s orientation=%s" % [text, scene.scene_file_path, _orientation_text(size)])
	else:
		print("[UI-DIAG] %s scene_path=%s orientation=%s" % [text, scene.scene_file_path, _orientation_text(size)])


func _scene_viewport_size(scene: Node) -> Vector2:
	var viewport := scene.get_viewport()
	if viewport != null:
		return viewport.get_visible_rect().size
	return get_viewport().get_visible_rect().size


func _orientation_text(size: Vector2) -> String:
	return "portrait" if size.y >= size.x else "landscape"
