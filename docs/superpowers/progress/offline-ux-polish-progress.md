# Progress: Offline UX Polish

**Plan:** `docs/superpowers/plans/2026-05-02-offline-ux-polish.md`
**Status:** TESTFLIGHT_SUCCEEDED_PENDING_DEVICE_VALIDATION
**Workflow:** subagent-driven-development + test-driven-development
**Branch:** `main`
**Worktree:** `/home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish`
**Last updated:** 2026-05-03 03:05 UTC
**Last known commit:** `8b90682`
**Current task:** TestFlight workflow run `25268222929` succeeded for iPhone portrait gameplay UI redesign; final IPA plist verified iPhone portrait and iPad landscape orientations.
**Next action:** Ask user to validate iPhone portrait gameplay UI sizing/polish plus iPad/macOS layout on devices. Preserve worktree until validation or explicit cleanup approval.

---

## Recovery Instructions

1. Read this file.
2. Read the plan file.
3. Verify git state with `git status` and recent commits.
4. Verify listed test evidence if needed.
5. Continue from **Next action**.
6. Update this file before changing task/review/blocker state.

---

## Task Ledger

| Task | Status | Commit(s) | Verification | Notes |
|------|--------|-----------|--------------|-------|
| Task 1 — Add reusable rules card selector | COMPLETE | `95d04da`, `465d0da` | Focused selector test passed during task; code quality fix reviewed. | `Button.text` intentionally empty; selected checkmark lives in title labels. |
| Task 2 — Apply selector to local PvP and human-vs-AI setup | COMPLETE | `563ebdb`, `fe24d17` | Focused setup tests passed during task; AI setup layout guard added. | AI setup uses 2-column `%LevelGrid` to keep Level 6 visible. |
| Task 3 — Apply selector to AI Lab and rules copy | COMPLETE | `918b669` | Focused AI Lab/HUD test and regressions passed during task; reviews approved. | User-facing rules copy is Chinese-only. |
| Task 4 — Fix iPhone portrait activation | COMPLETE | `fe1a965`, `d31ed17` | `tools/test_game_layout_task4.tscn` PASS; parse check ran with known Linux GDExtension warning; spec and quality reviews approved. | Complete. |
| Task 5 — Refresh font subset and final local verification | COMPLETE | none | Font check PASS; focused tests PASS; regressions PASS; no Renju matches; token scan no matches; `git diff --check` PASS after progress-file whitespace fix; spec and quality reviews approved. | No font commit needed. |

---

## Current Handoff

**Last completed safe point:** TestFlight run `25268222929` succeeded for head SHA `b0f66833d6696daf86d261b05326617f978e7855`; downloaded artifact `/tmp/gomoku-testflight-25268222929/gomoku-main/gomoku.ipa` and verified final plist orientation arrays.

**In progress:** Waiting for target-device validation of the redesigned iPhone portrait gameplay UI and unchanged iPad/macOS horizontal layouts.

**Blockers/questions:** None known. The preserved worktree still has untracked `.superpowers/` scratch and must remain until target-device validation or explicit cleanup approval. The canonical main checkout still has unrelated training-script changes, so never use blanket staging.

**Next exact action:** Ask user to validate iPhone portrait gameplay UI sizing/polish plus iPad/macOS layout on devices; preserve worktree until validation or explicit cleanup approval.

---

## Review Ledger

