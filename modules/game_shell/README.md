# Aster Valley — Game Shell (isolated Track F)

**Standalone Godot 4.7.2 project**, all implementation strictly inside \`modules/game_shell/\`. Nothing here is the authoritative driving scene or a replacement vehicle controller. No third-party assets or network services.

## Open and run

From repository root:

\`\`\`sh
godot --headless --path modules/game_shell --editor --quit
godot --headless --path modules/game_shell --script res://tests/run_tests.gd
godot --path modules/game_shell
\`\`\`

Open \`modules/game_shell/project.godot\` in Godot 4.7.2 for the same demo. The startup scene is \`scenes/demo.tscn\`. A local profile is stored at \`user://aster_valley_save_v2.json\`; a validated \`.bak\` is kept when replacing a valid prior save. The data lives in the user's Godot application-data directory, not in the repository.

## Screens and behavior

- **Main menu:** Play, Garage, Settings, Quit; 3D showcase of selected car.
- **Free roam (mock):** changing km/h, gear, selected car, event prompt, live schematic minimap, garage and pause. Controls affect only demo telemetry, not a physics car.
- **Garage:** original procedural 3D car preview; all three fictional cars (Vela GT, Orion RS, Kestrel XR), stats, locked selection states and parked-only access from free roam.
- **Events:** four canonical design event names, course type/laps, per-event best time and start action.
- **Race:** 3-second countdown, clock, position, lap, speed, result transition, pause/abort-to-roam. F finishes an active mock race early for rapid UI testing.
- **Results:** time, best time, placement, deterministic credits and unlocks, retry and free-roam return. Save failure is visible.
- **Settings:** low/medium/high 3D render-scale presets, windowed/fullscreen, three resolutions, controller sensitivity, master/music/SFX volume and persistent values. Music and SFX bus values are staged until buses are present in the host.
- **Pause:** freezes the mock clock, offers resume/settings/main-menu; abandoning a race returns to free roam.
- **Focus/navigation:** buttons and options have keyboard focus and directional UI navigation. Runtime default mappings support keyboard and Xbox-style gamepad.

All UI artwork is original code: no downloaded fonts, images, logos or models. \`scripts/car_preview.gd\` creates a visual-only primitive coupe; **it is not one of the Art Agent's final GLBs**. \`scripts/minimap.gd\` draws a **labeled schematic**, not World Agent road geometry. Mock race durations do not represent real lap times.

## Keyboard and gamepad defaults

| Action | Keyboard | Xbox-style |
|---|---|---|
| Menu select and directional focus | Enter, arrows | A, D-pad |
| Back | Backspace; Esc on other screens | B |
| Pause / resume | Esc | Start |
| Demo accelerate / brake | W/Up, S/Down | RT, LT |
| Demo steer | A/D or left/right | Left stick |
| Discover event | E | A |
| Garage while parked | G | X |
| Enlarge schematic map | M | View/Back |
| Finish mock race early | F | Not mapped |

The demo adds missing \`shell_*\` InputMap actions at runtime. Existing events are not removed. Godot's \`ui_*\` focus actions are reused and gamepad A/D-pad fallbacks are added. **Mappings are implemented in code; real controller operation and hotplug behavior remain unverified without physical hardware.** Controller sensitivity affects the mock steering path; the root vehicle input router must adopt it during integration.

## Save contract

Current schema **2**:
\`\`\`json
{
  "schema_version": 2,
  "selected_car": "vela_gt",
  "unlocked_cars": ["vela_gt"],
  "credits": 0,
  "completed_events": {},
  "settings": {
    "graphics_quality": "medium", "window_mode": "windowed",
    "resolution": "1280x720", "controller_sensitivity": 0.65,
    "master_volume": 0.8, "music_volume": 0.5, "sfx_volume": 0.85
  }
}
\`\`\`

A completed-event record has \`best_time_s\`, \`wins\`, \`completions\`. Race results award 300 credits and +150 for first place. Orion RS unlocks after any completed event, Kestrel XR after **three distinct** events (not three repeats). Unlock logic is intentionally deterministic. Schema 1 legacy aliases (\`selected_vehicle\`, \`unlocked_vehicles\`, \`race_records\`, \`options\`) migrate to schema 2; unknown versions/invalid types are rejected. Invalid primary files fall back to validated temp then backup, then safe defaults. Corrupt originals are quarantined before overwrite. Operations return failure when disk writes fail; there is no claim of transactional guarantees on every filesystem or power-loss window.

## Tests

Run the headless script above for actual Godot import/runtime/save/transition testing. See \`TEST_REPORT.md\` for the execution status in the authoring environment. This module does not depend on unmerged Art/Core/Racing/World PRs.
