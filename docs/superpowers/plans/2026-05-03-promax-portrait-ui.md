# Pro Max iPhone Portrait UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign iPhone portrait UI as a deliberate phone layout, with Pro Max / Plus as the primary visual target: near-full-width centered gameplay board, centered readable status card, full-width large action buttons, and phone-sized menu/setup screens.

**Architecture:** Preserve the existing responsive split: iPhone portrait uses dedicated vertical/mobile behavior while iPad/macOS horizontal layout remains unchanged. Strengthen Godot headless layout tests around rendered sizes across small, standard, and Pro Max phone widths before implementing. Keep changes local to existing scene scripts/scene files unless a focused test scene is required.

**Tech Stack:** Godot 4 GDScript, `.tscn` scenes, headless Godot `SubViewport` layout tests, existing `Board.board_pixel_size` API.

---

## Approved Design Target

Primary validation target is large iPhone / Plus / Pro Max portrait, not 390-wide standard iPhone.

```text
Large iPhone portrait logical width: 430–440
Large iPhone portrait logical height: 920–960
Side margin: 16–18
Content width: 396–408
Gameplay board: 396–404, centered
Status card: content width, centered, main status 22–24px
Bottom action buttons: content width, 54–58px high, 18–20px text
Menu/setup buttons: content width, 58–64px high, 19–21px text
```

Compatibility targets remain:

```text
Small iPhone: 375 wide, no overflow, board/content around 343–347
Standard iPhone: 390 wide, no overflow, board/content around 358–362
Large iPhone: 430–440 wide, primary visual target, board/content around 396–408
```

All user-facing UI remains Chinese-only. Do not add `Renju` text.

---

## File Structure

- Modify: `docs/superpowers/progress/offline-ux-polish-progress.md`
  - Durable checkpoint before every state transition.
- Modify: `tools/test_iphone_portrait_ui_task.gd`
  - Gameplay portrait tests for Pro Max board/status/action sizing, button height, label sizing, and no horizontal regression.
- Create: `tools/test_iphone_portrait_menu_ui_task.gd`
  - Focused phone-menu/setup layout test covering main menu, local setup, human-vs-AI setup, and AI Lab setup at 430×932 plus small-width containment.
- Create: `tools/test_iphone_portrait_menu_ui_task.tscn`
  - Minimal test runner scene for the new menu/setup test script.
- Modify: `scenes/game/game.gd`
  - Replace 390-first portrait sizing with content-width rules that scale to 430–440 primary target.
  - Keep horizontal layout restoration intact.
- Modify: `scenes/game/game.tscn`
  - Only adjust vertical-only margins/padding if needed to meet the Pro Max and small-phone tests.
- Modify: `scenes/main_menu/main_menu.gd`
  - Apply phone portrait sizing to main menu container/buttons while preserving existing navigation.
- Modify: `scenes/main_menu/main_menu.tscn`
  - Add unique names or minimal layout defaults only if the script needs stable node references.
- Modify: `scenes/local_setup/local_setup.gd`
  - Apply phone portrait sizing to setup container/title/buttons/rules selector.
- Modify: `scenes/local_setup/local_setup.tscn`
  - Add unique names or minimal layout defaults only if needed.
- Modify: `scenes/ai_setup/ai_setup.gd`
  - Apply phone portrait sizing to setup container/color buttons/level grid/bottom buttons.
- Modify: `scenes/ai_setup/ai_setup.tscn`
  - Replace phone-hostile horizontal bottom buttons with portrait-friendly sizing when in portrait.
- Modify: `scenes/ai_lab/ai_lab.gd`
  - Apply phone portrait sizing to AI Lab rows/actions/back button.
- Modify: `scenes/ai_lab/ai_lab.tscn`
  - Add unique names or minimal layout defaults only if needed.

---

## Task 1: Checkpoint and Strengthen Gameplay Portrait Test for Pro Max

**Files:**
- Modify: `docs/superpowers/progress/offline-ux-polish-progress.md`
- Modify: `tools/test_iphone_portrait_ui_task.gd`

- [ ] **Step 1: Verify preserved worktree state before editing**

Run:

```bash
git -C /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish status --short --branch
git -C /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish log --oneline -5
```

Expected:
- Worktree is still the preserved `offline-ux-polish` worktree, or clearly points to the current offline UX branch state.
- Do not stage `.superpowers/` scratch.
- Do not stage canonical checkout training files or `layout/` screenshots.

- [ ] **Step 2: Update progress before changing tests**

In `docs/superpowers/progress/offline-ux-polish-progress.md`, set:

```markdown
**Status:** IMPLEMENTING_PROMAX_PORTRAIT_UI_RED
**Workflow:** subagent-driven-development
**Current task:** Task 1 — Strengthen gameplay portrait tests for the approved Pro Max / Plus phone layout.
**Next action:** Add RED assertions that large iPhone portrait renders a near-400px centered board, centered status card, and full-width large bottom action buttons.
```

Add a Task Ledger row:

```markdown
| Pro Max portrait UI Task 1 — gameplay RED tests | IN_PROGRESS | none | Pending RED run. | Primary validation target is 430×932 / 440×956, with 375/390 compatibility. |
```

- [ ] **Step 3: Add explicit Pro Max constants in `tools/test_iphone_portrait_ui_task.gd`**

Near existing constants or near the top of the script, add:

```gdscript
const SMALL_IPHONE_SIZE := Vector2i(375, 812)
const STANDARD_IPHONE_SIZE := Vector2i(390, 844)
const PROMAX_IPHONE_SIZE := Vector2i(430, 932)
const PROMAX_WIDE_IPHONE_SIZE := Vector2i(440, 956)

const PHONE_SIDE_MARGIN_MAX: float = 20.0
const PROMAX_CONTENT_MIN_WIDTH: float = 396.0
const PROMAX_BOARD_MIN_SIZE: float = 396.0
const PROMAX_BUTTON_MIN_HEIGHT: float = 54.0
const PROMAX_STATUS_MAIN_FONT_MIN: int = 22
const PROMAX_BUTTON_FONT_MIN: int = 18
```

- [ ] **Step 4: Add reusable layout assertion helpers**

Near existing `_assert_inside_viewport`, `_assert_centered_x`, and `_assert_min_width`, add:

```gdscript
func _assert_square_size(control: Control, min_size: float, max_size: float, message: String) -> bool:
	var rect := control.get_global_rect()
	return _expect(
		rect.size.x >= min_size and rect.size.y >= min_size and rect.size.x <= max_size and rect.size.y <= max_size and absf(rect.size.x - rect.size.y) <= 1.0,
		"%s square size %.1fx%.1f expected %.1f..%.1f rect=%s" % [message, rect.size.x, rect.size.y, min_size, max_size, rect]
	)


func _assert_min_height(control: Control, min_height: float, message: String) -> bool:
	var rect := control.get_global_rect()
	return _expect(rect.size.y >= min_height, "%s height %.1f expected >= %.1f rect=%s" % [message, rect.size.y, min_height, rect])


func _assert_font_size(control: Control, override_name: String, min_size: int, message: String) -> bool:
	var font_size := control.get_theme_font_size(override_name)
	return _expect(font_size >= min_size, "%s font size %d expected >= %d" % [message, font_size, min_size])
```

- [ ] **Step 5: Add or strengthen the Pro Max gameplay case**

If the file already has a helper that loads the game into a `SubViewport`, reuse it. The Pro Max case must assert rendered geometry, not just properties:

```gdscript
func _run_promax_portrait_case() -> void:
	var viewport := SubViewport.new()
	viewport.size = PROMAX_IPHONE_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	var game := preload("res://scenes/game/game.tscn").instantiate()
	viewport.add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame

	var board_frame := _find_node(game, "BoardFrame") as Control
	var vertical_status := _find_node(game, "VerticalStatus") as MarginContainer
	var vertical_actions := _find_node(game, "VerticalActions") as MarginContainer
	var status_container := _find_node(game, "StatusContainer") as VBoxContainer
	var actions_container := _find_node(game, "ActionsContainer") as VBoxContainer
	var turn_label := _find_node(game, "TurnLabel") as Label
	var color_label := _find_node(game, "ColorLabel") as Label
	var move_label := _find_node(game, "MoveLabel") as Label
	var undo_button := _find_node(game, "UndoButton") as Button
	var new_game_button := _find_node(game, "NewGameButton") as Button
	var back_to_menu_button := _find_node(game, "BackToMenuButton") as Button

	if not _expect(board_frame != null, "BoardFrame should exist"):
		return
	if not _expect(vertical_status != null, "VerticalStatus should exist"):
		return
	if not _expect(vertical_actions != null, "VerticalActions should exist"):
		return
	if not _expect(status_container != null, "StatusContainer should exist"):
		return
	if not _expect(actions_container != null, "ActionsContainer should exist"):
		return

	if not _assert_square_size(board_frame, PROMAX_BOARD_MIN_SIZE, 408.0, "Pro Max BoardFrame"):
		return
	if not _assert_centered_x(board_frame, float(PROMAX_IPHONE_SIZE.x), 3.0, "Pro Max BoardFrame"):
		return
	if not _assert_min_width(vertical_status, PROMAX_CONTENT_MIN_WIDTH, "Pro Max VerticalStatus"):
		return
	if not _assert_centered_x(vertical_status, float(PROMAX_IPHONE_SIZE.x), 3.0, "Pro Max VerticalStatus"):
		return
	if not _assert_min_width(status_container, PROMAX_CONTENT_MIN_WIDTH, "Pro Max StatusContainer"):
		return
	if not _assert_centered_x(status_container, float(PROMAX_IPHONE_SIZE.x), 3.0, "Pro Max StatusContainer"):
		return
	if not _expect(turn_label.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER, "TurnLabel should be centered in Pro Max portrait"):
		return
	if not _expect(color_label.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER, "ColorLabel should be centered in Pro Max portrait"):
		return
	if not _expect(move_label.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER, "MoveLabel should be centered in Pro Max portrait"):
		return
	if not _assert_font_size(turn_label, "font_size", PROMAX_STATUS_MAIN_FONT_MIN, "TurnLabel"):
		return
	if not _assert_min_width(vertical_actions, PROMAX_CONTENT_MIN_WIDTH, "Pro Max VerticalActions"):
		return
	if not _assert_centered_x(vertical_actions, float(PROMAX_IPHONE_SIZE.x), 3.0, "Pro Max VerticalActions"):
		return
	if not _assert_min_width(actions_container, PROMAX_CONTENT_MIN_WIDTH, "Pro Max ActionsContainer"):
		return
	if not _assert_centered_x(actions_container, float(PROMAX_IPHONE_SIZE.x), 3.0, "Pro Max ActionsContainer"):
		return
	for button: Button in [undo_button, new_game_button, back_to_menu_button]:
		if not _assert_min_width(button, PROMAX_CONTENT_MIN_WIDTH, "%s Pro Max width" % button.name):
			return
		if not _assert_min_height(button, PROMAX_BUTTON_MIN_HEIGHT, "%s Pro Max height" % button.name):
			return
		if not _assert_font_size(button, "font_size", PROMAX_BUTTON_FONT_MIN, "%s" % button.name):
			return

	for control: Control in [vertical_status, board_frame, vertical_actions, status_container, actions_container, undo_button, new_game_button, back_to_menu_button]:
		if not _assert_inside_viewport(control, Vector2(PROMAX_IPHONE_SIZE)):
			return

	viewport.queue_free()
```

Call `_run_promax_portrait_case()` from the test runner before printing success.

- [ ] **Step 6: Add a 440-wide large phone case**

Add a second large-phone assertion using the existing portrait helper or this wrapper:

```gdscript
func _run_promax_wide_portrait_case() -> void:
	var viewport := SubViewport.new()
	viewport.size = PROMAX_WIDE_IPHONE_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	var game := preload("res://scenes/game/game.tscn").instantiate()
	viewport.add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame

	var board_frame := _find_node(game, "BoardFrame") as Control
	var actions_container := _find_node(game, "ActionsContainer") as VBoxContainer
	if not _assert_square_size(board_frame, 404.0, 416.0, "440-wide BoardFrame"):
		return
	if not _assert_centered_x(board_frame, float(PROMAX_WIDE_IPHONE_SIZE.x), 3.0, "440-wide BoardFrame"):
		return
	if not _assert_min_width(actions_container, 404.0, "440-wide ActionsContainer"):
		return

	viewport.queue_free()
```

Call `_run_promax_wide_portrait_case()` from the test runner.

