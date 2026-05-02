# Progress: Offline UX 2.0

**Plan:** `docs/superpowers/plans/2026-05-01-offline-ux-2.md`  
**Status:** COMPLETE  
**Workflow:** subagent-driven-development  
**Branch:** `renju-mode`  
**Worktree:** `/home/ubuntu/.config/superpowers/worktrees/gomoku/renju-mode`  
**Last updated:** 2026-05-02 05:30 UTC  
**Last known commit:** `d7140c4`  
**Current task:** Branch finishing — sync to Google Drive checkout and GitHub  
**Next action:** Merge completed branch into the primary Google Drive checkout, push `main`, and leave exported session text files untracked.

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
| Task 1 — Font subset automation and Chinese coverage | COMPLETE | `e513e9b`, `15328c3` | `python3 tools/generate_cjk_subset.py --check` PASS; `python3 -m py_compile tools/generate_cjk_subset.py` PASS; ASCII cmap verification PASS | Spec review and code-quality review approved. |
| Task 2 — Local PvP and AI Lab explicit Renju setup | COMPLETE | `bf3c95f`, `86fad23` | `godot --headless --path . --quit` loaded with no parse errors, but Linux font loader reported `cjk_subset.otf` custom-font warning; static checks passed after fix. | Spec review and code-quality re-review approved. |
| Task 3 — Block human forbidden moves instead of ending the game | COMPLETE | `9a090fa` | TDD Godot scripts PASS; `godot --headless --path . --quit` PASS_WITH_WARNING; `git diff --check` PASS | Spec review and code-quality review approved. |
| Task 4 — Responsive game layout and explicit controls | COMPLETE | `ad5ecf3`, `dfc2b66` | `godot --headless --path . --quit` PASS_WITH_WARNING; static Task 4 check PASS; `git diff --check` PASS | Spec review and code-quality re-review approved. |
| Task 5 — Undo support for local PvP and human-vs-AI | COMPLETE | `18f3bd4`, `d620450`, `6f9567a`, `bb31c9e`, `c788fbd`, `f839be5` | `godot --headless --path . --quit` PASS; `tools/test_undo_task5.tscn` PASS; `git diff --check` PASS | Spec review and final code-quality re-review approved. |
| Task 6 — Replay for finished game and last AI Lab batch game | COMPLETE | `47a1153`, `54bd51e` | Replay tests PASS; Task 5 undo tests PASS; `godot --headless --path . --quit` PASS_WITH_EXPECTED_WARNINGS; `git diff --check` PASS | Spec review and code-quality re-review approved. |
| Task 7 — Board replay rendering support | COMPLETE | `8e3d0f3` | Parse PASS; replay tests PASS; undo tests PASS; diff checks PASS; token scan PASS | Spec review and code-quality review approved. |
| Task 8 — AI Lab watch pause and step controls | COMPLETE | `ab5c0b5`, `29408ac`, `d781165` | AI watch tests PASS; undo tests PASS; replay tests PASS; parse PASS; diff checks PASS | Spec review and final code-quality re-review approved. |
| Task 9 — Final integration verification and release readiness | COMPLETE | `d7140c4` | Font check PASS; Godot parse PASS; AI watch/replay/undo tests PASS; diff check PASS; token scan PASS; final whole-branch review APPROVED | Local final verification and whole-branch review complete; target-device release checks still required on Mac/iPhone/iPad. |

Statuses: NOT_STARTED, IN_PROGRESS, IMPLEMENTED, SPEC_REVIEWED, QUALITY_REVIEWED, COMPLETE, BLOCKED, SKIPPED.

---

## Current Handoff

**Last completed safe point:** Task 9 complete at commit `d7140c4`; final whole-branch review approved.  

**In progress:** Branch finishing — sync completed work to the primary Google Drive checkout and GitHub.  

**Blockers/questions:** No local blockers. Linux Godot reports expected missing `gomoku_neural` GDExtension warnings because the Swift plugin targets iOS/macOS. Target-device release checks are still required on Mac/iPhone/iPad.  

**Next exact action:** Merge `renju-mode` into the primary Google Drive checkout, push `main`, then run Mac/iPhone/iPad release verification before shipping.

