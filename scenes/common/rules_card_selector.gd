extends VBoxContainer

signal selection_changed(forbidden_enabled: bool)

@export var forbidden_enabled: bool = true

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
	if forbidden_enabled == enabled:
		_update_cards()
		return
	forbidden_enabled = enabled
	_update_cards()
	selection_changed.emit(forbidden_enabled)


func set_disabled(disabled: bool) -> void:
	free_card.disabled = disabled
	forbidden_card.disabled = disabled


func _select_free() -> void:
	set_forbidden_enabled(false)


func _select_forbidden() -> void:
	set_forbidden_enabled(true)


func _update_cards() -> void:
	free_title.text = "自由五子棋"
	free_description.text = "双方自由落子"
	forbidden_title.text = "禁手规则"
	forbidden_description.text = "黑棋禁手不可落子"
	free_card.text = "✓ 自由五子棋" if not forbidden_enabled else "自由五子棋"
	forbidden_card.text = "✓ 禁手规则" if forbidden_enabled else "禁手规则"
	free_card.modulate = Color(1.0, 0.88, 0.62, 1.0) if not forbidden_enabled else Color(0.78, 0.68, 0.56, 1.0)
	forbidden_card.modulate = Color(1.0, 0.88, 0.62, 1.0) if forbidden_enabled else Color(0.78, 0.68, 0.56, 1.0)