- [ ] **Step 7: Run focused test and confirm RED**

Run:

```bash
godot --headless --path /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish res://tools/test_iphone_portrait_ui_task.tscn
```

Expected: FAIL on one or more new Pro Max assertions, such as board size less than 396, button height less than 54, or font size below the new threshold. If it passes immediately, tighten the test against the approved mockup before implementing.

- [ ] **Step 8: Record RED evidence**

Add a verification row to `docs/superpowers/progress/offline-ux-polish-progress.md`:

```markdown
| 2026-05-03 Pro Max gameplay RED | `godot --headless --path /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish res://tools/test_iphone_portrait_ui_task.tscn` | RED FAIL | Intended Pro Max portrait assertion failed before implementation. |
```

---

## Task 2: Implement Pro Max-First Gameplay Portrait Layout

**Files:**
- Modify: `docs/superpowers/progress/offline-ux-polish-progress.md`
- Modify: `scenes/game/game.gd`
- Modify: `scenes/game/game.tscn` only if margins/padding prevent the tests from passing

- [ ] **Step 1: Update progress before implementation**

Set:

```markdown
**Status:** IMPLEMENTING_PROMAX_GAMEPLAY_LAYOUT
**Current task:** Task 2 — Implement Pro Max-first gameplay portrait layout.
**Next action:** Replace 390-first gameplay portrait sizing with content-width rules that produce a 396–404px centered board on large iPhones while preserving small-phone containment and horizontal layout.
```

- [ ] **Step 2: Add phone layout constants to `scenes/game/game.gd`**

Near existing layout constants, add:

```gdscript
const PHONE_SIDE_MARGIN_RATIO: float = 0.04
const PHONE_SIDE_MARGIN_MIN: float = 14.0
const PHONE_SIDE_MARGIN_MAX: float = 18.0
const PHONE_PROMAX_BOARD_TARGET_MIN: float = 396.0
const PHONE_PROMAX_BOARD_TARGET_MAX: float = 408.0
const PHONE_STATUS_HEIGHT_PROMAX: float = 108.0
const PHONE_ACTION_HEIGHT_PROMAX: float = 56.0
const PHONE_ACTION_HEIGHT_SMALL: float = 52.0
const PHONE_ACTION_GAP: float = 10.0
const PHONE_TOP_CHROME: float = 18.0
const PHONE_BOTTOM_CHROME: float = 18.0
```

- [ ] **Step 3: Replace or update `_portrait_side_margin(width: float)`**

Use this implementation:

```gdscript
func _portrait_side_margin(width: float) -> float:
	return clampf(width * PHONE_SIDE_MARGIN_RATIO, PHONE_SIDE_MARGIN_MIN, PHONE_SIDE_MARGIN_MAX)
```

- [ ] **Step 4: Add content-width and action-height helpers**

Below `_portrait_side_margin`, add:

```gdscript
func _portrait_content_width(width: float) -> float:
	return width - _portrait_side_margin(width) * 2.0


func _portrait_action_height(width: float) -> float:
	return PHONE_ACTION_HEIGHT_PROMAX if width >= 428.0 else PHONE_ACTION_HEIGHT_SMALL
```

- [ ] **Step 5: Replace portrait board-size budgeting in `_apply_responsive_layout()`**

In the `if use_vertical:` block that computes `board_size`, use this logic:

```gdscript
if use_vertical:
	var viewport_width: float = float(size.x)
	var viewport_height: float = float(size.y)
	var side_margin: float = _portrait_side_margin(viewport_width)
	var content_width: float = viewport_width - side_margin * 2.0
	var action_rows: int = max(1, _visible_action_count())
	var action_height: float = _portrait_action_height(viewport_width)
	var actions_height: float = float(action_rows) * action_height + float(max(0, action_rows - 1)) * PHONE_ACTION_GAP + 20.0
	var status_height: float = PHONE_STATUS_HEIGHT_PROMAX if viewport_width >= 428.0 else 96.0
	var vertical_chrome: float = PHONE_TOP_CHROME + status_height + 10.0 + actions_height + PHONE_BOTTOM_CHROME
	var width_budget: float = content_width
	var height_budget: float = viewport_height - vertical_chrome
	board_size = minf(minf(width_budget, height_budget), 620.0)
else:
	# Keep the existing horizontal board-size logic unchanged.
	pass
```

Do not leave the literal `pass` in the function. Keep the existing horizontal branch exactly as it was before this step.

Keep the existing lower clamp, but make sure it allows small phones to fit:

```gdscript
board_size = maxf(board_size, PORTRAIT_BOARD_MIN if use_vertical else 320.0)
```

If the current function already uses a responsive minimum, preserve that behavior and only change the Pro Max target sizing.

- [ ] **Step 6: Set portrait minimum widths after computing `board_size`**

In `_apply_responsive_layout()`, after `board_frame.custom_minimum_size` is set, add or update:

```gdscript
if use_vertical:
	var content_width: float = _portrait_content_width(float(size.x))
	vertical_status.custom_minimum_size.x = content_width
	vertical_actions.custom_minimum_size.x = content_width
	status_container.custom_minimum_size.x = content_width
	actions_container.custom_minimum_size.x = content_width
else:
	vertical_status.custom_minimum_size.x = 0.0
	vertical_actions.custom_minimum_size.x = 0.0
	status_container.custom_minimum_size.x = 0.0
	actions_container.custom_minimum_size.x = 0.0
```

- [ ] **Step 7: Update `_apply_gameplay_readability(use_vertical)` for large-phone typography and buttons**

At the start of `_apply_gameplay_readability(use_vertical)`, derive phone-specific sizes:

```gdscript
var viewport_width: float = float(get_viewport_rect().size.x)
var is_large_phone: bool = use_vertical and viewport_width >= 428.0
var status_font_size: int = 22 if is_large_phone else 20
var detail_font_size: int = 16 if is_large_phone else 15
var message_font_size: int = 14
var action_font_size: int = 18 if is_large_phone else 17
var action_height: float = _portrait_action_height(viewport_width) if use_vertical else 44.0
```

Then ensure these overrides are applied:

```gdscript
turn_label.add_theme_font_size_override("font_size", status_font_size)
color_label.add_theme_font_size_override("font_size", detail_font_size)
move_label.add_theme_font_size_override("font_size", detail_font_size)
message_label.add_theme_font_size_override("font_size", message_font_size)

turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if use_vertical else HORIZONTAL_ALIGNMENT_LEFT
color_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if use_vertical else HORIZONTAL_ALIGNMENT_LEFT
move_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if use_vertical else HORIZONTAL_ALIGNMENT_LEFT
message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

var fill_horizontal: int = Control.SIZE_EXPAND_FILL if use_vertical else Control.SIZE_FILL
status_container.size_flags_horizontal = fill_horizontal
actions_container.size_flags_horizontal = fill_horizontal
vertical_status_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
vertical_actions_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
```

In the action button loop, use:

```gdscript
for button: Button in [undo_button, pause_button, step_button, auto_button, new_game_button, back_to_menu_button, resign_button]:
	button.custom_minimum_size.y = action_height
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL if use_vertical else Control.SIZE_FILL
	button.add_theme_font_size_override("font_size", action_font_size)
```

If the current implementation preserves `PauseButton`, `StepButton`, and `AutoButton` as `SIZE_EXPAND_FILL` in horizontal AI-watch mode, keep that exception.

- [ ] **Step 8: Run focused gameplay test and confirm GREEN**

Run:

```bash
godot --headless --path /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish res://tools/test_iphone_portrait_ui_task.tscn
```

Expected: `IPHONE_PORTRAIT_UI_TASK_TESTS PASS`.

- [ ] **Step 9: Run horizontal/regression checks for gameplay**

Run:

```bash
godot --headless --path /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish res://tools/test_game_layout_task4.tscn
godot --headless --path /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish res://tools/test_ai_watch_task8.tscn
git -C /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish diff --check -- scenes/game/game.gd scenes/game/game.tscn tools/test_iphone_portrait_ui_task.gd docs/superpowers/progress/offline-ux-polish-progress.md
```

Expected:
- `GAME_LAYOUT_TASK4_TESTS PASS`
- `AI_WATCH_TASK8_TESTS PASS`
- `git diff --check` exits 0
- Linux `gomoku_neural.gdextension` warning is expected and not a failure.

- [ ] **Step 10: Request review for gameplay task**

Use `superpowers:requesting-code-review` / `superpowers:code-reviewer` with this context:

```text
Review Task 2 of Pro Max iPhone portrait UI redesign. Requirements: Pro Max/Plus portrait 430–440 logical width should render a 396–404px centered gameplay board, centered readable status card, full-width 54–58px bottom action buttons, small/standard iPhones must not overflow, and horizontal iPad/macOS layout must be preserved. Check scenes/game/game.gd, scenes/game/game.tscn, and tools/test_iphone_portrait_ui_task.gd.
```

Fix Critical or Important findings before proceeding.

- [ ] **Step 11: Commit Task 1–2 gameplay changes**

Only after GREEN tests and review:

```bash
git -C /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish status --short
git -C /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish add scenes/game/game.gd scenes/game/game.tscn tools/test_iphone_portrait_ui_task.gd docs/superpowers/progress/offline-ux-polish-progress.md
git -C /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish commit -m "fix: scale iPhone portrait gameplay for Pro Max"
```

Do not stage `.superpowers/`, `layout/`, or unrelated training files.

---

## Task 3: Add RED Tests for Phone-Sized Menu and Setup Screens

**Files:**
- Modify: `docs/superpowers/progress/offline-ux-polish-progress.md`
- Create: `tools/test_iphone_portrait_menu_ui_task.gd`
- Create: `tools/test_iphone_portrait_menu_ui_task.tscn`

- [ ] **Step 1: Update progress before creating the menu/setup test**

Set:

```markdown
**Status:** IMPLEMENTING_PROMAX_MENU_SETUP_RED
**Current task:** Task 3 — Add RED tests for phone-sized main menu and setup screens.
**Next action:** Create a focused SubViewport test proving main menu, local setup, AI setup, and AI Lab use full-width phone controls on 430×932 and do not overflow on 375×812.
```

- [ ] **Step 2: Create `tools/test_iphone_portrait_menu_ui_task.tscn`**

Write:

```ini
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://tools/test_iphone_portrait_menu_ui_task.gd" id="1"]

[node name="IPhonePortraitMenuUITaskTest" type="Node"]
script = ExtResource("1")
```

- [ ] **Step 3: Create `tools/test_iphone_portrait_menu_ui_task.gd`**

Write this complete test file:

```gdscript
extends Node

const SMALL_IPHONE_SIZE := Vector2i(375, 812)
const PROMAX_IPHONE_SIZE := Vector2i(430, 932)
const PROMAX_CONTENT_MIN_WIDTH: float = 396.0
const SMALL_CONTENT_MIN_WIDTH: float = 343.0
const PROMAX_PRIMARY_BUTTON_MIN_HEIGHT: float = 56.0
const PROMAX_TITLE_FONT_MIN: int = 28
const PROMAX_BUTTON_FONT_MIN: int = 18

var _failed: bool = false


func _ready() -> void:
	await _run_all()
	if _failed:
		get_tree().quit(1)
	else:
		print("IPHONE_PORTRAIT_MENU_UI_TASK_TESTS PASS")
		get_tree().quit(0)


func _run_all() -> void:
	await _assert_scene_phone_layout("res://scenes/main_menu/main_menu.tscn", ["LocalPvpButton", "VsAiButton", "AiLabButton"], [])
	await _assert_scene_phone_layout("res://scenes/local_setup/local_setup.tscn", ["StartButton", "BackButton"], ["RulesSelector"])
	await _assert_scene_phone_layout("res://scenes/ai_setup/ai_setup.tscn", ["BlackButton", "WhiteButton", "StartButton", "BackButton"], ["LevelGrid", "RulesSelector"])
	await _assert_scene_phone_layout("res://scenes/ai_lab/ai_lab.tscn", ["WatchButton", "RunBatchButton", "ReplayLastBatchButton", "BackButton"], ["RulesSelector"])
	await _assert_small_phone_containment("res://scenes/main_menu/main_menu.tscn")
	await _assert_small_phone_containment("res://scenes/local_setup/local_setup.tscn")
	await _assert_small_phone_containment("res://scenes/ai_setup/ai_setup.tscn")
	await _assert_small_phone_containment("res://scenes/ai_lab/ai_lab.tscn")


