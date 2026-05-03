# Progress: Offline UX Polish

**Plan:** `docs/superpowers/plans/2026-05-03-promax-portrait-ui.md`
**Status:** MERGED_PROMAX_PORTRAIT_UI_TO_MAIN
**Workflow:** subagent-driven-development
**Branch:** `main`
**Worktree:** `/home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish` preserved for device validation
**Last updated:** 2026-05-03 06:55 UTC
**Last known commit:** `10cae3f`
**Current task:** Task 5 — Merged Pro Max portrait UI branch to main after verification.
**Next action:** Commit this merge checkpoint, rerun token scan immediately before public push, push `origin main`, dispatch TestFlight, and preserve the worktree until device validation or explicit cleanup approval.

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
| Pro Max portrait UI Task 1 — gameplay RED tests | COMPLETE | none | RED run produced intended Pro Max gameplay assertion failure; diff --check passed. | Primary validation target is 430×932 / 440×956, with 375/390 compatibility. |
| Pro Max portrait UI Task 2 — gameplay layout implementation | COMPLETE | `544edb1` | Focused GREEN and regressions passed; spec/code-quality reviews approved. | `scenes/game/game.gd` now uses content-width portrait rules for large iPhones while preserving small-phone containment and horizontal layout. |
| Pro Max portrait UI Task 3 — menu/setup RED tests | COMPLETE | none | RED run still produces intended menu/setup phone layout assertion failure after review fixes; diff --check passed. | Code-quality fixes: containment now respects `is_visible_in_tree()` and Task 4 plan stacks color buttons full-width. |
| Pro Max portrait UI Task 4 — menu/setup layout implementation | COMPLETE | `5d2c689` | Focused menu/setup test, setup regressions, resize RED/GREEN checks, code reviews, and diff --check passed. | Full-width phone portrait controls implemented without navigation/rules behavior changes; horizontal resize restoration covered. |

---

## Current Handoff

**Last completed safe point:** Merge commit `10cae3f` brought Pro Max portrait gameplay/menu/setup UI into main after merged-result verification passed.

**In progress:** Merge checkpoint is unstaged and should be committed before public push.

**Blockers/questions:** None known. The preserved worktree still has untracked `.superpowers/` scratch and must remain untouched. The canonical main checkout still has unrelated training-script changes, so never use blanket staging.