---

## Review Ledger

| Task | Review Type | Status | Reviewer | Findings | Follow-up |
|------|-------------|--------|----------|----------|-----------|
| Task 1 | Spec compliance | APPROVED | subagent a4e0bd08d59fa5e21 | Matches Task 1 plan; current check passes; old font failed with missing 禁/规/则/，; commit contains only Task 1 files. | None |
| Task 1 | Code quality | CHANGES_REQUIRED | subagent a7fc6fe08ef17088a | Important: regenerated font dropped ASCII/digits/space used by UI; `Path.rglob` pruning code has no effect. | Fixed in `15328c3`; re-review approved. |
| Task 1 | Code quality re-review | APPROVED | subagent aa26c07e0dd63950a | ASCII coverage and real pruning verified; no critical or important findings. | None |
| Task 2 | Spec compliance | APPROVED | subagent a0d88b2857df6fc50 | Local setup, AI Lab explicit rules, GameRecord ruleset, and Task 2 file scope match plan; replay placeholder acceptable until Task 6. | None |
| Task 2 | Code quality | CHANGES_REQUIRED | subagent a2141e28005b130a9 | Important: GameManager-saved records still default to free; AI Lab Renju checkbox can change mid-batch causing mixed-rules stats. | Fixed in `86fad23`; re-review approved. |
| Task 2 | Code quality re-review | APPROVED | subagent a2e2bf8bda9781876 | Ruleset persistence and stable AI Lab batch rules verified; no critical or important findings. | None |
| Task 3 | Spec compliance | APPROVED | subagent a894762c31fb4e319 | Forbidden human moves are rejected with message; MessageLabel wired; obsolete forbidden-win branch removed; Task 3 files only. | None |
| Task 3 | Code quality | APPROVED | subagent ad1aa1a573e74fa7b | No critical/important findings; only non-blocking suggestions about message-token clearing and AI Lab invalid AI fallback. | None |
| Task 4 | Spec compliance | APPROVED | subagent a0abc133507d17051 | Required buttons/dialog/layouts, responsive board sizing, mode visibility, and safe undo hook are present; Task 4 files only. | None |
| Task 4 | Code quality | CHANGES_REQUIRED | subagent ad1d2dac660a2b015 | Important: AI can place moves while confirmation dialog is open; online/autoload/viewport signals are not disconnected on scene exit. | Fixed in `dfc2b66`; re-review approved. |
| Task 4 | Code quality re-review | APPROVED | subagent a5acd94bab62a4a8e | Confirmation pause/cancel and scene signal cleanup verified; no critical or important findings. | None |
| Task 5 | Spec compliance | APPROVED | subagent a6d11284115170d56 | Undo helpers, manager API, UI refresh, mode behavior, and Task 5 file scope match plan; extra smoke test passed. | None |
| Task 5 | Code quality | CHANGES_REQUIRED | subagent ac267fdce754f6ff9 | Important: `rebuild_from_history()` can partially corrupt state on invalid history; VS AI undo removes too many moves while AI response is pending. | Fixed across `d620450`, `6f9567a`, and `bb31c9e`; re-review found further manager/UI issues. |
| Task 5 | Code quality re-review | CHANGES_REQUIRED | subagent a60221ed80073b368 | Important: undo failure still cancels live request plumbing; UI enables undo in VS AI human-white opening where manager refuses it. | Fixed in `c788fbd` and `f839be5`; final re-review approved. |
| Task 5 | Code quality final re-review | APPROVED | subagent a7a8135088da58dca | Transactional rebuild, VS AI undo count, public/UI `can_undo_last_turn()`, and focused tests verified; no critical/important findings. | None |
| Task 6 | Spec compliance | APPROVED | subagent a67a20aea58699c21 | Replay scene/script, GameManager replay state, GameRecord load safety, game-over replay, AI Lab last-batch replay, and tests match Task 6. | None |
| Task 6 | Code quality | CHANGES_REQUIRED | subagent abae1e952af92afa0 | Important: stale replay records can show after unsaved/save-failed endings; GameRecord accepts malformed parseable JSON; tests miss these cases. | Fixed in `54bd51e`; re-review approved. |
| Task 6 | Code quality re-review | APPROVED | subagent a7dfa5c21b2dffc43 | Stale replay state, unsaved endings, GameRecord validation, and regression tests verified; no critical/important findings. | None |
| Task 7 | Spec compliance | APPROVED | subagent af4f8e0740c606e3c | Board display/read-only state, replay integration, temporary renderer removal, and tests match Task 7; no Task 8 scope. | None |
| Task 7 | Code quality | APPROVED | subagent a3942d344de4771b3 | Shared board renderer replay path approved; no critical/important findings. | None |
| Task 8 | Spec compliance | APPROVED | subagent addfe52c51ad93c9f | AI watch state, controls, pause/step/auto handlers, speed preservation, and tests match Task 8. | None |
| Task 8 | Code quality | CHANGES_REQUIRED | subagent ad7009c4bccb73f8f | Important: paused/step invalid AI result retries are blocked by pause gate and can stall before any move is accepted. | Fixed in `29408ac`; re-review found signal-path one-shot issue. |
| Task 8 | Code quality re-review | CHANGES_REQUIRED | subagent a9a5ed2e02e142d33 | Critical: invalid retry requested inside `CONNECT_ONE_SHOT` callback loses listener after one-shot cleanup; tests bypassed signal lifecycle. | Fixed in `d781165`; final re-review approved. |
| Task 8 | Code quality final re-review | APPROVED | subagent abb61ca8a3b160068 | Deferred retry after one-shot cleanup and signal-path invalid retry tests verified; no critical/important findings. | None |
| Whole branch | Final code review | APPROVED | subagent final review | Offline UX 2.0 implementation approved with no critical or important findings. | Complete target-device checks on Mac/iPhone/iPad before release. |