func _assert_scene_phone_layout(scene_path: String, primary_button_names: Array[String], wide_control_names: Array[String]) -> void:
	var viewport := SubViewport.new()
	viewport.size = PROMAX_IPHONE_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	var scene := load(scene_path).instantiate()
	viewport.add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame

	var root_control := scene as Control
	if not _expect(root_control != null, "%s root should be Control" % scene_path):
		viewport.queue_free()
		return

	for button_name in primary_button_names:
		var button := _find_node(scene, button_name) as Button
		if not _expect(button != null, "%s should exist in %s" % [button_name, scene_path]):
			continue
		_assert_min_width(button, PROMAX_CONTENT_MIN_WIDTH, "%s %s" % [scene_path, button_name])
		_assert_min_height(button, PROMAX_PRIMARY_BUTTON_MIN_HEIGHT, "%s %s" % [scene_path, button_name])
		_assert_centered_x(button, float(PROMAX_IPHONE_SIZE.x), 4.0, "%s %s" % [scene_path, button_name])
		_assert_font_size(button, "font_size", PROMAX_BUTTON_FONT_MIN, "%s %s" % [scene_path, button_name])
		_assert_inside_viewport(button, Vector2(PROMAX_IPHONE_SIZE))

	for control_name in wide_control_names:
		var control := _find_node(scene, control_name) as Control
		if not _expect(control != null, "%s should exist in %s" % [control_name, scene_path]):
			continue
		_assert_min_width(control, PROMAX_CONTENT_MIN_WIDTH, "%s %s" % [scene_path, control_name])
		_assert_centered_x(control, float(PROMAX_IPHONE_SIZE.x), 4.0, "%s %s" % [scene_path, control_name])
		_assert_inside_viewport(control, Vector2(PROMAX_IPHONE_SIZE))

	var title := _find_node(scene, "TitleLabel") as Label
	if title != null:
		_assert_font_size(title, "font_size", PROMAX_TITLE_FONT_MIN, "%s TitleLabel" % scene_path)
		if not _expect(title.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER, "%s TitleLabel should be centered" % scene_path):
			pass

	viewport.queue_free()


func _assert_small_phone_containment(scene_path: String) -> void:
	var viewport := SubViewport.new()
	viewport.size = SMALL_IPHONE_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	var scene := load(scene_path).instantiate()
	viewport.add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame

	_assert_all_visible_controls_inside(scene, Vector2(SMALL_IPHONE_SIZE), scene_path)

	var buttons := _collect_buttons(scene)
	for button in buttons:
		if button.visible:
			_assert_min_width(button, SMALL_CONTENT_MIN_WIDTH, "%s %s small width" % [scene_path, button.name])
			_assert_inside_viewport(button, Vector2(SMALL_IPHONE_SIZE))

	viewport.queue_free()


func _collect_buttons(node: Node) -> Array[Button]:
	var result: Array[Button] = []
	if node is Button:
		result.append(node)
	for child in node.get_children():
		result.append_array(_collect_buttons(child))
	return result


func _assert_all_visible_controls_inside(node: Node, viewport_size: Vector2, scene_path: String) -> void:
	if node is Control and node.visible:
		_assert_inside_viewport(node, viewport_size, "%s %s" % [scene_path, node.name])
	for child in node.get_children():
		_assert_all_visible_controls_inside(child, viewport_size, scene_path)


func _find_node(root: Node, node_name: String) -> Node:
	if root.name == node_name:
		return root
	for child in root.get_children():
		var found := _find_node(child, node_name)
		if found != null:
			return found
	return null


func _assert_inside_viewport(control: Control, viewport_size: Vector2, message: String = "") -> bool:
	var rect := control.get_global_rect()
	var label := message if message != "" else control.name
	return _expect(
		rect.position.x >= -0.5 and rect.position.y >= -0.5 and rect.end.x <= viewport_size.x + 0.5 and rect.end.y <= viewport_size.y + 0.5,
		"%s outside %s: %s" % [label, viewport_size, rect]
	)


func _assert_centered_x(control: Control, viewport_width: float, tolerance: float, message: String) -> bool:
	var rect := control.get_global_rect()
	var center_x := rect.position.x + rect.size.x * 0.5
	return _expect(absf(center_x - viewport_width * 0.5) <= tolerance, "%s center %.1f expected %.1f rect=%s" % [message, center_x, viewport_width * 0.5, rect])


func _assert_min_width(control: Control, min_width: float, message: String) -> bool:
	var rect := control.get_global_rect()
	return _expect(rect.size.x >= min_width, "%s width %.1f expected >= %.1f rect=%s" % [message, rect.size.x, min_width, rect])


func _assert_min_height(control: Control, min_height: float, message: String) -> bool:
	var rect := control.get_global_rect()
	return _expect(rect.size.y >= min_height, "%s height %.1f expected >= %.1f rect=%s" % [message, rect.size.y, min_height, rect])


func _assert_font_size(control: Control, override_name: String, min_size: int, message: String) -> bool:
	var font_size := control.get_theme_font_size(override_name)
	return _expect(font_size >= min_size, "%s font size %d expected >= %d" % [message, font_size, min_size])


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		_failed = true
		push_error(message)
		print("FAIL: %s" % message)
	return condition
