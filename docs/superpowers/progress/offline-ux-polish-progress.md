# Progress: Offline UX Polish

**Plan:** `docs/superpowers/plans/2026-05-02-offline-ux-polish.md`
**Status:** IN_PROGRESS
**Workflow:** subagent-driven-development
**Branch:** `offline-ux-polish`
**Worktree:** `/home/ubuntu/.config/superpowers/worktrees/gomoku/offline-ux-polish`
**Last updated:** 2026-05-02 12:19 UTC
**Last known commit:** `d31ed17`
**Current task:** Task 5 — Refresh font subset and final local verification
**Next action:** Commit progress artifact only, mark Task 5 complete, then dispatch final whole-branch review.

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

**Last completed safe point:** Task 4 passed spec and code-quality review and cleanup/progress was committed as `d31ed17`.

**In progress:** All plan tasks are complete; final whole-branch review is next.

**Blockers/questions:** None known. `.superpowers/` is untracked and must not be committed.

**Next exact action:** Commit progress artifact only, run final whole-branch review, then use finishing-a-development-branch workflow to sync/merge without deleting the worktree.

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
