# Offline UX 2.0 Design

## Scope

This design improves offline usability after the Renju release. It covers local two-player games, human-vs-AI games, AI Lab watch/batch flows, replay, touch layout, and Chinese font reliability.

Online play remains out of scope for this pass. Online games keep the current free-Gomoku rules and do not add Renju negotiation, undo requests, or replay synchronization.

## Goals

- Make Renju rules selectable in local two-player mode.
- Make AI Lab rules explicit instead of depending on hidden global state.
- Fix Chinese garbled text by regenerating the bundled CJK font subset from current UI text.
- Make iPhone gameplay vertical and touch-friendly while keeping iPad/macOS horizontal.
- Add safe in-game actions: undo, new game, and return to main menu.
- Change casual Renju behavior so forbidden black moves are blocked with a message instead of immediately losing.
- Add replay for the just-finished game and the last AI Lab batch game.
- Add AI-vs-AI step controls only for AI Lab watch mode.

## Non-goals

- No online Renju mode.
- No online undo/takeback protocol.
- No complete historical game-record browser.
- No Renju-specific CNN retraining.
- No detailed forbidden-reason classification in this pass; the message can be generic.

## Current issues

- `GameManager.setup_local_pvp()` already accepts a Renju flag, but `main_menu.gd` calls it without a UI choice, so local two-player always starts as free Gomoku.
- `ai_lab.gd` reads `GameManager.forbidden_enabled`, but AI Lab has no visible Renju toggle, so test results depend on stale hidden state.
- `assets/fonts/cjk_subset.otf` is missing newly added glyphs such as `禁`, `规`, `则`, and Chinese punctuation like `，`.
- `game.tscn` uses a horizontal board plus side-panel layout. This is awkward for iPhone and several action buttons are too small.
- During local two-player games, the visible active-game action is overloaded as `新对局`; there is no clear active-game return-to-main-menu action.
- `GameLogic` has move history but no undo API.
- `GameRecord` can store moves, but there is no replay UI.
- AI Lab watch mode auto-runs with a speed delay but has no pause or next-step control.

## UX design

### Mode and rules setup

Local two-player gets a lightweight setup screen before the game starts:

- Rules: `自由五子棋` or `禁手规则 Renju`.
- Actions: `开始`, `返回`.

Human-vs-AI keeps the existing AI setup screen, but the Renju checkbox uses the fixed font and consistent copy.

AI Lab gets its own explicit `禁手规则 Renju` checkbox. Both watch mode and batch mode read this checkbox and pass the selected ruleset into `GameManager.setup_ai_vs_ai()` or the headless batch `GameLogic`.

Online setup remains unchanged and continues forcing Renju off.

### Responsive game layout

The game scene supports two layouts:

- iPhone vertical layout:
  - Top status area: current turn, ruleset, move count, and transient messages.
  - Center board: scaled to available width while preserving the 15x15 board.
  - Bottom action area: large touch buttons.
- iPad/macOS horizontal layout:
  - Keep the current board plus right information panel structure.
  - Increase button sizes and split overloaded actions into explicit buttons.

The layout decision should be based on viewport shape and practical touch size, with iPhone portrait using the vertical layout and iPad/macOS using horizontal by default.

### In-game actions

Local two-player:

- `悔棋`: undo the last move.
- `新对局`: ask for confirmation, then reset.
- `返回主菜单`: ask for confirmation, then return.

Human-vs-AI:

- `悔棋`: undo one full turn pair, meaning the last AI move plus the last human move. If the AI has not answered yet, undo the last human move.
- `新对局`: ask for confirmation, then reset.
- `返回主菜单`: ask for confirmation, then return.

AI Lab watch mode:

- `暂停/继续`: toggle automatic AI movement.
- `下一步`: request exactly one AI move while paused.
- `自动播放`: resume automatic movement.
- Speed control remains available.
- `返回主菜单`: ask for confirmation, then return.

Online mode keeps its existing resign/reset behavior except for safe UI sizing and font fixes.

### Forbidden move behavior

In Renju mode, black forbidden cells remain visually marked with red X indicators when helpful.

When a human black player taps a forbidden cell:

- Do not place the stone.
- Do not end the game.
- Show a transient message: `黑棋禁手，不能落子`.
- Keep the same player to move.

AI move generation must continue filtering forbidden black moves. If an AI somehow proposes an illegal forbidden move, the existing fallback legality checks should prevent it from being submitted.

### Undo model

`GameLogic` should expose an undo/rebuild path based on `move_history`:

- Remove the requested number of trailing moves.
- Rebuild the board from the remaining move history.
- Restore `current_player`, `game_over`, `winner`, and `game_end_reason` consistently.

Undo is available only for local two-player and human-vs-AI in this pass. Undo is not available during online games, completed games, or replay mode.