```

- [ ] **Step 4: Run the new test and confirm RED**

Run:

```bash
godot --headless --path /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish res://tools/test_iphone_portrait_menu_ui_task.tscn
```

Expected: FAIL because current menu/setup screens use centered fixed-size desktop panels, smaller buttons, horizontal bottom rows, or small typography. If it passes immediately, tighten the test around the approved design before implementing.

- [ ] **Step 5: Record RED evidence**

Add a progress verification row:

```markdown
| 2026-05-03 Pro Max menu/setup RED | `godot --headless --path /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish res://tools/test_iphone_portrait_menu_ui_task.tscn` | RED FAIL | Intended phone menu/setup layout assertion failed before implementation. |
```

---

## Task 4: Implement Phone Layout Rules for Main Menu and Setup Screens

**Files:**
- Modify: `docs/superpowers/progress/offline-ux-polish-progress.md`
- Modify: `scenes/main_menu/main_menu.gd`
- Modify: `scenes/main_menu/main_menu.tscn` only if stable node references are missing
- Modify: `scenes/local_setup/local_setup.gd`
- Modify: `scenes/local_setup/local_setup.tscn` only if stable node references are missing
- Modify: `scenes/ai_setup/ai_setup.gd`
- Modify: `scenes/ai_setup/ai_setup.tscn` only if stable node references are missing
- Modify: `scenes/ai_lab/ai_lab.gd`
- Modify: `scenes/ai_lab/ai_lab.tscn` only if stable node references are missing

- [ ] **Step 1: Update progress before implementation**

Set:

```markdown
**Status:** IMPLEMENTING_PROMAX_MENU_SETUP_LAYOUT
**Current task:** Task 4 — Implement phone-sized main menu and setup screens.
**Next action:** Apply shared portrait sizing rules to main menu, local setup, AI setup, and AI Lab without changing navigation or game-mode behavior.
```

- [ ] **Step 2: Add a shared local helper pattern to each affected script**

In each of these scripts:

```text
scenes/main_menu/main_menu.gd
scenes/local_setup/local_setup.gd
scenes/ai_setup/ai_setup.gd
scenes/ai_lab/ai_lab.gd
```

Add these helpers near the bottom of the file:

```gdscript
func _is_phone_portrait() -> bool:
	var viewport_size := get_viewport_rect().size
	return viewport_size.y > viewport_size.x and viewport_size.x <= 700.0


func _phone_side_margin(width: float) -> float:
	return clampf(width * 0.04, 14.0, 18.0)


func _phone_content_width() -> float:
	var width := get_viewport_rect().size.x
	return width - _phone_side_margin(width) * 2.0


func _phone_primary_button_height() -> float:
	return 60.0 if get_viewport_rect().size.x >= 428.0 else 56.0


func _apply_phone_button(button: Button, font_size: int = 19) -> void:
	button.custom_minimum_size = Vector2(_phone_content_width(), _phone_primary_button_height())
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", font_size)
```

Do not change game navigation functions.

- [ ] **Step 3: Connect viewport resize in each `_ready()`**

In each affected script's `_ready()`, add this after existing signal setup:

```gdscript
get_viewport().size_changed.connect(_apply_phone_layout)
_apply_phone_layout()
```

If a script already connects viewport resize, reuse the existing connection and call `_apply_phone_layout()` from it.

- [ ] **Step 4: Implement main menu phone layout**

In `scenes/main_menu/main_menu.gd`, add onready references near existing variables:

```gdscript
@onready var menu_container: VBoxContainer = $VBoxContainer
@onready var local_pvp_button: Button = $VBoxContainer/LocalPvpButton
@onready var vs_ai_button: Button = $VBoxContainer/VsAiButton
@onready var ai_lab_button: Button = $VBoxContainer/AiLabButton
@onready var online_button: Button = $VBoxContainer/OnlineButton
@onready var quit_button: Button = $VBoxContainer/QuitButton
@onready var status_label: Label = %StatusLabel
```

Add:

```gdscript
func _apply_phone_layout() -> void:
	if not is_node_ready():
		return
	if not _is_phone_portrait():
		menu_container.custom_minimum_size = Vector2.ZERO
		return

	var content_width := _phone_content_width()
	menu_container.set_anchors_preset(Control.PRESET_CENTER)
	menu_container.custom_minimum_size = Vector2(content_width, 0.0)
	menu_container.offset_left = -content_width * 0.5
	menu_container.offset_right = content_width * 0.5
	menu_container.offset_top = -250.0
	menu_container.offset_bottom = 250.0
	menu_container.add_theme_constant_override("separation", 12)

	for button: Button in [local_pvp_button, vs_ai_button, ai_lab_button, online_button, quit_button]:
		_apply_phone_button(button, 20)

	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 16)
```

If `$VBoxContainer` is not the exact path because the scene uses unique names, use the existing node path found in the scene and keep the same behavior.

- [ ] **Step 5: Implement local setup phone layout**

In `scenes/local_setup/local_setup.gd`, add onready references:

```gdscript
@onready var setup_container: VBoxContainer = $VBoxContainer
@onready var title_label: Label = $VBoxContainer/TitleLabel
@onready var subtitle_label: Label = $VBoxContainer/SubtitleLabel
@onready var rules_selector: Control = $VBoxContainer/RulesSelector
@onready var start_button: Button = $VBoxContainer/StartButton
@onready var back_button: Button = $VBoxContainer/BackButton
```

Add:

```gdscript
func _apply_phone_layout() -> void:
	if not is_node_ready():
		return
	if not _is_phone_portrait():
		setup_container.custom_minimum_size = Vector2.ZERO
		return

	var content_width := _phone_content_width()
	setup_container.set_anchors_preset(Control.PRESET_CENTER)
	setup_container.custom_minimum_size = Vector2(content_width, 0.0)
	setup_container.offset_left = -content_width * 0.5
	setup_container.offset_right = content_width * 0.5
	setup_container.offset_top = -260.0
	setup_container.offset_bottom = 260.0
	setup_container.add_theme_constant_override("separation", 12)

	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 30)
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle_label.add_theme_font_size_override("font_size", 16)
	rules_selector.custom_minimum_size.x = content_width
	_apply_phone_button(start_button, 20)
	_apply_phone_button(back_button, 19)
```

- [ ] **Step 6: Implement AI setup phone layout**

In `scenes/ai_setup/ai_setup.gd`, add onready references:

```gdscript
@onready var setup_container: VBoxContainer = $VBoxContainer
@onready var title_label: Label = $VBoxContainer/TitleLabel
@onready var color_buttons: VBoxContainer = $VBoxContainer/ColorButtons
@onready var black_button: Button = $VBoxContainer/ColorButtons/BlackButton
@onready var white_button: Button = $VBoxContainer/ColorButtons/WhiteButton
@onready var level_grid: GridContainer = $VBoxContainer/LevelGrid
@onready var rules_selector: Control = $VBoxContainer/RulesSelector
@onready var bottom_buttons: HBoxContainer = $VBoxContainer/BottomButtons
@onready var back_button: Button = $VBoxContainer/BottomButtons/BackButton
@onready var start_button: Button = $VBoxContainer/BottomButtons/StartButton
```

Add:

```gdscript
func _apply_phone_layout() -> void:
	if not is_node_ready():
		return
	if not _is_phone_portrait():
		setup_container.custom_minimum_size = Vector2.ZERO
		return

	var content_width := _phone_content_width()
	setup_container.set_anchors_preset(Control.PRESET_CENTER)
	setup_container.custom_minimum_size = Vector2(content_width, 0.0)
	setup_container.offset_left = -content_width * 0.5
	setup_container.offset_right = content_width * 0.5
	setup_container.offset_top = -330.0
	setup_container.offset_bottom = 330.0
	setup_container.add_theme_constant_override("separation", 10)

	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 30)
	color_buttons.custom_minimum_size.x = content_width
	color_buttons.add_theme_constant_override("separation", 10)
	_apply_phone_button(black_button, 18)
	_apply_phone_button(white_button, 18)
	level_grid.custom_minimum_size.x = content_width
	level_grid.columns = 2
	rules_selector.custom_minimum_size.x = content_width
	bottom_buttons.custom_minimum_size.x = content_width
	bottom_buttons.add_theme_constant_override("separation", 10)
	_apply_phone_button(back_button, 19)
	_apply_phone_button(start_button, 20)