| Task | Review Type | Status | Reviewer | Findings | Follow-up |
|------|-------------|--------|----------|----------|-----------|
| Task 1 | Spec compliance | APPROVED | subagent | Requirements met. | None. |
| Task 1 | Code quality | APPROVED_AFTER_FIX | subagent | Initial overlap/property-state issues fixed in `465d0da`. | None. |
| Task 2 | Spec compliance | APPROVED | subagent | Requirements met. | None. |
| Task 2 | Code quality | APPROVED_AFTER_FIX | subagent | Initial AI setup overflow fixed in `fe24d17`. | None. |
| Task 3 | Spec compliance | APPROVED | subagent | Requirements met. | None. |
| Task 3 | Code quality | APPROVED | subagent | No blocking issues. | None. |
| Task 4 | Spec compliance | APPROVED | subagent `a29d7654462c22c0a` | Implementation matches predicate, export orientation, test, and verification requirements. | None. |
| Task 4 | Code quality | APPROVED | subagent `a8225d6cab1910378` | No quality issues; noted `game.free()` cleanup is good test hygiene. | Commit cleanup/progress. |
| Task 5 | Spec compliance | APPROVED | subagent `a615dfa193e8fa96d` | Rechecked font coverage, no font changes, clean whitespace, no Renju matches, no token-shaped matches; accepted prior test evidence. | None. |
| Task 5 | Code quality | APPROVED | subagent `a58fb984641340b37` | Verification evidence sufficient; no font files changed; `.superpowers/` is not in branch diff but remains untracked scratch. | Stage only intended files; never use blanket staging. |
| Whole branch | Final code review | READY_WITH_NOTES | subagent `afac91ce03990545e` | No merge-blocking issues; minor stale progress metadata fixed after review. | Proceed to finishing/merge flow. |
| iPhone portrait UI sizing | Code quality | APPROVED_AFTER_TEST_STRENGTHENING | subagent `af2fdc8b2e6d73128` | No blockers. Important suggestion: assert rendered sizes/viewport containment, not just properties. | Strengthened test; found and fixed vertical height overflow. |
| iPhone portrait redesign Task 1 | Spec compliance | APPROVED | subagent `a9c295e3f24e1a808` | Strengthened 390×844 test covers board/status/actions width and centering, label centering, existing assertions, and meaningful RED failure. | Proceed to code quality review. |
| iPhone portrait redesign Task 1 | Code quality | APPROVED | subagent `ab76feb69754e1a22` | No critical/important issues; minor notes about explicit missing-node failures and pass-only cleanup are non-blocking. | Proceed to Task 2 vertical card hosts. |
| iPhone portrait redesign Task 2 | Spec compliance | APPROVED | subagent `a0846c20b762e1eb3` | Vertical status/actions card hosts and padding added; onready refs and vertical reparenting match plan; horizontal branch unchanged. | Proceed to code quality review. |
| iPhone portrait redesign Task 2 | Code quality | CHANGES_REQUIRED | subagent `a0734fabbcc1f5d72` | Card padding leaves only 338–342px inner width on 390px viewport, conflicting with full-width status/actions/button assertions after board width is fixed. | Reduce vertical-only margins/padding so inner content can still reach at least 350px. |
| iPhone portrait redesign Task 2 | Code quality re-review | APPROVED | subagent `a66df8d5061089054` | Padding fix leaves ~366px inner budget on 390px viewport; no critical/important issues. Minor stale handoff note addressed. | Proceed to Task 3 dynamic board sizing and full-width controls. |
| iPhone portrait redesign Task 3 | Spec compliance | APPROVED | subagent `a58632a233aba67a1` | Focused 390×844 test and parse smoke passed; dynamic board sizing, centered labels, full-width controls, and message-label height reclamation meet spec. | Proceed to code quality review. |
| iPhone portrait redesign Task 3 | Code quality | CHANGES_REQUIRED | subagent `a5171c902c8059977` | Persistent compressed portrait chrome across resizes, hard 350px board floor for short iPhones, and horizontal AI-watch button expand regression. | Fix idempotent chrome reset, responsive board floor/tests, and AI-watch horizontal sizing. |
| iPhone portrait redesign Task 3 follow-up | Implementation | VERIFIED | current agent | Fixed the three code-quality findings; extended tests for 375×667, 430×932, resize reset, and horizontal AI-watch expand-fill. | Ready for review; no commit made. |
| iPhone portrait redesign Task 3 follow-up | Spec compliance | APPROVED | subagent `a40f8a8fd16a6c32b` | Idempotent chrome reset, responsive board floor, horizontal AI-watch expand-fill, and extended viewport tests satisfy follow-up requirements. | Proceed to code quality re-review. |
| iPhone portrait redesign Task 3 follow-up | Code quality re-review | APPROVED | subagent `a0ede2b26eac3edf7` | Prior important issues fixed; focused portrait, AI-watch, parse smoke, and diff --check passed. Minor maintainability notes only. | Proceed to Task 4 vertical-only polish styling. |
| iPhone portrait redesign Task 4 | Implementation | VERIFIED | subagent `a221509556d69d591` | Vertical-only card/button StyleBox polish added with RED/GREEN style assertions; focused portrait, AI-watch, parse smoke, Renju scan, and diff --check passed. | Proceed to spec compliance review. |
| iPhone portrait redesign Task 4 | Spec compliance | APPROVED | subagent `a5348a397bc0f2207` | Style helpers and vertical-only card/button overrides meet requirements; horizontal override clearing and non-brittle style tests present. | Proceed to code quality review. |
| iPhone portrait redesign Task 4 | Code quality | APPROVED | subagent `a1b1a39811a559d07` | No critical/important issues; minor disabled-state consistency note followed up with TDD. | Add disabled override follow-up and verify. |
| iPhone portrait redesign Task 4 disabled follow-up | Code quality | APPROVED | subagent `a84048339ab14952f` | Disabled StyleBox override applies in portrait and is cleared in horizontal; TDD evidence accepted. | Proceed to final local verification. |
| iPhone portrait redesign Task 4 | Implementation | VERIFIED | subagent `a221509556d69d591` | Vertical-only card/button StyleBox polish added with RED/GREEN style assertions; focused portrait, AI-watch, parse smoke, Renju scan, and diff --check passed. | Proceed to spec compliance review. |
| iPhone portrait redesign Task 4 | Spec compliance | APPROVED | subagent `a5348a397bc0f2207` | Style helpers and vertical-only card/button overrides meet requirements; horizontal override clearing and non-brittle style tests present. | Proceed to code quality review. |
| iPhone portrait redesign Task 4 disabled-button follow-up | Implementation | VERIFIED | current agent | Added RED/GREEN coverage for portrait `UndoButton.disabled` style override and horizontal clearing, then added vertical-only disabled StyleBox to all action buttons. | No commit made. |

