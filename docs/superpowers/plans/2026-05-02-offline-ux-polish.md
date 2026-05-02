# Offline UX Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Polish the offline setup UX after target-device validation by using Chinese-only rules copy, unified card selectors defaulting to `禁手规则`, and iPhone portrait gameplay.

**Architecture:** Add a small reusable `RulesCardSelector` scene/script for offline setup screens. Replace the local PvP, human-vs-AI, and AI Lab rules checkbox/button implementations with this selector, then adjust game HUD copy and iOS orientation/export settings.

**Tech Stack:** Godot 4.2 GDScript and `.tscn` scenes, existing `GameManager` setup APIs, existing CJK font subset tooling.

---

## File Structure

- Create `scenes/common/rules_card_selector.gd` — reusable two-card selector with `forbidden_enabled`, `set_disabled()`, and `selection_changed`.
- Create `scenes/common/rules_card_selector.tscn` — card-style UI for `自由五子棋` and `禁手规则` with one-line descriptions.
- Modify `scenes/local_setup/local_setup.tscn` — polished local setup panel, replacing plain rule buttons with `RulesCardSelector`.
- Modify `scenes/local_setup/local_setup.gd` — default to `禁手规则` through the selector and start local PvP with selector state.
- Modify `scenes/ai_setup/ai_setup.tscn` — replace `RenjuCheckBox` with `RulesCardSelector`.
- Modify `scenes/ai_setup/ai_setup.gd` — read selector state instead of checkbox state.
- Modify `scenes/ai_lab/ai_lab.tscn` — replace `RenjuCheckBox` with compact `RulesCardSelector` placement.
- Modify `scenes/ai_lab/ai_lab.gd` — read selector state, disable it during batches, and default to `禁手规则`.
- Modify `scenes/game/game.gd` — make rules suffix Chinese-only.
- Modify `scenes/game/game.tscn` / `scenes/game/game.gd` if needed — ensure narrow portrait viewports use vertical layout independent of OS name.
- Modify `export_presets.cfg` — set iOS orientation options so iPhone uses portrait; exact keys must match Godot export preset behavior.
- Modify `assets/fonts/cjk_subset.otf` and `assets/fonts/cjk_subset_chars.txt` if the font coverage check requires regeneration.

---

### Task 1: Add reusable rules card selector

**Files:**
- Create: `scenes/common/rules_card_selector.gd`
- Create: `scenes/common/rules_card_selector.tscn`
- Test: `tools/test_rules_card_selector_task1.gd`
- Test: `tools/test_rules_card_selector_task1.tscn`

- [ ] **Step 1: Write the failing selector test**

Create `tools/test_rules_card_selector_task1.gd`:

```gdscript
extends SceneTree

func _init() -> void:
	var selector_scene: PackedScene = load("res://scenes/common/rules_card_selector.tscn")
	assert(selector_scene != null)
	var selector = selector_scene.instantiate()
	root.add_child(selector)
	await process_frame

	assert(selector.forbidden_enabled == true)
	assert(selector.has_signal("selection_changed"))
	assert(selector.get_node("%FreeTitle").text == "自由五子棋")
	assert(selector.get_node("%FreeDescription").text == "双方自由落子")
	assert(selector.get_node("%ForbiddenTitle").text == "禁手规则")
	assert(selector.get_node("%ForbiddenDescription").text == "黑棋禁手不可落子")

	var changed: Array[bool] = []
	selector.selection_changed.connect(func(enabled: bool) -> void:
		changed.append(enabled)
	)
	selector.get_node("%FreeCard").pressed.emit()
	await process_frame
	assert(selector.forbidden_enabled == false)
	assert(changed == [false])

	selector.set_disabled(true)
	assert(selector.get_node("%FreeCard").disabled == true)
	assert(selector.get_node("%ForbiddenCard").disabled == true)
	selector.set_disabled(false)
	assert(selector.get_node("%FreeCard").disabled == false)
	assert(selector.get_node("%ForbiddenCard").disabled == false)

	print("RULES_CARD_SELECTOR_TASK1_TESTS PASS")
	quit()
```

Create `tools/test_rules_card_selector_task1.tscn`:

```ini
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://tools/test_rules_card_selector_task1.gd" id="1"]

[node name="TestRulesCardSelectorTask1" type="Node"]
script = ExtResource("1")
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
godot --headless --path . res://tools/test_rules_card_selector_task1.tscn
```

Expected: FAIL because `res://scenes/common/rules_card_selector.tscn` does not exist.

- [ ] **Step 3: Create the selector script**

Create `scenes/common/rules_card_selector.gd`:

```gdscript
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
```

- [ ] **Step 4: Create the selector scene**

Create `scenes/common/rules_card_selector.tscn`:

```ini
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scenes/common/rules_card_selector.gd" id="1"]

[node name="RulesCardSelector" type="VBoxContainer"]
custom_minimum_size = Vector2(0, 132)
theme_override_constants/separation = 10
script = ExtResource("1")
forbidden_enabled = true

[node name="FreeCard" type="Button" parent="."]
unique_name_in_owner = true
custom_minimum_size = Vector2(0, 58)
layout_mode = 2
theme_override_font_sizes/font_size = 18
text = "自由五子棋"
alignment = 0

[node name="FreeLabels" type="VBoxContainer" parent="FreeCard"]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
offset_left = 18.0
offset_top = 8.0
offset_right = -18.0
offset_bottom = -8.0
grow_horizontal = 2
grow_vertical = 2
theme_override_constants/separation = 2
mouse_filter = 2

[node name="FreeTitle" type="Label" parent="FreeCard/FreeLabels"]
unique_name_in_owner = true
layout_mode = 2
theme_override_font_sizes/font_size = 18
text = "自由五子棋"

[node name="FreeDescription" type="Label" parent="FreeCard/FreeLabels"]
unique_name_in_owner = true
layout_mode = 2
theme_override_font_sizes/font_size = 13
theme_override_colors/font_color = Color(0.78, 0.68, 0.56, 1)
text = "双方自由落子"

[node name="ForbiddenCard" type="Button" parent="."]
unique_name_in_owner = true
custom_minimum_size = Vector2(0, 58)
layout_mode = 2
theme_override_font_sizes/font_size = 18
text = "禁手规则"
alignment = 0

[node name="ForbiddenLabels" type="VBoxContainer" parent="ForbiddenCard"]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
offset_left = 18.0
offset_top = 8.0
offset_right = -18.0
offset_bottom = -8.0
grow_horizontal = 2
grow_vertical = 2
theme_override_constants/separation = 2
mouse_filter = 2

[node name="ForbiddenTitle" type="Label" parent="ForbiddenCard/ForbiddenLabels"]
unique_name_in_owner = true
layout_mode = 2
theme_override_font_sizes/font_size = 18
text = "禁手规则"

[node name="ForbiddenDescription" type="Label" parent="ForbiddenCard/ForbiddenLabels"]
unique_name_in_owner = true
layout_mode = 2
theme_override_font_sizes/font_size = 13
theme_override_colors/font_color = Color(0.78, 0.68, 0.56, 1)
text = "黑棋禁手不可落子"
```

- [ ] **Step 5: Run the selector test and parse check**

Run:

```bash
godot --headless --path . res://tools/test_rules_card_selector_task1.tscn
godot --headless --path . --quit
```

Expected: `RULES_CARD_SELECTOR_TASK1_TESTS PASS`; parse check exits 0 with the known Linux `gomoku_neural` GDExtension warning.

- [ ] **Step 6: Commit Task 1**

Run:

```bash
git add scenes/common/rules_card_selector.gd scenes/common/rules_card_selector.tscn tools/test_rules_card_selector_task1.gd tools/test_rules_card_selector_task1.tscn
git commit -m "ui: add offline rules card selector"
```

---

### Task 2: Apply card selector to local PvP and human-vs-AI setup

**Files:**
- Modify: `scenes/local_setup/local_setup.tscn`
- Modify: `scenes/local_setup/local_setup.gd`
- Modify: `scenes/ai_setup/ai_setup.tscn`
- Modify: `scenes/ai_setup/ai_setup.gd`
- Test: `tools/test_setup_rules_task2.gd`
- Test: `tools/test_setup_rules_task2.tscn`