```

Change `ColorButtons` to a vertical stack (or add a portrait-only vertical color host) so rendered `BlackButton` and `WhiteButton` are each full-width phone controls in portrait. If `BottomButtons` as `HBoxContainer` cannot make both buttons full-width without overflow, change the scene node to `VBoxContainer` only in portrait-safe structure, or add a vertical-only wrapper. The resulting rendered `BlackButton`, `WhiteButton`, `BackButton`, and `StartButton` must each be at least `396px` wide on 430×932.

- [ ] **Step 7: Implement AI Lab phone layout**

In `scenes/ai_lab/ai_lab.gd`, add onready references:

```gdscript
@onready var lab_container: VBoxContainer = $VBoxContainer
@onready var title_label: Label = $VBoxContainer/TitleLabel
@onready var match_row: HBoxContainer = $VBoxContainer/MatchRow
@onready var black_level: OptionButton = $VBoxContainer/MatchRow/BlackLevel
@onready var white_level: OptionButton = $VBoxContainer/MatchRow/WhiteLevel
@onready var speed_row: HBoxContainer = $VBoxContainer/SpeedRow
@onready var rules_selector: Control = $VBoxContainer/RulesSelector
@onready var action_row: HBoxContainer = $VBoxContainer/ActionRow
@onready var watch_button: Button = $VBoxContainer/ActionRow/WatchButton
@onready var run_batch_button: Button = $VBoxContainer/ActionRow/RunBatchButton
@onready var replay_last_batch_button: Button = $VBoxContainer/ReplayLastBatchButton
@onready var back_button: Button = $VBoxContainer/BackButton
```

Add:

```gdscript
func _apply_phone_layout() -> void:
	if not is_node_ready():
		return
	if not _is_phone_portrait():
		lab_container.custom_minimum_size = Vector2.ZERO
		return

	var content_width := _phone_content_width()
	lab_container.set_anchors_preset(Control.PRESET_CENTER)
	lab_container.custom_minimum_size = Vector2(content_width, 0.0)
	lab_container.offset_left = -content_width * 0.5
	lab_container.offset_right = content_width * 0.5
	lab_container.offset_top = -350.0
	lab_container.offset_bottom = 350.0
	lab_container.add_theme_constant_override("separation", 10)

	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 30)
	match_row.custom_minimum_size.x = content_width
	black_level.custom_minimum_size.x = (content_width - 10.0) * 0.5
	white_level.custom_minimum_size.x = (content_width - 10.0) * 0.5
	speed_row.custom_minimum_size.x = content_width
	rules_selector.custom_minimum_size.x = content_width
	action_row.custom_minimum_size.x = content_width
	action_row.add_theme_constant_override("separation", 10)
	_apply_phone_button(watch_button, 19)
	_apply_phone_button(run_batch_button, 19)
	_apply_phone_button(replay_last_batch_button, 18)
	_apply_phone_button(back_button, 18)