Human-vs-AI undo must also cancel any pending AI move before rebuilding state.

### Replay model

Replay is a read-only review state built from a saved move list, not from live game mutation.

Entry points:

- Game-over panel: `复盘` for the just-finished visible game.
- AI Lab batch completion: `复盘最后一局` for the final completed batch game.

Controls:

- `上一步`
- `下一步`
- `从头`
- `自动播放/暂停`
- `返回`

Replay reconstructs the board up to the selected move index and draws it through the existing board rendering path or a small replay-specific wrapper. It should show move index, total moves, result, ruleset, and players.

This pass does not add a full historical game browser, but the design should avoid blocking one later.

### Chinese font pipeline

Add an automated font-subset generation script:

- Scan `.gd` and `.tscn` files for Chinese characters and Chinese punctuation used in UI strings.
- Include stable base characters used by dynamic copy where static scanning may miss them.
- Generate `assets/fonts/cjk_subset.otf` from the source CJK font.
- Fail clearly if the source font or subsetting tool is missing.

The generated subset must include all current UI glyphs, including Renju text and punctuation. Future Chinese copy changes should rerun this script before release.

## Components

### Setup screens

- Add a local two-player setup scene or equivalent lightweight panel.
- Update main menu local PvP action to open setup instead of directly starting.
- Update AI Lab scene to include a Renju checkbox and pass the value explicitly.

### Game scene

- Refactor `game.tscn` / `game.gd` enough to support vertical and horizontal arrangements.
- Add explicit action buttons instead of overloading one mode-specific button.
- Add a transient message label for blocked forbidden moves and confirmations.
- Add AI Lab watch controls shown only in `AI_VS_AI` watch mode.

### Game logic and manager

- Add undo/rebuild support to `GameLogic`.
- Add `GameManager` methods for mode-appropriate undo and pending-AI cancellation.
- Change human forbidden-move submission to reject with a message instead of placing the stone and ending the game.
- Preserve AI forbidden filtering.

### Replay

- Add a replay state or scene that accepts a `GameRecord` or move list.
- Add entry points from game-over and AI Lab batch completion.
- Reconstruct board by replaying moves up to the cursor.

### Font tooling

- Add a script under a tooling/scripts location for font subset generation.
- Document the command in the relevant release or development doc.
- Regenerate the committed subset font.

## Data flow

1. User selects mode and rules.
2. Setup screen passes the ruleset into `GameManager`.
3. `GameManager` applies the ruleset to `GameLogic` and AI engines.
4. Board taps flow through `GameManager.submit_human_move()`.
5. If the move is a human forbidden black move in Renju mode, the manager rejects it and emits/displays a transient message.
6. Legal moves update `GameLogic` and `move_history`.
7. Undo requests call manager-level undo, which cancels pending AI work if needed and rebuilds the board.
8. On game end, `GameRecord` captures the final move list.
9. Replay receives a move list and renders a read-only board at the selected cursor.

## Error handling and confirmations

- `新对局` and `返回主菜单` during active games require confirmation.
- `悔棋` is disabled when there are not enough moves to undo.
- Replay controls are disabled at the beginning/end as appropriate.
- AI Lab step controls are disabled when an AI move is already computing.
- If font generation dependencies are missing, the script exits with a clear message and does not silently keep a stale subset.

## Testing plan

Manual target-device checks are required because this is UI-heavy:

- iPhone portrait: vertical layout, readable text, large bottom buttons, safe-area behavior.
- iPad/macOS: horizontal layout remains usable.
- Local PvP free Gomoku and Renju setup paths.
- Human-vs-AI free Gomoku and Renju setup paths.
- AI Lab watch and batch with explicit Renju on/off.
- Human forbidden black tap is blocked with a message and does not end the game.
- Local PvP undo removes one move.
- Human-vs-AI undo removes the AI response plus the human move.
- New game and return-to-main-menu confirmations work.
- Replay from game-over works.
- Replay of AI Lab batch final game works.
- AI Lab watch pause, next-step, autoplay, and speed control work.
- Generated font covers all current Chinese UI strings in iOS and macOS builds.

Automated/light checks:

- GDScript parse/headless check if available.
- Existing Swift diff/CoreML validation unchanged.
- A script-level font coverage check that compares scanned UI glyphs against the generated subset.

## Rollout

Implement as one UX 2.0 branch, but keep commits staged by subsystem:

1. Font pipeline and regenerated subset.
2. Local PvP and AI Lab rules setup.
3. Responsive game layout and explicit controls.
4. Forbidden-move blocking behavior.
5. Undo.
6. Replay.
7. AI Lab watch controls.
8. Verification and release build.

This keeps the feature cohesive while preserving reviewable checkpoints.
