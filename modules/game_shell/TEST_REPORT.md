# Game shell runtime QA

Verified on November 21, 2026 with Godot 4.7.2 stable (`ed1daf0bf`) on Windows. The graphical test used Vulkan Forward+ on an NVIDIA GeForce RTX 4050 Laptop GPU. The baseline is PR #12 head `be89592`.

## Failures reproduced and corrected

| Area | Finding and correction |
| --- | --- |
| Import | GDScript could not infer the types of the save candidate, garage unlock flag, and minimap marker. Explicit types restored clean import and runtime loading. Godot could print script errors even when a shell test returned exit code zero, so the logs were checked as well. |
| Save recovery | Invalid JSON flooded the engine log during expected recovery. The save service now handles failed parses before schema validation. A versionless schema-1 profile now writes back its migrated schema-2 data. The runtime suite uses a dedicated profile. |
| Settings | Display and slider controls now restore the saved value on write failure and show the error in Settings. Returning from fullscreen reapplies the saved window size. |
| Garage | Rebuilding the view returned focus to the first car. The inspected row retains focus and the selection button stays near the top of the detail panel. Pausing while moving no longer bypasses the parked-car requirement. |
| Layout and preview | The footer spacer took height away from scrollable panels. Focus now waits for layout and scroll follows the focused control. The countdown, live telemetry, and minimap are visible together. Preview lighting no longer washes out the cars and floor. |

## Results

- Editor import completed without parser or runtime errors.
- The original 48 GDScript assertions passed. Five more assertions covered versionless migration, the moving garage guard, and blocked setting writes. **53 checks, 0 failures.**
- The standalone scene ran graphically at **1280×720, 1600×900, and 1920×1080**. The test exercised keyboard menu and garage focus, three-car progression, synthetic D-pad/A/B/Start events, pause and resume in free roam and during a race countdown, event discovery, result persistence, keyboard settings navigation, fullscreen/windowed switching, and corrupt-primary recovery. **30 screenshots, 0 failures.**
- A second Godot process reopened the repaired profile and verified the selected car, graphics preset, sensitivity, and resolution. **0 failures.**
- Reviewed the menu, garage, pause, events, countdown, results, settings, and recovered menu. Event and settings lists scroll with focus. The garage shows its primary selection controls before the preview and lower stats.

## Screenshots from the actual Godot viewport

- [1280×720 main menu](tests/screenshots/1280x720-menu.png)
- [1280×720 race countdown, telemetry and map](tests/screenshots/1280x720-race-countdown.png)
- [1600×900 three-car garage](tests/screenshots/1600x900-garage-unlocked.png)
- [1920×1080 race results](tests/screenshots/1920x1080-results.png)
- [1920×1080 settings with keyboard focus](tests/screenshots/1920x1080-settings-scrolled.png)

## Reproduce

Run from the repository root with the Godot 4.7.2 console executable and an existing screenshot folder.

```powershell
godot --headless --path modules/game_shell --import --quit
godot --headless --path modules/game_shell --script res://tests/run_tests.gd
godot --path modules/game_shell --fixed-fps 30 --script res://tests/visual_qa.gd -- --capture-dir <folder>
godot --headless --path modules/game_shell --script res://tests/visual_qa.gd -- --verify-profile <printed-profile>
```

The last command uses the `RESTART PROFILE` path printed by the graphical test. The tests create isolated QA profiles and deliberately corrupt only their own fixtures.

## Remaining verification and integration

Physical controller and hotplug behavior, Windows export, and interruption or power loss at the filesystem level remain unverified. The standalone shell still uses mock telemetry and races. Root integration must wire the real vehicle and race state, world-map coordinates, GLB previews, audio buses, and host input/pause and save ownership. See [the integration handoff](INTEGRATION_NOTES.md).