---

## Verification Evidence

| When | Command | Result | Notes |
|------|---------|--------|-------|
| 2026-05-02 before compaction | Task 1 focused tests and parse checks | PASS | Exact output not currently in this artifact. |
| 2026-05-02 before compaction | Task 2 focused tests and parse checks | PASS | Exact output not currently in this artifact. |
| 2026-05-02 before compaction | Task 3 focused tests, grep, parse checks | PASS | Exact output not currently in this artifact. |
| 2026-05-02 11:45 UTC | `git status --short --branch && git log --oneline -8` | Branch `offline-ux-polish`; latest `fe1a965`; one modified test file plus untracked `.superpowers/`. | Verification performed while resuming. |
| 2026-05-02 Task 5 | `python3 tools/generate_cjk_subset.py --check` | PASS | `cjk_subset.otf` covers 279 UI glyphs; no font files changed. |
| 2026-05-02 Task 5 | UX focused Godot tests | PASS | `RULES_CARD_SELECTOR_TASK1_TESTS PASS`, `SETUP_RULES_TASK2_TESTS PASS`, `AI_LAB_RULES_TASK3_TESTS PASS`, `GAME_LAYOUT_TASK4_TESTS PASS`. |
| 2026-05-02 Task 5 | Regression Godot tests and parse check | PASS | `AI_WATCH_TASK8_TESTS PASS`, `REPLAY_TASK6_TESTS PASS`, `UNDO_TASK5_TESTS PASS`; parse check only known Linux `gomoku_neural` warning. |
| 2026-05-02 Task 5 | `grep -R "Renju" -n scenes project.godot` | PASS | No matches; exit code 1. |
| 2026-05-02 Task 5 | token-shaped scan over `git diff main...HEAD` | PASS | No matches; grep exit code 1. |
| 2026-05-02 Task 5 | `git diff --check` | PASS | Initially blocked on progress-file trailing spaces; fixed by controller and re-run clean. |
| 2026-05-02 iOS portrait debug | Downloaded TestFlight run `25252306554` IPA and read `Payload/gomoku.app/Info.plist` | FAIL FOUND | iPhone orientations were `['UIInterfaceOrientationLandscapeLeft']`; iPad was `['UIInterfaceOrientationLandscapeRight']`. |
| 2026-05-02 iOS portrait debug | Godot 4.5 source inspection | ROOT CAUSE | iOS exporter/runtime read `display/window/handheld/orientation`; `orientation/*` preset keys are ignored. |
| 2026-05-02 iOS portrait fix | `python3 -m pytest ios_plugin/tests/test_patch_ios_orientation.py tools/test_ios_orientation_config.py -q` | PASS | 7 tests: plist patch, validation, framework plist guard, workflow order, runtime sensor setting, ignored preset-key removal, final IPA validation. |
| 2026-05-02 iOS portrait fix | Real IPA plist simulation with `patch_ios_orientation.py` | PASS | Patches iPhone to `Portrait` and iPad to both landscape orientations while preserving `UIDeviceFamily=[1,2]`. |
| 2026-05-02 iOS portrait fix | `godot --headless --path . res://tools/test_game_layout_task4.tscn` | PASS | Layout predicate still passes; Linux GDExtension warning remains expected. |
| 2026-05-02 iOS portrait UI sizing | New focused test harness `tools/test_iphone_portrait_ui_task.gd/.tscn` | PASS | Harness uses 390×844 `SubViewport`; RED failed on `%TurnLabel` font threshold, then strengthened rendered-size/viewport checks found vertical overflow; GREEN passes after height-constrained board sizing. |
| 2026-05-02 iOS portrait UI sizing | `godot --headless --path /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish res://tools/test_game_layout_task4.tscn` | PASS | Existing layout predicate test still passes; Linux `gomoku_neural` warning expected. |
| 2026-05-02 iOS portrait UI sizing | `godot --headless --path /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish res://tools/test_ai_watch_task8.tscn` | PASS | AI watch regression passed; Linux `gomoku_neural` warning expected. |
| 2026-05-02 iOS portrait UI sizing | `godot --headless --path /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish res://tools/test_undo_task5.tscn` | PASS | Undo regression passed; expected invalid-history test errors appear in output. |
| 2026-05-02 iOS portrait UI sizing | `godot --headless --path /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish res://tools/test_replay_task6.tscn` | PASS | Replay regression passed; Linux `gomoku_neural` warning expected. |
| 2026-05-02 iOS portrait UI sizing | `git diff --check` | PASS | No whitespace errors. |
| 2026-05-02 iOS portrait UI sizing | Merged main verification suite | PASS | `IPHONE_PORTRAIT_UI_TASK_TESTS`, `GAME_LAYOUT_TASK4_TESTS`, `REPLAY_TASK6_TESTS`, `UNDO_TASK5_TESTS`, `AI_WATCH_TASK8_TESTS`, and `git diff --check` passed on main after merge; Linux `gomoku_neural` warning expected. |
| 2026-05-02 iOS portrait UI sizing | token-shaped scan over `git diff origin/main...HEAD` before push | PASS | No matches; scan covered committed diff for `fd16f48` push. |
| 2026-05-02 iOS portrait UI sizing | `git push origin main` | PASS | Pushed `4a03b9b..fd16f48` then checkpoint `fd16f48..bb2b95c` to GitHub. |
| 2026-05-02 iOS portrait UI sizing | `gh workflow run "CD — TestFlight (iOS)" --repo jasonhorga/gomoku --ref main` / `gh run watch 25256049033` | PASS | Run `25256049033` succeeded for head SHA `bb2b95cb9137927d521f7fe71fbe945601d1cb27`; background monitor task `b89y65gc6` exited 0. |
| 2026-05-03 00:49 UTC | `godot --headless --path /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish res://tools/test_iphone_portrait_ui_task.tscn` | RED FAIL | Intended new assertion failed: `BoardFrame should be wide enough for iPhone portrait (width=268.0, min=350.0, rect=[P: (61, 324), S: (268, 268)])`. Linux `gomoku_neural` warning expected. |
| 2026-05-03 Task 2 vertical card hosts | `godot --headless --path /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish --quit` | PASS | Parse/smoke passed with expected Linux `gomoku_neural` warning. |
| 2026-05-03 Task 2 vertical card hosts | `godot --headless --path /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish res://tools/test_iphone_portrait_ui_task.tscn` | RED FAIL | Still fails only on intended BoardFrame width assertion (`width=268.0, min=350.0`); no missing-node or parse errors. |
| 2026-05-03 Task 2 code review fix | `godot --headless --path /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish --quit` | PASS | Parse/smoke passed with expected Linux `gomoku_neural` warning. |
| 2026-05-03 Task 2 code review fix | `godot --headless --path /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish res://tools/test_iphone_portrait_ui_task.tscn` | RED FAIL | Still fails only on intended BoardFrame width assertion (`width=268.0, min=350.0`); no missing-node or parse errors. |
| 2026-05-03 Task 3 follow-up RED | `godot --headless --path /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish res://tools/test_iphone_portrait_ui_task.tscn` | RED FAIL | New short-portrait coverage failed on `VerticalLayout outside (375, 667)` before implementation; Linux `gomoku_neural` warning expected. |
| 2026-05-03 Task 3 follow-up | `godot --headless --path /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish res://tools/test_iphone_portrait_ui_task.tscn` | PASS | Extended 390×844, 375×667, 430×932, resize reset, and horizontal AI-watch expand-fill assertions passed; Linux `gomoku_neural` warning expected. |
| 2026-05-03 Task 3 follow-up | `godot --headless --path /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish res://tools/test_ai_watch_task8.tscn` | PASS | AI-watch regression passed after preserving Pause/Step/Auto `SIZE_EXPAND_FILL`; Linux `gomoku_neural` warning expected. |
| 2026-05-03 Task 3 follow-up | `godot --headless --path /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish --quit` | PASS | Parse/smoke passed with expected Linux `gomoku_neural` warning. |
| 2026-05-03 Task 3 follow-up | `git -C /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish diff --check -- scenes/game/game.gd tools/test_iphone_portrait_ui_task.gd docs/superpowers/progress/offline-ux-polish-progress.md` | PASS | No whitespace errors. |
| 2026-05-03 Task 4 vertical-only polish RED | `godot --headless --path /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish res://tools/test_iphone_portrait_ui_task.tscn` | RED FAIL | Intended new style assertion failed on missing `VerticalStatusCard` portrait panel override; Linux `gomoku_neural` warning expected. |
| 2026-05-03 Task 4 vertical-only polish | `godot --headless --path /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish res://tools/test_iphone_portrait_ui_task.tscn` | PASS | Portrait card/button style assertions, horizontal style-clear assertions, and existing portrait sizing checks passed; Linux `gomoku_neural` warning expected. |
| 2026-05-03 Task 4 vertical-only polish | `godot --headless --path /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish res://tools/test_ai_watch_task8.tscn` | PASS | AI-watch regression passed; Linux `gomoku_neural` warning expected. |
| 2026-05-03 Task 4 vertical-only polish | `godot --headless --path /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish --quit` | PASS | Parse/smoke passed with expected Linux `gomoku_neural` warning. |
| 2026-05-03 Task 4 vertical-only polish | `grep -R "Renju" -n /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish/scenes /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish/project.godot` | PASS | No matches; exit code 1 expected. |
| 2026-05-03 Task 4 vertical-only polish | `git -C /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish diff --check -- scenes/game/game.gd tools/test_iphone_portrait_ui_task.gd docs/superpowers/progress/offline-ux-polish-progress.md` | PASS | No whitespace errors. |
| 2026-05-03 final merge verification | Merged main focused/regression suite | PASS | `IPHONE_PORTRAIT_UI_TASK_TESTS`, `GAME_LAYOUT_TASK4_TESTS`, `AI_WATCH_TASK8_TESTS`; merge diff whitespace and token scan passed. |
| 2026-05-03 TestFlight redesign | `gh workflow run "CD — TestFlight (iOS)" --repo jasonhorga/gomoku --ref main` / `gh run watch 25268222929` | PASS | Run `25268222929` succeeded for head SHA `b0f66833d6696daf86d261b05326617f978e7855`. |
| 2026-05-03 TestFlight redesign | Downloaded final IPA artifact and inspected `Payload/gomoku.app/Info.plist` | PASS | `UIDeviceFamily=[1,2]`; iPhone `['UIInterfaceOrientationPortrait']`; iPad `['UIInterfaceOrientationLandscapeLeft', 'UIInterfaceOrientationLandscapeRight']`. |
| 2026-05-03 Task 4 disabled-button follow-up RED | `godot --headless --path /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish res://tools/test_iphone_portrait_ui_task.tscn` | RED FAIL | Intended new assertion failed: `UndoButton should have a portrait disabled style override`; Linux `gomoku_neural` warning expected. |
| 2026-05-03 Task 4 disabled-button follow-up GREEN | `godot --headless --path /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish res://tools/test_iphone_portrait_ui_task.tscn` | PASS | `IPHONE_PORTRAIT_UI_TASK_TESTS PASS`; Linux `gomoku_neural` warning expected. |
| 2026-05-03 Task 4 disabled-button follow-up | `godot --headless --path /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish res://tools/test_ai_watch_task8.tscn` | PASS | `AI_WATCH_TASK8_TESTS PASS`; Linux `gomoku_neural` warning expected. |
| 2026-05-03 Task 4 disabled-button follow-up | `git -C /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish diff --check -- scenes/game/game.gd tools/test_iphone_portrait_ui_task.gd docs/superpowers/progress/offline-ux-polish-progress.md` | PASS | No whitespace errors. |