---

## Verification Evidence

| When | Command | Result | Notes |
|------|---------|--------|-------|
| 2026-05-01 13:06 UTC | `git rev-parse --show-toplevel && git branch --show-current && git worktree list` | PASS | Confirmed current session is isolated worktree `/home/ubuntu/.config/superpowers/worktrees/gomoku/renju-mode` on branch `renju-mode`. |
| 2026-05-01 13:20 UTC | `python3 tools/generate_cjk_subset.py --check` | FAIL expected | Before regeneration, missing glyphs were `。上下不从则动复头悔播放斗暂最由电盘确禁继续脑自落规负，`. |
| 2026-05-01 13:24 UTC | `python3 tools/generate_cjk_subset.py --source-font /tmp/NotoSansCJKsc-Regular.otf` | PASS | Generated `assets/fonts/cjk_subset.otf` with 168 UI glyphs after extracting SC face from `/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc`. |
| 2026-05-01 13:25 UTC | `python3 tools/generate_cjk_subset.py --check` | PASS | `OK: ... covers 168 UI glyphs`. |
| 2026-05-01 13:30 UTC | `python3 -m py_compile tools/generate_cjk_subset.py` | PASS | Script syntax check passed. |
| 2026-05-01 13:31 UTC | token-pattern grep on Task 1 diff | PASS | No token-shaped strings found. |
| 2026-05-01 14:15 UTC | `python3 tools/generate_cjk_subset.py --check` after quality fix | PASS | `OK: ... covers 263 UI glyphs`. |
| 2026-05-01 14:15 UTC | `python3 -m py_compile tools/generate_cjk_subset.py` after quality fix | PASS | Script syntax check passed. |
| 2026-05-01 14:15 UTC | ASCII cmap verification | PASS | Font includes digits, A-Z, a-z, space, and `-_/%.:|=>+`. |
| 2026-05-01 14:50 UTC | `godot --headless --path . --quit` after Task 2 quality fix | PASS_WITH_WARNING | No parse errors; existing Linux custom font loader warning for `res://assets/fonts/cjk_subset.otf`. |
| 2026-05-01 14:50 UTC | grep for `record.ruleset`, `batch_use_renju_rules`, `renju_checkbox.disabled` | PASS | Verified normal records persist ruleset and AI Lab batch rules are captured/locked. |
| 2026-05-01 15:12 UTC | Godot Task 3 TDD scripts | PASS | Forbidden move rejected by `place_stone`; `GameManager.submit_human_move()` emits `黑棋禁手，不能落子`, does not place stone/end game. |
| 2026-05-01 15:13 UTC | `godot --headless --path . --quit` after Task 3 | PASS_WITH_WARNING | No parse errors; existing Linux custom font loader warning for `res://assets/fonts/cjk_subset.otf`. |
| 2026-05-01 15:13 UTC | `git diff --check` after Task 3 | PASS | No whitespace errors. |
| 2026-05-01 15:33 UTC | `godot --headless --path . --quit` after Task 4 | PASS_WITH_WARNING | No parse errors; existing Linux custom font loader warning for `res://assets/fonts/cjk_subset.otf`. |
| 2026-05-01 15:33 UTC | Static Task 4 requirement check | PASS | Verified required nodes/functions/export are present. |
| 2026-05-01 15:33 UTC | `git diff --check -- scenes/game/game.tscn scenes/game/game.gd scenes/game/board.gd` | PASS | No whitespace errors. |
| 2026-05-01 16:15 UTC | `godot --headless --path . --quit` after Task 4 quality fix | PASS_WITH_WARNING | No parse errors; existing Linux custom font loader warning for `res://assets/fonts/cjk_subset.otf`. |
| 2026-05-01 16:15 UTC | `git diff --check -- scenes/game/game.gd scripts/autoload/game_manager.gd` | PASS | No whitespace errors. |
| 2026-05-01 16:37 UTC | `godot --headless --path . --quit` after Task 5 | PASS_WITH_WARNING | No parse errors; existing Linux custom font loader warning for `res://assets/fonts/cjk_subset.otf`. |
| 2026-05-01 16:37 UTC | Temporary Godot undo behavior script | PASS | Verified local PvP undo removes one move and VS AI undo removes human+AI pair. |
| 2026-05-01 16:38 UTC | token-shaped grep on Task 5 diff | PASS | No token-shaped strings found. |
| 2026-05-01 17:56 UTC | `godot --headless --path . res://tools/test_undo_task5.tscn` | PASS | `UNDO_TASK5_TESTS PASS`; includes expected invalid-history error log. |
| 2026-05-01 17:57 UTC | `godot --headless --path . --quit` after Task 5 quality fix | PASS_WITH_WARNING | No parse errors; known missing Linux GDExtension warning for `gomoku_neural`. |
| 2026-05-01 17:57 UTC | `git diff --check` after Task 5 quality fix | PASS | No whitespace errors. |
| 2026-05-01 18:40 UTC | `godot --headless --path . res://tools/test_replay_task6.tscn` | PASS | `REPLAY_TASK6_TESTS PASS`. |
| 2026-05-01 18:41 UTC | `godot --headless --path . res://tools/test_undo_task5.tscn` after Task 6 | PASS | `UNDO_TASK5_TESTS PASS`. |
| 2026-05-01 18:41 UTC | `godot --headless --path . --quit` after Task 6 | PASS_WITH_EXPECTED_WARNINGS | No parse errors; expected Linux missing `gomoku_neural` GDExtension warnings. |
| 2026-05-01 18:42 UTC | token-shaped grep on Task 6 diff | PASS | No token-shaped strings found. |
| 2026-05-01 19:08 UTC | `godot --headless --path . res://tools/test_replay_task6.tscn` after Task 6 quality fix | PASS | `REPLAY_TASK6_TESTS PASS`; expected Linux missing GDExtension warning. |
| 2026-05-01 19:09 UTC | `godot --headless --path . --quit` after Task 6 quality fix | PASS_WITH_EXPECTED_WARNINGS | No parse errors; expected Linux missing `gomoku_neural` GDExtension warning. |
| 2026-05-01 19:09 UTC | `git diff --check` after Task 6 quality fix | PASS | No whitespace errors. |
| 2026-05-01 19:27 UTC | `godot --headless --path . --quit` after Task 7 | PASS_WITH_EXPECTED_WARNINGS | No parse errors; expected Linux missing `gomoku_neural` GDExtension warnings. |
| 2026-05-01 19:27 UTC | `godot --headless --path . res://tools/test_replay_task6.tscn` after Task 7 | PASS | `REPLAY_TASK6_TESTS PASS`. |
| 2026-05-01 19:28 UTC | `godot --headless --path . res://tools/test_undo_task5.tscn` after Task 7 | PASS | `UNDO_TASK5_TESTS PASS`; expected invalid-history test log. |
| 2026-05-01 19:28 UTC | diff checks and token scan after Task 7 | PASS | No whitespace errors or token-shaped strings. |
| 2026-05-01 19:57 UTC | `godot --headless --path . res://tools/test_ai_watch_task8.tscn` | PASS | `AI_WATCH_TASK8_TESTS PASS`. |
| 2026-05-01 19:58 UTC | Task 5/6 regression tests after Task 8 | PASS | Undo and replay tests passed; replay test still emits existing ObjectDB leak warning while exiting 0. |
| 2026-05-01 19:58 UTC | `godot --headless --path . --quit` after Task 8 | PASS_WITH_EXPECTED_WARNINGS | No parse errors; expected Linux missing `gomoku_neural` GDExtension warning. |
| 2026-05-01 19:59 UTC | diff/token checks after Task 8 | PASS | No whitespace errors or token-shaped strings. |
| 2026-05-01 20:32 UTC | `godot --headless --path . res://tools/test_ai_watch_task8.tscn` after Task 8 quality fix | PASS | `AI_WATCH_TASK8_TESTS PASS`; includes invalid-retry while paused cases. |
| 2026-05-01 20:33 UTC | Task 5/6 regression tests after Task 8 quality fix | PASS | Undo and replay tests passed. |
| 2026-05-01 20:33 UTC | `godot --headless --path . --quit` after Task 8 quality fix | PASS_WITH_EXPECTED_WARNINGS | No parse errors; expected Linux missing `gomoku_neural` GDExtension warning. |
| 2026-05-01 20:33 UTC | `git diff --check` after Task 8 quality fix | PASS | No whitespace errors. |
| 2026-05-01 20:54 UTC | `godot --headless --path . res://tools/test_ai_watch_task8.tscn` after signal retry fix | PASS | `AI_WATCH_TASK8_TESTS PASS`; signal-path invalid retry tests included. |
| 2026-05-01 20:55 UTC | Task 5/6 regression tests after signal retry fix | PASS | Undo and replay tests passed. |
| 2026-05-01 20:55 UTC | `godot --headless --path . --quit` after signal retry fix | PASS_WITH_EXPECTED_WARNINGS | No parse errors; expected Linux missing `gomoku_neural` GDExtension warning. |
| 2026-05-01 20:55 UTC | `git diff --check` after signal retry fix | PASS | No whitespace errors. |
| 2026-05-01 18:14 UTC | `godot --headless --path . tools/test_undo_task5.tscn --quit` after second Task 5 fix | PASS | `UNDO_TASK5_TESTS PASS`; includes expected invalid-history logs. |
| 2026-05-01 21:14 UTC | `python3 tools/generate_cjk_subset.py --check` final | PASS | Font covers 279 UI glyphs. |
| 2026-05-01 21:15 UTC | `godot --headless --path . --quit` final | PASS_WITH_EXPECTED_WARNINGS | No parse errors; expected Linux missing `gomoku_neural` GDExtension warning. |
| 2026-05-01 21:16 UTC | AI watch/replay/undo focused tests final | PASS | `AI_WATCH_TASK8_TESTS PASS`, `REPLAY_TASK6_TESTS PASS`, `UNDO_TASK5_TESTS PASS`. |
| 2026-05-01 21:18 UTC | `git diff --check` final | PASS | No whitespace errors. |
| 2026-05-01 21:18 UTC | token-shaped grep on `git diff main...HEAD` | PASS | No token-shaped strings found. |
| 2026-05-02 05:30 UTC | finishing-branch pre-sync checks | PASS | Font coverage PASS, Godot parse PASS with expected Linux GDExtension warning, `git diff --check` PASS. |
| 2026-05-01 18:15 UTC | `godot --headless --path . --quit` after second Task 5 fix | PASS_WITH_WARNING | No parse errors; known Linux missing `gomoku_neural` GDExtension warning. |
| 2026-05-01 18:15 UTC | `git diff --check` after second Task 5 fix | PASS | No whitespace errors. |

