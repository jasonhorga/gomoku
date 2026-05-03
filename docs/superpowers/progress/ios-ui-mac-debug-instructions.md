# iOS UI Mac Debug Instructions

You are running on the user's Mac, where you can inspect iOS Simulator or device UI directly. The EC2 Claude session cannot see the running app, so your job is to gather visual/runtime evidence and write it back into this Google Drive-synced repo for the EC2 session to fix.

## Goal

Diagnose why the iOS app Build 31 appears not to show the recent Pro Max / iPhone portrait UI changes, even though CI built and uploaded `main@bff2c61` successfully.

Do not guess. Capture evidence that distinguishes these cases:

1. The installed app is not running the expected exported resources.
2. The expected resources are present, but the responsive layout branch is not being used.
3. The branch is used, but viewport/safe-area/layout calculations are wrong.
4. The UI actually changed, but the expected visual target was different from what shipped.

## Repo and branch

Use the Google Drive-synced repo checkout, not a copy if possible:

- Repo: `/Users/<user>/.../gomoku` or wherever Google Drive sync placed this repo on the Mac.
- Expected branch: `main`
- Expected relevant commit in shipped TestFlight run: `bff2c61` (`docs: record Pro Max portrait merge`)
- Latest EC2 context also has `5d740a1` (`docs: record Pro Max TestFlight dispatch`)

Before testing, record:

```bash
git status --short --branch
git log --oneline -5
```

Do not discard or overwrite local changes. If the Mac repo has unexpected changes, record them in the report and continue read-only unless the user explicitly approves otherwise.

## Screens to inspect

Capture screenshots from iPhone Pro Max-sized Simulator if possible, preferably iPhone 16 Pro Max / 15 Pro Max portrait. If only a real device is available, screenshots from the real device are fine.

Minimum screens:

1. Main menu
2. Local PvP setup
3. Human vs AI setup
4. AI Lab
5. Gameplay screen after starting a local game

For each screen, record:

- Device/simulator model
- Orientation
- Screenshot path
- What appears wrong or unchanged
- Whether controls fit within the viewport
- Approximate viewport/screenshot size in pixels

Put screenshots under:

`docs/superpowers/progress/ios-ui-screenshots/`

Suggested filenames:

- `build31-main-menu.png`
- `build31-local-setup.png`
- `build31-ai-setup.png`
- `build31-ai-lab.png`
- `build31-gameplay.png`

## Useful Simulator commands

List devices:

```bash
xcrun simctl list devices available
```

Boot an iPhone Pro Max simulator if needed:

```bash
open -a Simulator
xcrun simctl boot "iPhone 16 Pro Max" || true
```

Screenshot booted simulator:

```bash
xcrun simctl io booted screenshot docs/superpowers/progress/ios-ui-screenshots/build31-main-menu.png
```

If the app is installed in Simulator, launch it:

```bash
xcrun simctl launch booted com.jasonhorga.gomoku
```

If testing a local simulator build, install it after building with Xcode/Godot. Prefer reversible local build steps only; do not upload TestFlight from the Mac unless the user explicitly asks.

## Logs to capture

Capture logs around launch and screen transitions. Try one of these:

```bash
xcrun simctl spawn booted log stream --style compact --predicate 'process CONTAINS "gomoku" OR eventMessage CONTAINS "Gomoku" OR eventMessage CONTAINS "UI-DIAG"' --level debug
```

or, if using a real device connected to Xcode, use Console.app/Xcode device logs and copy relevant lines.

Look for:

- viewport / window size
- orientation
- scene name
- layout branch messages
- Godot errors or GDScript parse/runtime errors
- plugin initialization errors that might stop later code

If no useful logs exist, state that clearly.

## Code areas to inspect if needed

Recent UI changes are mainly in:

- `scenes/game/game.gd`
- `scenes/game/game.tscn`
- `scenes/main_menu/main_menu.gd`
- `scenes/local_setup/local_setup.gd`
- `scenes/ai_setup/ai_setup.gd`
- `scenes/ai_lab/ai_lab.gd`
- `export_presets.cfg`
- `project.godot`

Do not implement fixes unless the user asks you to. Prefer writing observations and a suggested fix for EC2 Claude to implement.

## Report file to write

Write your findings to:

`docs/superpowers/progress/ios-ui-device-debug.md`

Use this exact structure:

```md
# iOS UI Device Debug

**Date:** YYYY-MM-DD HH:MM local
**Tester:** Mac Claude / user Mac
**Repo path:** <path>
**Git state:** <branch + short sha + whether dirty>
**Device / Simulator:** <model + OS>
**Installed build:** <TestFlight/App build number if known>

## Summary

One or two sentences with the most likely root cause based on evidence.

## Screens Checked

| Screen | Screenshot | Observed | Expected | Notes |
|--------|------------|----------|----------|-------|
| Main menu | `docs/superpowers/progress/ios-ui-screenshots/...png` | ... | ... | ... |
| Local setup | ... | ... | ... | ... |
| AI setup | ... | ... | ... | ... |
| AI Lab | ... | ... | ... | ... |
| Gameplay | ... | ... | ... | ... |

## Runtime Evidence

Paste relevant logs, viewport/orientation values, build number, or errors. If unavailable, say exactly what was attempted and what failed.

## Root-Cause Hypothesis

State one hypothesis only, with evidence. Example:

> I think the responsive branch is not triggered because the runtime viewport is 932x430 landscape even though the simulator appears portrait. Evidence: ...

or:

> I think the shipped app uses new resources but the intended visual target is not reflected in tests. Evidence: screenshots show ..., while headless tests assert only ...

## Suggested Fix

List concrete files/functions to change, but do not apply the fix unless asked.

## Open Questions

Anything EC2 Claude must ask or verify before coding.
```

## Important constraints

- Do not run training or benchmarks on EC2 or Mac as part of this UI debug.
- Do not run heavy credential/secret scans.
- Do not push, tag, or upload TestFlight unless the user explicitly asks.
- Avoid destructive git commands.
- If you take screenshots, keep them in the progress screenshots directory so the EC2 session can read them from Google Drive.
