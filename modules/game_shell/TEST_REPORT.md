# Game shell test report — 2026-11-21

## Verified in authoring environment

- Repository and requirements inspected from connected GitHub: AGENTS, Game Design, Technical Architecture, Interfaces, and PRs for Core (#6), Art (#7), Racing (#5).
- Only `modules/game_shell/` paths were written to `feat/game-shell`. Branch started from main commit `2f6d2a71f48eee09dadd16c86457b4daddc51f07`.
- Source-controlled scenes, scripts, save migration/recovery, mock transitions and automated Godot test harness authored. GitHub content/branch writes confirmed.

## Executed independent source and repository checks

- GitHub comparison of `main...feat/game-shell`: **13 changed files, 13 within `modules/game_shell/`, zero ownership violations; 1,696 lines added** at the checkpointed scan (later fixes add a few more lines).
- Enumerated **8 GDScript files plus the standalone scene**, checked relative preloads against the feature-branch Git tree: **zero unresolved references**.
- Independent balanced-delimiter/source string scan over module GDScript: **zero structural errors detected**. This does **not** substitute for GDScript parsing.
- Executed **16/16 targeted source-contract checks** against the committed files: eight UI routes; input mappings; v2 schema; seven settings; three cars; four events; temporary/backup/corrupt recovery branches; migration; race results; pause gating; standalone scene linkage; original visuals; authored tests; Forward+ renderer; no network dependency.
- Authored `tests/run_tests.gd` contains **48 runtime assertions**; these remain **unexecuted** because the Godot binary is not available.

## Engine/runtime checks — not executable in this environment

The authoring container has **no `godot` or `godot4` binary**. Standard `git` cannot resolve `github.com` from that container, although the connected GitHub app can access and write the repository. Therefore this report **does not claim a Godot parser pass, imported scene pass, visual screenshot, interactive gameplay test, controller test or exported Windows build**.

Run on a Godot 4.7.2 machine:

```sh
godot --headless --path modules/game_shell --editor --quit
godot --headless --path modules/game_shell --script res://tests/run_tests.gd
godot --path modules/game_shell
```

The `tests/run_tests.gd` assertions are authored, **not claimed passing** until their real console output is recorded. They cover first-run defaults, locked selections, save/write/reload, persistence, invalid settings, progression unlocks/best times, backup/temp/corrupt recovery, schema-1 migration, pause/resume, mock stage progression, and actual UI callback paths.

## Manual QA gates pending

- Inspect all screens at 1280×720, 1600×900, 1920×1080 and a narrower viewport. Verify clipping/scroll/large fonts.
- Navigate every screen with keyboard-only and a physical Xbox controller, including disconnect/reconnect, focus after selecting a dropdown, B/back and Start/pause.
- Test actual fullscreen/windowed transitions, OS resolution changes, audio bus behavior (host must supply Music/SFX), and persistence after process restart.
- Verify garage 3D render, selected car visual changes, schematic minimap refresh, race overlays, prompt readability and contrast.
- Simulate read-only user directory, interrupted write and power loss to confirm backup paths on target Windows filesystem.
- Host integration: real VehicleAdapter telemetry, authoritative race end, world map coordinates, GLB import, physics pause, Windows export, framerate.

Do not merge based solely on source presence. The module is a functional implementation candidate pending actual Godot execution and QA.