---

## Decisions

| When | Decision | Reason |
|------|----------|--------|
| 2026-05-01 13:06 UTC | Use subagent-driven development. | User agreed; prior memory requires strict Superpowers process and strongest available subagents. |
| 2026-05-01 13:06 UTC | Keep existing global worktree instead of creating another. | Current session is already in isolated worktree `renju-mode`. |

---

## Files Changed So Far

- `docs/superpowers/specs/2026-05-01-offline-ux-2-design.md` — approved design spec, committed.
- `docs/superpowers/plans/2026-05-01-offline-ux-2.md` — implementation plan, committed.
- `docs/superpowers/progress/offline-ux-2-progress.md` — durable execution progress, in progress.
- `tools/generate_cjk_subset.py` — font subset generation/check script, committed in `e513e9b`; ASCII coverage and pruning fixed in `15328c3`.
- `assets/fonts/cjk_subset.otf` — regenerated CJK subset, committed in `e513e9b`; regenerated with ASCII coverage in `15328c3`.
- `assets/fonts/cjk_subset_chars.txt` — generated character manifest, committed in `e513e9b`; regenerated with ASCII coverage in `15328c3`.
- `docs/dev_log.md` — font subset workflow note, committed in `e513e9b`.
- `scenes/local_setup/local_setup.gd` — local rules setup script, committed in `bf3c95f`.
- `scenes/local_setup/local_setup.tscn` — local rules setup scene, committed in `bf3c95f`.
- `scenes/main_menu/main_menu.gd` — routes local PvP to setup, committed in `bf3c95f`.
- `scenes/ai_lab/ai_lab.tscn` — explicit Renju checkbox and last-batch replay button, committed in `bf3c95f`.
- `scenes/ai_lab/ai_lab.gd` — explicit AI Lab rules and stable batch rules, committed in `bf3c95f`; quality fix in `86fad23`.
- `scripts/data/game_record.gd` — adds `ruleset`, committed in `bf3c95f`.
- `scripts/autoload/game_manager.gd` — persists ruleset for normal records, committed in `86fad23`; emits invalid human move messages in `9a090fa`; pauses gameplay during confirmations in `dfc2b66`; offline undo manager API in `18f3bd4`; VS AI pending-response undo fix in `d620450`; manager-level undo transactional state/can-undo fixes in `c788fbd`.
- `scripts/game_logic.gd` — rejects forbidden placements and exposes `can_place_stone`, committed in `9a090fa`; rebuild/undo helpers in `18f3bd4`; transactional rebuild fixes in `d620450` and `bb31c9e`.
- `scenes/game/game.gd` — displays invalid move messages and removes forbidden-win result branch, committed in `9a090fa`; responsive layout/control wiring in `ad5ecf3`; confirmation/signal lifecycle fixes in `dfc2b66`; undo UI refresh in `18f3bd4`; can-undo UI eligibility in `c788fbd`.
- `scenes/game/game.tscn` — adds `MessageLabel`, committed in `9a090fa`; responsive layout containers and explicit buttons in `ad5ecf3`.
- `scenes/game/board.gd` — runtime board sizing/scaling for responsive layout, committed in `ad5ecf3`.
- `tools/test_undo_task5.gd` / `tools/test_undo_task5.tscn` — focused undo regression tests, committed in `6f9567a`; expanded in `f839be5`.
- `scenes/replay/replay.gd` / `scenes/replay/replay.tscn` — replay UI and controls, committed in `47a1153`.
- `tools/test_replay_task6.gd` / `tools/test_replay_task6.tscn` — replay regression tests, committed in `47a1153`.
- `tools/test_ai_watch_task8.gd` / `tools/test_ai_watch_task8.tscn` — AI watch pause/step regression tests, committed in `ab5c0b5` and expanded in `d781165`.