- [ ] **Step 1: Write setup default tests**

Create `tools/test_setup_rules_task2.gd`:

```gdscript
extends SceneTree

func _init() -> void:
	var local_scene: PackedScene = load("res://scenes/local_setup/local_setup.tscn")
	assert(local_scene != null)
	var local_setup = local_scene.instantiate()
	root.add_child(local_setup)
	await process_frame
	assert(local_setup.get_node("%RulesSelector").forbidden_enabled == true)
	assert(local_setup.get_node("%TitleLabel").text == "本地双人")
	assert(local_setup.get_node("%SubtitleLabel").text == "选择规则后开始对局")

	var ai_scene: PackedScene = load("res://scenes/ai_setup/ai_setup.tscn")
	assert(ai_scene != null)
	var ai_setup = ai_scene.instantiate()
	root.add_child(ai_setup)
	await process_frame
	assert(ai_setup.get_node("%RulesSelector").forbidden_enabled == true)
	assert(ai_setup.has_node("%RenjuCheckBox") == false)

	print("SETUP_RULES_TASK2_TESTS PASS")
	quit()
```

Create `tools/test_setup_rules_task2.tscn`:

```ini
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://tools/test_setup_rules_task2.gd" id="1"]

[node name="TestSetupRulesTask2" type="Node"]
script = ExtResource("1")
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
godot --headless --path . res://tools/test_setup_rules_task2.tscn
```

Expected: FAIL because `RulesSelector` is not present in local/AI setup scenes.

- [ ] **Step 3: Update local setup scene**

Modify `scenes/local_setup/local_setup.tscn`:

- Add external resource:

```ini
[ext_resource type="PackedScene" path="res://scenes/common/rules_card_selector.tscn" id="2"]
```

- Change `load_steps=2` to `load_steps=3`.
- Replace `RulesLabel`, `FreeButton`, and `RenjuButton` with:

```ini
[node name="SubtitleLabel" type="Label" parent="VBoxContainer"]
unique_name_in_owner = true
layout_mode = 2
theme_override_font_sizes/font_size = 16
theme_override_colors/font_color = Color(0.78, 0.68, 0.56, 1)
text = "选择规则后开始对局"
horizontal_alignment = 1

[node name="RulesSelector" parent="VBoxContainer" instance=ExtResource("2")]
unique_name_in_owner = true
layout_mode = 2
```

- Increase the setup panel height by changing `offset_top` from `-170.0` to `-210.0` and `offset_bottom` from `170.0` to `210.0`.
- Keep `StartButton` text `开始对局` and `BackButton` text `返回菜单`.

- [ ] **Step 4: Update local setup script**

Modify `scenes/local_setup/local_setup.gd` to:

```gdscript
extends Control

@onready var rules_selector = %RulesSelector
@onready var start_button: Button = %StartButton


func _ready() -> void:
	start_button.pressed.connect(_on_start_pressed)
	%BackButton.pressed.connect(_on_back_pressed)


func _on_start_pressed() -> void:
	GameManager.setup_local_pvp(rules_selector.forbidden_enabled)
	get_tree().change_scene_to_file("res://scenes/game/game.tscn")


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")
```

- [ ] **Step 5: Update AI setup scene**

Modify `scenes/ai_setup/ai_setup.tscn`:

- Add external resource:

```ini
[ext_resource type="PackedScene" path="res://scenes/common/rules_card_selector.tscn" id="2"]
```

- Change `load_steps=2` to `load_steps=3`.
- Replace the `RenjuCheckBox` node with:

```ini
[node name="RulesSelector" parent="VBoxContainer" instance=ExtResource("2")]
unique_name_in_owner = true
layout_mode = 2
```

- [ ] **Step 6: Update AI setup script**

Modify `scenes/ai_setup/ai_setup.gd`:

- Replace:

```gdscript
@onready var renju_checkbox: CheckBox = %RenjuCheckBox
```

with:

```gdscript
@onready var rules_selector = %RulesSelector
```

- Replace `_on_start()` with:

```gdscript
func _on_start() -> void:
	var engine = _create_engine()
	GameManager.setup_vs_ai(selected_color, engine, rules_selector.forbidden_enabled)
	get_tree().change_scene_to_file("res://scenes/game/game.tscn")
```

- [ ] **Step 7: Run tests and parse check**

Run:

```bash
godot --headless --path . res://tools/test_setup_rules_task2.tscn
godot --headless --path . res://tools/test_rules_card_selector_task1.tscn
godot --headless --path . --quit
```

Expected: both focused tests pass; parse check exits 0 with known Linux GDExtension warning.

- [ ] **Step 8: Commit Task 2**

Run:

```bash
git add scenes/local_setup/local_setup.tscn scenes/local_setup/local_setup.gd scenes/ai_setup/ai_setup.tscn scenes/ai_setup/ai_setup.gd tools/test_setup_rules_task2.gd tools/test_setup_rules_task2.tscn
git commit -m "ui: unify setup rules selectors"
```

---

### Task 3: Apply card selector to AI Lab and rules copy

**Files:**
- Modify: `scenes/ai_lab/ai_lab.tscn`
- Modify: `scenes/ai_lab/ai_lab.gd`
- Modify: `scenes/game/game.gd`
- Test: `tools/test_ai_lab_rules_task3.gd`
- Test: `tools/test_ai_lab_rules_task3.tscn`

- [ ] **Step 1: Write AI Lab and HUD copy test**

Create `tools/test_ai_lab_rules_task3.gd`:

```gdscript
extends SceneTree

func _init() -> void:
	var lab_scene: PackedScene = load("res://scenes/ai_lab/ai_lab.tscn")
	assert(lab_scene != null)
	var lab = lab_scene.instantiate()
	root.add_child(lab)
	await process_frame
	assert(lab.get_node("%RulesSelector").forbidden_enabled == true)
	assert(lab.has_node("%RenjuCheckBox") == false)

	var game_script = load("res://scenes/game/game.gd")
	var game = game_script.new()
	GameManager.forbidden_enabled = true
	assert(game._ruleset_suffix() == "（禁手规则）")
	GameManager.forbidden_enabled = false
	assert(game._ruleset_suffix() == "（自由五子棋）")

	print("AI_LAB_RULES_TASK3_TESTS PASS")
	quit()
```

Create `tools/test_ai_lab_rules_task3.tscn`:

```ini
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://tools/test_ai_lab_rules_task3.gd" id="1"]

[node name="TestAILabRulesTask3" type="Node"]
script = ExtResource("1")
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
godot --headless --path . res://tools/test_ai_lab_rules_task3.tscn
```

Expected: FAIL because AI Lab still has `RenjuCheckBox` and/or HUD suffix still contains old copy.

- [ ] **Step 3: Update AI Lab scene**

Modify `scenes/ai_lab/ai_lab.tscn`:

- Add external resource:

```ini
[ext_resource type="PackedScene" path="res://scenes/common/rules_card_selector.tscn" id="2"]
```

- Change `load_steps=2` to `load_steps=3`.
- Replace the `RenjuCheckBox` node with:

```ini
[node name="RulesSelector" parent="VBoxContainer" instance=ExtResource("2")]
unique_name_in_owner = true
layout_mode = 2
```

- If the screen becomes too tall, adjust `VBoxContainer.offset_top` and `offset_bottom` to keep the panel centered within the viewport, for example `-320.0` and `320.0`.

- [ ] **Step 4: Update AI Lab script**

Modify `scenes/ai_lab/ai_lab.gd`:

- Replace:

```gdscript
@onready var renju_checkbox: CheckBox = %RenjuCheckBox
```

with:

```gdscript
@onready var rules_selector = %RulesSelector
```

- Replace every `renju_checkbox.button_pressed` with `rules_selector.forbidden_enabled`.
- Replace every `renju_checkbox.disabled = true` with `rules_selector.set_disabled(true)`.
- Replace every `renju_checkbox.disabled = false` with `rules_selector.set_disabled(false)`.

Specifically, `_on_watch_pressed()` should call:

```gdscript
GameManager.setup_ai_vs_ai(engine_b, engine_w, rules_selector.forbidden_enabled)
```

and `_on_run_batch_pressed()` should set:

```gdscript
batch_use_renju_rules = rules_selector.forbidden_enabled
rules_selector.set_disabled(true)
```

and `_run_next_batch_game()` completion should set:

```gdscript
rules_selector.set_disabled(false)
```

- [ ] **Step 5: Update HUD rules suffix**

Modify `scenes/game/game.gd` so `_ruleset_suffix()` is:

```gdscript
func _ruleset_suffix() -> String:
	return "（禁手规则）" if GameManager.forbidden_enabled else "（自由五子棋）"
```

- [ ] **Step 6: Run focused tests and grep copy**

Run:

```bash
godot --headless --path . res://tools/test_ai_lab_rules_task3.tscn
grep -R "Renju" -n scenes scripts project.godot | grep -v "class_name RenjuForbidden" | grep -v "renju_forbidden" | grep -v "_RenjuForbidden" | grep -v "Renju mode"
```

Expected: focused test passes. Grep should only show internal code identifiers/comments, not `.tscn` UI labels or setup scene strings.

- [ ] **Step 7: Run regression tests**

Run:

```bash
godot --headless --path . res://tools/test_rules_card_selector_task1.tscn
godot --headless --path . res://tools/test_setup_rules_task2.tscn
godot --headless --path . --quit
```

Expected: focused tests pass; parse check exits 0 with known Linux GDExtension warning.

- [ ] **Step 8: Commit Task 3**

Run:

```bash
git add scenes/ai_lab/ai_lab.tscn scenes/ai_lab/ai_lab.gd scenes/game/game.gd tools/test_ai_lab_rules_task3.gd tools/test_ai_lab_rules_task3.tscn
git commit -m "ui: use Chinese-only rules copy"
```

---

### Task 4: Fix iPhone portrait activation

**Files:**
- Modify: `scenes/game/game.gd`
- Modify: `export_presets.cfg`
- Test: `tools/test_game_layout_task4.gd`
- Test: `tools/test_game_layout_task4.tscn`

- [ ] **Step 1: Write layout predicate test**

Create `tools/test_game_layout_task4.gd`:

```gdscript
extends SceneTree

func _init() -> void:
	var game_script = load("res://scenes/game/game.gd")
	var game = game_script.new()
	assert(game._should_use_vertical_layout(Vector2i(390, 844)) == true)
	assert(game._should_use_vertical_layout(Vector2i(844, 390)) == false)
	assert(game._should_use_vertical_layout(Vector2i(1024, 768)) == false)
	assert(game._should_use_vertical_layout(Vector2i(768, 1024)) == false)

	print("GAME_LAYOUT_TASK4_TESTS PASS")
	quit()
```

Create `tools/test_game_layout_task4.tscn`:

```ini
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://tools/test_game_layout_task4.gd" id="1"]

[node name="TestGameLayoutTask4" type="Node"]
script = ExtResource("1")
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
godot --headless --path . res://tools/test_game_layout_task4.tscn
```

Expected: FAIL because `_should_use_vertical_layout()` does not exist.

- [ ] **Step 3: Add layout predicate and use it**

Modify `scenes/game/game.gd`:

- Add helper near `_apply_responsive_layout()`:

```gdscript
func _should_use_vertical_layout(size: Vector2i) -> bool:
	var is_portrait: bool = size.y > size.x
	var narrow_width: bool = size.x <= 700
	return is_portrait and narrow_width
```

- Replace:

```gdscript
var use_vertical: bool = OS.get_name() == "iOS" and size.y > size.x
```

with:

```gdscript
var use_vertical: bool = _should_use_vertical_layout(size)
```

This keeps iPad portrait at 768×1024 on the horizontal layout while allowing iPhone portrait widths to use the vertical layout.

- [ ] **Step 4: Update iOS export orientation**

Inspect Godot 4.2 iOS export preset key names already generated for orientation support. If the preset accepts orientation booleans, add the portrait settings under `[preset.2.options]`:

```ini
orientation/portrait=true
orientation/landscape_left=false
orientation/landscape_right=false
orientation/portrait_upside_down=false
```