---

## Decisions

| When | Decision | Reason |
|------|----------|--------|
| 2026-05-02 | Use unified card selector across Local PvP, human-vs-AI, and AI Lab. | User wanted forbidden-rules controls to remain consistent. |
| 2026-05-02 | Default offline setup screens to `禁手规则`. | User chose default forbidden rules. |
| 2026-05-02 | Force/support iPhone portrait while leaving iPad/macOS horizontal. | User chose forced iPhone portrait. |
| 2026-05-02 | Do not use visual companion further. | User said not to use visual. |
| 2026-05-02 | Keep `offline-ux-polish` worktree after merge/push until target-device validation or explicit cleanup approval. | User corrected lifecycle expectation. |

---

## Files Changed So Far

- `docs/superpowers/specs/2026-05-02-offline-ux-polish-design.md` — approved design spec.
- `docs/superpowers/plans/2026-05-02-offline-ux-polish.md` — execution plan.
- `docs/superpowers/progress/offline-ux-polish-progress.md` — durable recovery state.
- `scenes/common/rules_card_selector.gd` — reusable rules selector.
- `scenes/common/rules_card_selector.tscn` — selector scene.
- `tools/test_rules_card_selector_task1.gd` — selector focused test.
- `tools/test_rules_card_selector_task1.tscn` — selector test scene.
- `scenes/local_setup/local_setup.gd` — local PvP reads `RulesSelector`.
- `scenes/local_setup/local_setup.tscn` — polished local setup panel.
- `scenes/ai_setup/ai_setup.gd` — human-vs-AI reads `RulesSelector`.
- `scenes/ai_setup/ai_setup.tscn` — human-vs-AI selector and layout guard.
- `tools/test_setup_rules_task2.gd` — setup selector/layout test.
- `tools/test_setup_rules_task2.tscn` — setup test scene.
- `scenes/ai_lab/ai_lab.gd` — AI Lab reads/disables `RulesSelector`.
- `scenes/ai_lab/ai_lab.tscn` — AI Lab selector.
- `tools/test_ai_lab_rules_task3.gd` — AI Lab/HUD copy test.
- `tools/test_ai_lab_rules_task3.tscn` — AI Lab test scene.
- `scenes/game/game.gd` — Chinese-only HUD suffix and viewport-based vertical layout helper.
- `export_presets.cfg` — iOS portrait orientation booleans.
- `tools/test_game_layout_task4.gd` — layout predicate test.
- `tools/test_game_layout_task4.tscn` — layout test scene.
- `project.godot` — runtime iOS orientation set to sensor for device-specific plist restrictions.
- `.github/workflows/ios.yml` — patches exported iOS plist and validates final IPA orientation.
- `ios_plugin/scripts/patch_ios_orientation.py` — patches/validates iPhone portrait and iPad landscape plist entries.
- `ios_plugin/tests/test_patch_ios_orientation.py` — plist patch regression tests.
- `tools/test_ios_orientation_config.py` — project/workflow orientation configuration tests.
- `tools/test_iphone_portrait_ui_task.gd` — WIP focused iPhone portrait gameplay readability test.
- `tools/test_iphone_portrait_ui_task.tscn` — WIP focused iPhone portrait gameplay readability test scene.