```

If `ActionRow` as `HBoxContainer` cannot produce full-width `WatchButton` and `RunBatchButton`, convert that portrait structure to a vertical button stack or add a portrait-only vertical action host. The test requires full-width rendered buttons.

- [ ] **Step 8: Run menu/setup focused test and confirm GREEN**

Run:

```bash
godot --headless --path /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish res://tools/test_iphone_portrait_menu_ui_task.tscn
```

Expected: `IPHONE_PORTRAIT_MENU_UI_TASK_TESTS PASS`.

- [ ] **Step 9: Run existing setup regressions**

Run:

```bash
godot --headless --path /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish res://tools/test_rules_card_selector_task1.tscn
godot --headless --path /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish res://tools/test_setup_rules_task2.tscn
godot --headless --path /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish res://tools/test_ai_lab_rules_task3.tscn
git -C /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish diff --check -- scenes/main_menu scenes/local_setup scenes/ai_setup scenes/ai_lab tools/test_iphone_portrait_menu_ui_task.gd tools/test_iphone_portrait_menu_ui_task.tscn docs/superpowers/progress/offline-ux-polish-progress.md
```

Expected:
- `RULES_CARD_SELECTOR_TASK1_TESTS PASS`
- `SETUP_RULES_TASK2_TESTS PASS`
- `AI_LAB_RULES_TASK3_TESTS PASS`
- `git diff --check` exits 0.

- [ ] **Step 10: Request review for menu/setup task**

Use `superpowers:requesting-code-review` / `superpowers:code-reviewer` with this context:

```text
Review Task 4 of Pro Max iPhone portrait UI redesign. Requirements: main menu, local setup, human-vs-AI setup, and AI Lab should look like phone screens on 430×932: content nearly full-width, primary buttons 56–64px high, readable Chinese typography, no tiny centered desktop panel, no overflow on 375×812. Navigation and existing rules/default behavior must be unchanged. Check scenes/main_menu, scenes/local_setup, scenes/ai_setup, scenes/ai_lab, and tools/test_iphone_portrait_menu_ui_task.gd.
```

Fix Critical or Important findings before proceeding.

- [ ] **Step 11: Commit menu/setup changes**

Only after GREEN tests and review:

```bash
git -C /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish status --short
git -C /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish add scenes/main_menu/main_menu.gd scenes/main_menu/main_menu.tscn scenes/local_setup/local_setup.gd scenes/local_setup/local_setup.tscn scenes/ai_setup/ai_setup.gd scenes/ai_setup/ai_setup.tscn scenes/ai_lab/ai_lab.gd scenes/ai_lab/ai_lab.tscn tools/test_iphone_portrait_menu_ui_task.gd tools/test_iphone_portrait_menu_ui_task.tscn docs/superpowers/progress/offline-ux-polish-progress.md
git -C /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish commit -m "fix: scale iPhone portrait menus for Pro Max"
```

If a listed `.tscn` file did not change, omit it from `git add`. Do not stage unrelated files.

---

## Task 5: Final Verification, Review, Commit Hygiene, and Handoff

**Files:**
- Modify: `docs/superpowers/progress/offline-ux-polish-progress.md`

- [ ] **Step 1: Update progress before final verification**

Set:

```markdown
**Status:** VERIFYING_PROMAX_PORTRAIT_UI_REDESIGN
**Current task:** Task 5 — Final verification and review for Pro Max iPhone portrait UI redesign.
**Next action:** Run focused phone UI tests, gameplay regressions, setup regressions, no-Renju scan, diff check, and token scan before finishing branch flow.
```

- [ ] **Step 2: Run focused phone UI tests**

Run:

```bash
godot --headless --path /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish res://tools/test_iphone_portrait_ui_task.tscn
godot --headless --path /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish res://tools/test_iphone_portrait_menu_ui_task.tscn
```

Expected:
- `IPHONE_PORTRAIT_UI_TASK_TESTS PASS`
- `IPHONE_PORTRAIT_MENU_UI_TASK_TESTS PASS`

- [ ] **Step 3: Run regression checks**

Run:

```bash
godot --headless --path /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish res://tools/test_game_layout_task4.tscn
godot --headless --path /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish res://tools/test_ai_watch_task8.tscn
godot --headless --path /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish res://tools/test_undo_task5.tscn
godot --headless --path /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish res://tools/test_replay_task6.tscn
godot --headless --path /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish res://tools/test_rules_card_selector_task1.tscn
godot --headless --path /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish res://tools/test_setup_rules_task2.tscn
godot --headless --path /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish res://tools/test_ai_lab_rules_task3.tscn
```

Expected:
- `GAME_LAYOUT_TASK4_TESTS PASS`
- `AI_WATCH_TASK8_TESTS PASS`
- `UNDO_TASK5_TESTS PASS`
- `REPLAY_TASK6_TESTS PASS`
- `RULES_CARD_SELECTOR_TASK1_TESTS PASS`
- `SETUP_RULES_TASK2_TESTS PASS`
- `AI_LAB_RULES_TASK3_TESTS PASS`
- Linux `gomoku_neural.gdextension` warning is expected and not a failure.

- [ ] **Step 4: Run Chinese-only and whitespace checks**

Run:

```bash
grep -R "Renju" -n /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish/scenes /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish/project.godot
git -C /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish diff --check
```

Expected:
- `grep` finds no `Renju` matches; exit code 1 is expected.
- `git diff --check` has no output and exits 0.

- [ ] **Step 5: Token-scan committed/uncommitted diff before public push**

Run:

```bash
git -C /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish diff --cached -- .
git -C /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish diff -- . | grep -E "(ghp_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|-----BEGIN (RSA|OPENSSH|EC|DSA) PRIVATE KEY-----|AuthKey_[A-Z0-9]{10}\.p8)"
```

Expected: token scan has no matches; grep exit code 1 is expected.

- [ ] **Step 6: Request final code review**

Use `superpowers:requesting-code-review` / `superpowers:code-reviewer` with this context:

```text
Final review for Pro Max iPhone portrait UI redesign. Requirements: large iPhone/Pro Max portrait is primary target; gameplay board is near-full-width and centered around 396–404px; top game info is centered and readable; bottom actions are full-width large phone buttons; main menu/local setup/AI setup/AI Lab are no longer tiny centered desktop panels and use full-width phone controls; small iPhones do not overflow; iPad/macOS horizontal layout is preserved; Chinese-only UI; no Renju text. Review all changed scene/script/test files.
```

Fix Critical or Important findings and rerun relevant tests.

- [ ] **Step 7: Update progress for commit readiness**

Set:

```markdown
**Status:** READY_TO_FINISH_PROMAX_PORTRAIT_UI
**Current task:** Pro Max iPhone portrait UI redesign locally verified and reviewed.
**Next action:** Finish branch following finishing-branch flow; preserve `/home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish` until TestFlight/device validation passes or user explicitly approves cleanup.
```

Add verification rows for every command actually run.

- [ ] **Step 8: Commit any remaining intended files**

If Task 2 and Task 4 already committed all implementation changes, commit only the final progress update. Otherwise stage only intended files:

```bash
git -C /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish status --short
git -C /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish add docs/superpowers/progress/offline-ux-polish-progress.md tools/test_iphone_portrait_ui_task.gd tools/test_iphone_portrait_menu_ui_task.gd tools/test_iphone_portrait_menu_ui_task.tscn scenes/game/game.gd scenes/game/game.tscn scenes/main_menu/main_menu.gd scenes/main_menu/main_menu.tscn scenes/local_setup/local_setup.gd scenes/local_setup/local_setup.tscn scenes/ai_setup/ai_setup.gd scenes/ai_setup/ai_setup.tscn scenes/ai_lab/ai_lab.gd scenes/ai_lab/ai_lab.tscn
git -C /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish commit -m "fix: redesign iPhone portrait UI for Pro Max"
```

If any listed file is unchanged, omit it from `git add`. Never use blanket staging.

- [ ] **Step 9: Finishing branch flow**

Use `superpowers:finishing-a-development-branch` after final verification. Because the user has established a default push preference, merge/push may be appropriate, but still preserve the offline UX worktree until device validation passes or the user explicitly approves cleanup.

Before any public push, rerun the token scan over the exact diff being pushed.

---

## Self-Review Notes

- Spec coverage: gameplay Pro Max board/status/actions are covered by Tasks 1–2; menu/setup phone layouts are covered by Tasks 3–4; horizontal preservation, no Renju, token scan, reviews, and worktree preservation are covered by Task 5.
- Placeholder scan: no `TBD`, `TODO`, or unspecified test steps remain; code snippets and exact commands are provided.
- Type consistency: helper names use `_phone_*` for menu/setup scripts and `_portrait_*` for gameplay, matching the existing gameplay naming style and avoiding cross-file dependencies.
