extends Node

const DIAG_MARKER := "UI-DIAG"
const VIEWPORT_SIZE := Vector2i(430, 932)
const SCENES := {
	"MainMenu": "res://scenes/main_menu/main_menu.tscn",
	"LocalSetup": "res://scenes/local_setup/local_setup.tscn",
	"AiSetup": "res://scenes/ai_setup/ai_setup.tscn",
	"AiLab": "res://scenes/ai_lab/ai_lab.tscn",
	"Game": "res://scenes/game/game.tscn",
}

var _failed := false


func _ready() -> void:
	GameManager.setup_local_pvp(true)
	for scene_name in SCENES.keys():
		await _assert_scene_has_diagnostics(scene_name, SCENES[scene_name])
	if _failed:
		get_tree().quit(1)
	else:
		print("UI_DIAGNOSTICS_TASK_TESTS PASS")
		get_tree().quit(0)


func _assert_scene_has_diagnostics(scene_name: String, scene_path: String) -> void:
	var viewport := SubViewport.new()
	viewport.size = VIEWPORT_SIZE
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	var packed_scene := load(scene_path) as PackedScene
	if not _expect(packed_scene != null, "%s should load" % scene_path):
		viewport.queue_free()
		return
	var scene := packed_scene.instantiate()
	viewport.add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	var marker := _find_diag_label(scene)
	if _expect(marker != null, "%s should have UI diagnostics label" % scene_name):
		_expect(marker.text.contains(DIAG_MARKER), "%s diagnostics should include marker text: %s" % [scene_name, marker.text])
		_expect(marker.text.contains(scene_name), "%s diagnostics should include scene name: %s" % [scene_name, marker.text])
		_expect(marker.text.contains("430x932"), "%s diagnostics should include viewport size: %s" % [scene_name, marker.text])
		_expect(marker.mouse_filter == Control.MOUSE_FILTER_IGNORE, "%s diagnostics should ignore mouse input" % scene_name)
		_expect(marker.get_global_rect().position.x >= 0.0, "%s diagnostics should be visible horizontally" % scene_name)
		_expect(marker.get_global_rect().position.y >= 0.0, "%s diagnostics should be visible vertically" % scene_name)

	viewport.queue_free()


func _find_diag_label(root: Node) -> Label:
	if root is Label and root.name == "BuildDiagnosticsLabel":
		return root as Label
	for child in root.get_children():
		var found := _find_diag_label(child)
		if found != null:
			return found
	return null


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	_failed = true
	push_error(message)
	return false