**Next exact action:** Commit this merge checkpoint, rerun token scan immediately before public push, push `origin main`, dispatch TestFlight, then preserve the worktree until device validation or explicit cleanup approval.

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
| Pro Max portrait UI Task 1 | Spec compliance | APPROVED | subagent `aefbabf265ede33a6` | Pro Max plan exists in worktree, progress points to it, and gameplay RED tests meet Task 1 requirements. | Proceed to code quality review. |
| Pro Max portrait UI Task 1 | Code quality | APPROVED | subagent `a68edcf3f9fcff377` | RED failure is meaningful; no critical/important issues. Minor cleanup/checklist notes are non-blocking. | Proceed to Task 2 implementation. |
| Pro Max portrait UI Task 2 | Spec compliance | APPROVED | subagent `a84753ceda955437f` | Gameplay layout meets Pro Max sizing, small-phone containment, horizontal preservation, and verification requirements. | Proceed to code quality review. |
| Pro Max portrait UI Task 2 | Code quality | APPROVED | subagent `abaf0933706e3bb21` | No critical/important issues. Minor stale plan checklist and unused constant notes are non-blocking. | Commit gameplay slice, then proceed to Task 3. |
| Pro Max menu/setup RED Task 3 | Code quality fix | VERIFIED | current agent | Fixed Important findings: visible-control traversal now stops at hidden Control parents via `is_visible_in_tree()`, and Task 4 AI setup plan uses full-width stacked color buttons. | RED remains meaningful; no production layout changes. |
| Pro Max menu/setup RED Task 3 remaining review fix | VERIFIED | current agent | Added `OnlineButton`/`QuitButton` to main-menu RED coverage; corrected Task 4 AI Lab replay button and main-menu status label paths. | RED remains meaningful; no production layout changes. |
| Pro Max menu/setup RED Task 3 | Spec compliance | APPROVED | subagent `abc544e3718a8be41` | Focused menu/setup RED test meets Task 3 requirements and records intended failure evidence. | Proceed to code quality review. |
| Pro Max menu/setup RED Task 3 | Code quality | APPROVED_AFTER_FIX | subagent `a4e85a780c8c672c0` | Initial hidden-parent traversal, color-button plan mismatch, coverage, and path issues fixed; no remaining findings. | Proceed to Task 4 implementation. |
| Pro Max menu/setup Task 4 | Spec compliance | APPROVED | subagent `aa85d3ff9c02ee909` | Main menu, local setup, AI setup, AI Lab phone portrait sizing meets approved target; no Critical/Important findings. | Proceed to code-quality review. |
| Pro Max menu/setup Task 4 | Code quality | CHANGES_REQUIRED | subagent `a0a91c463c8902a59` | Important: portrait layout mutations are not fully restored when resizing back to horizontal. | Added RED resize-restoration test, fixed cleanup, reran focused/regression tests. |
| Pro Max menu/setup Task 4 review fix | Implementation | VERIFIED | current agent | RED reproduced stale phone minimum widths after portrait-to-horizontal resize; GREEN passes after restoring mutated controls in non-phone branches. | Re-review found remaining AI setup size-flag/visible-stack gap. |
| Pro Max menu/setup Task 4 review fix | Code quality re-review | CHANGES_REQUIRED | subagent `aeb4e4322df1d4380` | Important: AI setup still leaves portrait button `SIZE_EXPAND_FILL` and visible empty phone stacks after horizontal resize. | Strengthened test and reset AI setup size flags/phone stack visibility. |
| Pro Max menu/setup Task 4 AI setup restore fix | Implementation | VERIFIED | current agent | RED failed on AI setup button `SIZE_EXPAND_FILL` and visible phone stacks; GREEN passes after restoring flags and hiding phone stacks. | Targeted code-quality re-review approved. |
| Pro Max menu/setup Task 4 AI setup restore fix | Code quality re-review | APPROVED | subagent `a2c639d63f121781e` | No Critical/Important findings; reran focused menu test, setup rules regression, and diff check. | Proceed to final Task 4 verification and commit intended files only. |

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
| 2026-05-03 Task 4 disabled-button follow-up RED | `godot --headless --path /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish res://tools/test_iphone_portrait_ui_task.tscn` | RED FAIL | Intended new assertion failed: `UndoButton should have a portrait disabled style override`; Linux `gomoku_neural` warning expected. |
| 2026-05-03 Task 4 disabled-button follow-up GREEN | `godot --headless --path /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish res://tools/test_iphone_portrait_ui_task.tscn` | PASS | `IPHONE_PORTRAIT_UI_TASK_TESTS PASS`; Linux `gomoku_neural` warning expected. |
| 2026-05-03 Task 4 disabled-button follow-up | `godot --headless --path /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish res://tools/test_ai_watch_task8.tscn` | PASS | `AI_WATCH_TASK8_TESTS PASS`; Linux `gomoku_neural` warning expected. |
| 2026-05-03 Task 4 disabled-button follow-up | `git -C /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish diff --check -- scenes/game/game.gd tools/test_iphone_portrait_ui_task.gd docs/superpowers/progress/offline-ux-polish-progress.md` | PASS | No whitespace errors. |
| 2026-05-03 Pro Max gameplay RED | `godot --headless --path /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish res://tools/test_iphone_portrait_ui_task.tscn` | RED FAIL | Intended Pro Max portrait assertion failed before implementation: `UndoButton Pro Max minimum height should be at least 54.0`. Linux `gomoku_neural` warning expected. |
| 2026-05-03 Pro Max gameplay RED | `git -C /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish diff --check -- tools/test_iphone_portrait_ui_task.gd docs/superpowers/progress/offline-ux-polish-progress.md` | PASS | No whitespace errors. |
| 2026-05-03 Pro Max gameplay layout | `godot --headless --path /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish res://tools/test_iphone_portrait_ui_task.tscn` | PASS | `IPHONE_PORTRAIT_UI_TASK_TESTS PASS`; Linux `gomoku_neural` warning expected. |
| 2026-05-03 Pro Max gameplay layout | `godot --headless --path /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish res://tools/test_game_layout_task4.tscn` | PASS | `GAME_LAYOUT_TASK4_TESTS PASS`; Linux `gomoku_neural` warning expected. |
| 2026-05-03 Pro Max gameplay layout | `godot --headless --path /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish res://tools/test_ai_watch_task8.tscn` | PASS | `AI_WATCH_TASK8_TESTS PASS`; Linux `gomoku_neural` warning expected. |
| 2026-05-03 Pro Max gameplay layout | `git -C /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish diff --check -- scenes/game/game.gd scenes/game/game.tscn tools/test_iphone_portrait_ui_task.gd docs/superpowers/progress/offline-ux-polish-progress.md docs/superpowers/plans/2026-05-03-promax-portrait-ui.md` | PASS | No whitespace errors. |
| 2026-05-03 Pro Max menu/setup RED | `godot --headless --path /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish res://tools/test_iphone_portrait_menu_ui_task.tscn` | RED FAIL | Intended phone menu/setup layout assertion failed before implementation: `res://scenes/local_setup/local_setup.tscn StartButton outside (430, 932): [P: (-5, 562), S: (440, 62)]`. Linux `gomoku_neural` warning expected. |
| 2026-05-03 Pro Max menu/setup RED | `git -C /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish diff --check -- tools/test_iphone_portrait_menu_ui_task.gd tools/test_iphone_portrait_menu_ui_task.tscn docs/superpowers/progress/offline-ux-polish-progress.md` | PASS | No whitespace errors. |
| 2026-05-03 Pro Max menu/setup review fix | `godot --headless --path /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish res://tools/test_iphone_portrait_menu_ui_task.tscn` | RED FAIL | First exact failure after review fix: `res://scenes/local_setup/local_setup.tscn StartButton outside (430, 932): [P: (-5, 562), S: (440, 62)]`. Linux `gomoku_neural` warning expected. |
| 2026-05-03 Pro Max menu/setup review fix | `git -C /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish diff --check -- tools/test_iphone_portrait_menu_ui_task.gd tools/test_iphone_portrait_menu_ui_task.tscn docs/superpowers/progress/offline-ux-polish-progress.md docs/superpowers/plans/2026-05-03-promax-portrait-ui.md` | PASS | No whitespace errors. |
| 2026-05-03 Pro Max menu/setup layout | `godot --headless --path /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish res://tools/test_iphone_portrait_menu_ui_task.tscn` | PASS | `IPHONE_PORTRAIT_MENU_UI_TASK_TESTS PASS`; Linux `gomoku_neural` warning expected. |
| 2026-05-03 Pro Max menu/setup layout | `godot --headless --path /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish res://tools/test_rules_card_selector_task1.tscn` | PASS | `RULES_CARD_SELECTOR_TASK1_TESTS PASS`; Linux `gomoku_neural` warning expected. |
| 2026-05-03 Pro Max menu/setup layout | `godot --headless --path /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish res://tools/test_setup_rules_task2.tscn` | PASS | `SETUP_RULES_TASK2_TESTS PASS`; Linux `gomoku_neural` warning expected. |
| 2026-05-03 Pro Max menu/setup layout | `godot --headless --path /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish res://tools/test_ai_lab_rules_task3.tscn` | PASS | `AI_LAB_RULES_TASK3_TESTS PASS`; Linux `gomoku_neural` warning expected. |
| 2026-05-03 Pro Max menu/setup layout | `git -C /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish diff --check -- scenes/main_menu scenes/local_setup scenes/ai_setup scenes/ai_lab tools/test_iphone_portrait_menu_ui_task.gd tools/test_iphone_portrait_menu_ui_task.tscn docs/superpowers/progress/offline-ux-polish-progress.md docs/superpowers/plans/2026-05-03-promax-portrait-ui.md` | PASS | No whitespace errors. |
| 2026-05-03 Pro Max menu/setup resize restoration RED | `godot --headless --path /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish res://tools/test_iphone_portrait_menu_ui_task.tscn` | RED FAIL | Intended failures showed phone `custom_minimum_size.x=396` persisted after resizing to 932×430; Linux `gomoku_neural` warning expected. |
| 2026-05-03 Pro Max menu/setup resize restoration GREEN | `godot --headless --path /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish res://tools/test_iphone_portrait_menu_ui_task.tscn` | PASS | `IPHONE_PORTRAIT_MENU_UI_TASK_TESTS PASS` after restoring portrait mutations in non-phone branches; Linux `gomoku_neural` warning expected. |
| 2026-05-03 Pro Max menu/setup resize restoration | `godot --headless --path /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish res://tools/test_rules_card_selector_task1.tscn` | PASS | `RULES_CARD_SELECTOR_TASK1_TESTS PASS`; Linux `gomoku_neural` warning expected. |
| 2026-05-03 Pro Max menu/setup resize restoration | `godot --headless --path /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish res://tools/test_setup_rules_task2.tscn` | PASS | `SETUP_RULES_TASK2_TESTS PASS`; Linux `gomoku_neural` warning expected. |
| 2026-05-03 Pro Max menu/setup resize restoration | `godot --headless --path /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish res://tools/test_ai_lab_rules_task3.tscn` | PASS | `AI_LAB_RULES_TASK3_TESTS PASS`; Linux `gomoku_neural` warning expected. |
| 2026-05-03 Pro Max menu/setup resize restoration | `git -C /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish diff --check` | PASS | No whitespace errors. |
| 2026-05-03 Pro Max menu/setup AI restore RED | `godot --headless --path /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish res://tools/test_iphone_portrait_menu_ui_task.tscn` | RED FAIL | Intended failures: AI setup buttons kept `SIZE_EXPAND_FILL`, and `PhoneColorButtons`/`PhoneBottomButtons` remained visible after horizontal resize. |
| 2026-05-03 Pro Max menu/setup AI restore GREEN | `godot --headless --path /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish res://tools/test_iphone_portrait_menu_ui_task.tscn` | PASS | `IPHONE_PORTRAIT_MENU_UI_TASK_TESTS PASS` with stronger AI setup restore assertions; Linux `gomoku_neural` warning expected. |
| 2026-05-03 Pro Max menu/setup AI restore | `godot --headless --path /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish res://tools/test_setup_rules_task2.tscn` | PASS | `SETUP_RULES_TASK2_TESTS PASS`; Linux `gomoku_neural` warning expected. |
| 2026-05-03 Pro Max menu/setup AI restore | `git -C /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish diff --check` | PASS | No whitespace errors. |
| 2026-05-03 Pro Max menu/setup final Task 4 verification | `godot --headless --path /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish res://tools/test_iphone_portrait_menu_ui_task.tscn` | PASS | `IPHONE_PORTRAIT_MENU_UI_TASK_TESTS PASS`; Linux `gomoku_neural` warning expected. |
| 2026-05-03 Pro Max menu/setup final Task 4 verification | `godot --headless --path /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish res://tools/test_rules_card_selector_task1.tscn` | PASS | `RULES_CARD_SELECTOR_TASK1_TESTS PASS`; Linux `gomoku_neural` warning expected. |
| 2026-05-03 Pro Max menu/setup final Task 4 verification | `godot --headless --path /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish res://tools/test_setup_rules_task2.tscn` | PASS | `SETUP_RULES_TASK2_TESTS PASS`; Linux `gomoku_neural` warning expected. |
| 2026-05-03 Pro Max menu/setup final Task 4 verification | `godot --headless --path /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish res://tools/test_ai_lab_rules_task3.tscn` | PASS | `AI_LAB_RULES_TASK3_TESTS PASS`; Linux `gomoku_neural` warning expected. |
| 2026-05-03 Pro Max menu/setup final Task 4 verification | `git -C /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish diff --check` | PASS | No whitespace errors. |
| 2026-05-03 Pro Max portrait branch final verification | `godot --headless --path /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish res://tools/test_iphone_portrait_ui_task.tscn` | PASS | `IPHONE_PORTRAIT_UI_TASK_TESTS PASS`; Linux `gomoku_neural` warning expected. |
| 2026-05-03 Pro Max portrait branch final verification | `godot --headless --path /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish res://tools/test_iphone_portrait_menu_ui_task.tscn` | PASS | `IPHONE_PORTRAIT_MENU_UI_TASK_TESTS PASS`; Linux `gomoku_neural` warning expected. |
| 2026-05-03 Pro Max portrait branch final verification | `godot --headless --path /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish res://tools/test_game_layout_task4.tscn` | PASS | `GAME_LAYOUT_TASK4_TESTS PASS`; Linux `gomoku_neural` warning expected. |
| 2026-05-03 Pro Max portrait branch final verification | `godot --headless --path /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish res://tools/test_ai_watch_task8.tscn` | PASS | `AI_WATCH_TASK8_TESTS PASS`; Linux `gomoku_neural` warning expected. |
| 2026-05-03 Pro Max portrait branch final verification | `godot --headless --path /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish res://tools/test_undo_task5.tscn` | PASS | `UNDO_TASK5_TESTS PASS`; expected invalid-history errors appear in output. |
| 2026-05-03 Pro Max portrait branch final verification | `godot --headless --path /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish res://tools/test_replay_task6.tscn` | PASS | `REPLAY_TASK6_TESTS PASS`; Linux `gomoku_neural` warning expected. |
| 2026-05-03 Pro Max portrait branch final verification | `godot --headless --path /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish res://tools/test_rules_card_selector_task1.tscn` | PASS | `RULES_CARD_SELECTOR_TASK1_TESTS PASS`; Linux `gomoku_neural` warning expected. |
| 2026-05-03 Pro Max portrait branch final verification | `godot --headless --path /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish res://tools/test_setup_rules_task2.tscn` | PASS | `SETUP_RULES_TASK2_TESTS PASS`; Linux `gomoku_neural` warning expected. |
| 2026-05-03 Pro Max portrait branch final verification | `godot --headless --path /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish res://tools/test_ai_lab_rules_task3.tscn` | PASS | `AI_LAB_RULES_TASK3_TESTS PASS`; Linux `gomoku_neural` warning expected. |
| 2026-05-03 Pro Max portrait branch final verification | `grep -R "Renju" -n /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish/scenes /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish/project.godot` | PASS | No matches; exit code 1 expected. |
| 2026-05-03 Pro Max portrait branch final verification | `git -C /home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish diff --check` | PASS | No whitespace errors. |
| 2026-05-03 Pro Max portrait branch final verification | token-pattern scan over `git diff main...HEAD` | PASS | No matches; grep exit code 1 expected. |

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
- `scenes/game/game.gd` — Chinese-only HUD suffix, viewport-based vertical layout helper, and WIP Pro Max-first gameplay portrait content-width sizing.
- `export_presets.cfg` — iOS portrait orientation booleans.
- `tools/test_game_layout_task4.gd` — layout predicate test.
- `tools/test_game_layout_task4.tscn` — layout test scene.
- `project.godot` — runtime iOS orientation set to sensor for device-specific plist restrictions.
- `.github/workflows/ios.yml` — patches exported iOS plist and validates final IPA orientation.
- `ios_plugin/scripts/patch_ios_orientation.py` — patches/validates iPhone portrait and iPad landscape plist entries.
- `ios_plugin/tests/test_patch_ios_orientation.py` — plist patch regression tests.
- `tools/test_ios_orientation_config.py` — project/workflow orientation configuration tests.
- `tools/test_iphone_portrait_ui_task.gd` — focused iPhone portrait gameplay readability test.
- `tools/test_iphone_portrait_ui_task.tscn` — focused iPhone portrait gameplay readability test scene.
- `tools/test_iphone_portrait_menu_ui_task.gd` — focused iPhone portrait menu/setup layout test.
- `tools/test_iphone_portrait_menu_ui_task.tscn` — focused iPhone portrait menu/setup test scene.
- `scenes/main_menu/main_menu.gd` — phone portrait main-menu content-width and button sizing.
- `scenes/local_setup/local_setup.gd` — phone portrait local setup content-width/rules/button sizing.
- `scenes/ai_setup/ai_setup.gd` — phone portrait AI setup content-width, stacked color/start/back buttons, and compact small-phone sizing.
- `scenes/ai_setup/ai_setup.tscn` — keeps stable bottom button path while script manages portrait stacking.
- `scenes/ai_lab/ai_lab.gd` — phone portrait AI Lab content-width, stacked action buttons/selectors, and compact small-phone sizing.
- `scenes/ai_lab/ai_lab.tscn` — uses script-managed flexible row hosts for portrait stacking.
