extends VBoxContainer

signal selection_changed(forbidden_enabled: bool)

var _forbidden_enabled: bool = true

@export var forbidden_enabled: bool = true:
	set(value):
		_apply_forbidden_enabled(value, false)
	get:
		return _forbidden_enabled

@onready var free_card: Button = %FreeCard
@onready var forbidden_card: Button = %ForbiddenCard
@onready var free_title: Label = %FreeTitle
@onready var free_description: Label = %FreeDescription
@onready var forbidden_title: Label = %ForbiddenTitle
@onready var forbidden_description: Label = %ForbiddenDescription


func _ready() -> void:
	free_card.pressed.connect(_select_free)
	forbidden_card.pressed.connect(_select_forbidden)
	_update_cards()


func set_forbidden_enabled(enabled: bool) -> void:
	_apply_forbidden_enabled(enabled, true)


func set_disabled(disabled: bool) -> void:
	free_card.disabled = disabled
	forbidden_card.disabled = disabled


func _apply_forbidden_enabled(enabled: bool, emit_changed: bool) -> void:
	var changed := _forbidden_enabled != enabled
	_forbidden_enabled = enabled
	if is_node_ready():
		_update_cards()
	if changed and emit_changed:
		selection_changed.emit(_forbidden_enabled)


func _select_free() -> void:
	set_forbidden_enabled(false)


func _select_forbidden() -> void:
	set_forbidden_enabled(true)


func _update_cards() -> void:
	free_card.text = ""
	forbidden_card.text = ""
	free_title.text = "✓ 自由五子棋" if not _forbidden_enabled else "自由五子棋"
	free_description.text = "双方自由落子"
	forbidden_title.text = "✓ 禁手规则" if _forbidden_enabled else "禁手规则"
	forbidden_description.text = "黑棋禁手不可落子"
	free_card.modulate = Color(1.0, 0.88, 0.62, 1.0) if not _forbidden_enabled else Color(0.78, 0.68, 0.56, 1.0)
	forbidden_card.modulate = Color(1.0, 0.88, 0.62, 1.0) if _forbidden_enabled else Color(0.78, 0.68, 0.56, 1.0)