If Godot rewrites these keys with different names after opening/exporting the project, keep the Godot-generated names and values that force portrait on iPhone. Do not change `application/targeted_device_family=2` unless target-device testing shows this is wrong for the existing release pipeline.

- [ ] **Step 5: Run layout and parse checks**

Run:

```bash
godot --headless --path . res://tools/test_game_layout_task4.tscn
godot --headless --path . --quit
```

Expected: `GAME_LAYOUT_TASK4_TESTS PASS`; parse check exits 0 with known Linux GDExtension warning.

- [ ] **Step 6: Commit Task 4**

Run:

```bash
git add scenes/game/game.gd export_presets.cfg tools/test_game_layout_task4.gd tools/test_game_layout_task4.tscn
git commit -m "ios: prefer portrait gameplay layout"
```

---

### Task 5: Refresh font subset and final local verification

**Files:**
- Modify if generated output changes: `assets/fonts/cjk_subset.otf`
- Modify if generated output changes: `assets/fonts/cjk_subset_chars.txt`
- Test: existing focused tests and font tooling

- [ ] **Step 1: Check font coverage**

Run:

```bash
python3 tools/generate_cjk_subset.py --check
```

Expected: PASS. If it fails with missing glyphs, regenerate from the current source font used in this repo, for example:

```bash
python3 tools/generate_cjk_subset.py --source-font /tmp/NotoSansCJKsc-Regular.otf
python3 tools/generate_cjk_subset.py --check
```

Expected after regeneration: PASS.

- [ ] **Step 2: Run all focused UX polish tests**

Run:

```bash
godot --headless --path . res://tools/test_rules_card_selector_task1.tscn
godot --headless --path . res://tools/test_setup_rules_task2.tscn
godot --headless --path . res://tools/test_ai_lab_rules_task3.tscn
godot --headless --path . res://tools/test_game_layout_task4.tscn
```

Expected: all print `PASS` and exit 0.

- [ ] **Step 3: Run existing regression checks**

Run:

```bash
godot --headless --path . res://tools/test_ai_watch_task8.tscn
godot --headless --path . res://tools/test_replay_task6.tscn
godot --headless --path . res://tools/test_undo_task5.tscn
godot --headless --path . --quit
```

Expected: all focused tests pass; parse check exits 0 with known Linux missing `gomoku_neural` GDExtension warning.

- [ ] **Step 4: Check user-facing Renju copy and whitespace**

Run:

```bash
grep -R "Renju" -n scenes project.godot
git diff --check
```

Expected: no `Renju` matches in user-facing scenes/project settings; `git diff --check` prints nothing.

- [ ] **Step 5: Token-shaped scan before push/merge**

Run:

```bash
git diff main...HEAD | grep -E -i '(AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|-----BEGIN (RSA|EC|OPENSSH|PRIVATE) KEY-----|ghp_[A-Za-z0-9_]{36,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9]{20,}|xox[baprs]-[A-Za-z0-9-]{10,})'
```

Expected: no output and exit code 1 from `grep`.

- [ ] **Step 6: Commit generated font refresh if needed**

If `assets/fonts/cjk_subset.otf` or `assets/fonts/cjk_subset_chars.txt` changed, run:

```bash
git add assets/fonts/cjk_subset.otf assets/fonts/cjk_subset_chars.txt
git commit -m "fix: refresh CJK font subset for UX polish"
```

If the font did not change, skip this commit.

- [ ] **Step 7: Leave worktree in place for post-merge validation**

Do not delete `/home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish` after merging/pushing. Keep it until iPhone/iPad/macOS validation passes or the user explicitly approves cleanup.

---

## Self-Review

- Spec coverage: Task 1 creates the reusable card selector; Tasks 2 and 3 apply it to local PvP, human-vs-AI, and AI Lab; Task 3 removes English UI rules copy; Task 4 fixes portrait activation; Task 5 covers font, parse, regression, token, and worktree lifecycle checks.
- Placeholder scan: no `TBD`, `TODO`, or unspecified implementation steps remain.
- Type consistency: `RulesSelector.forbidden_enabled`, `RulesSelector.set_disabled()`, `selection_changed`, and `_should_use_vertical_layout(size: Vector2i)` are defined before later tasks use them.
