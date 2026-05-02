# Offline UX Polish Design

## Scope

This polish pass fixes issues found during target-device validation of Offline UX 2.0:

- Remove English `Renju` from user-facing UI because Chinese rendering is now reliable.
- Make offline rules selection visually consistent across local two-player, human-vs-AI, and AI Lab.
- Default offline setup screens to `禁手规则`.
- Make iPhone gameplay use portrait orientation and the vertical game layout.
- Improve the local two-player setup screen quality.

Online play remains unchanged.

## UX decisions

### Rules copy

Use Chinese-only rules labels everywhere user-facing:

- `自由五子棋`
- `禁手规则`

Short rule descriptions:

- `双方自由落子`
- `黑棋禁手不可落子`

Game HUD rules suffixes should use Chinese-only names and no English parenthetical.

### Unified rules selector

Local two-player, human-vs-AI, and AI Lab use the same card-style selector pattern:

- Two large touch-friendly cards.
- Selected card has stronger border/background.
- Each card shows title plus one-line explanation.
- Default selection is `禁手规则`.

AI Lab may use a compact version of the same card pattern if space is tight, but it should not use a plain checkbox for rule selection.

### iPhone portrait

The iOS export should support/force portrait for iPhone so the vertical game layout is actually used on device. iPad and macOS should continue using the horizontal large-screen layout.

The game scene should still compute layout from the viewport as a safety net: portrait/narrow viewports use vertical layout; wider viewports use horizontal layout.

### Local two-player setup polish

The local two-player setup screen becomes a polished setup panel:

- Clear title: `本地双人`.
- Subtitle: `选择规则后开始对局`.
- Card-style rules selector.
- Primary action: `开始对局`.
- Secondary action: `返回菜单`.

## Components

- Add or reuse a small rules-card UI implementation in setup scripts/scenes.
- Update:
  - `scenes/local_setup/local_setup.tscn/gd`
  - `scenes/ai_setup/ai_setup.tscn/gd`
  - `scenes/ai_lab/ai_lab.tscn/gd`
  - `scenes/game/game.gd`
  - `export_presets.cfg` if needed for iOS orientation.
- Regenerate/check `assets/fonts/cjk_subset.otf` after copy changes.

## Testing

Local checks:

- Godot headless parse check.
- Font subset coverage check.
- Grep user-facing scene/script text to ensure English `Renju` is removed from UI labels.

Target-device checks:

- iPhone launches into portrait gameplay and shows vertical layout.
- iPad/macOS still use usable horizontal layout.
- Local two-player setup looks polished and defaults to `禁手规则`.
- Human-vs-AI and AI Lab show the same Chinese-only rules selector pattern and default to `禁手规则`.
- Game HUD shows Chinese-only rules text.
