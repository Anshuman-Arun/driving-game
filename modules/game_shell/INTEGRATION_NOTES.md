# Integrator handoff — game shell

Only `modules/game_shell/` changed. Shared status docs and other agents' paths deliberately untouched.

## Attach to the real Godot project

1. After the Core/Art/Racing PRs are reviewed and merged, instantiate `res://modules/game_shell/scripts/game_shell.gd` as a `Control` under a fullscreen `CanvasLayer`. Do **not** copy the standalone `project.godot` over the root project. Its relative script preloads already work inside the repository tree.
2. Replace the constructor-created `MockGame` in `game_shell.gd` with an adapter that exposes the **same** data/state methods and emits `stage_changed(stage)`. The shell's UI expects `speed_kph`, `gear`, `stage`, `lap`, `race_position`, `race_time_s`, `countdown_s`, `notification`, `result`, `current_event()`, `advance()`, `start_event()`, `finish_event()`, and `return_to_free_roam()`. Map units: VehicleAdapter m/s → km/h by ×3.6.
3. Wire the real RaceEngine from Track C: `state_changed` → shell countdown/racing/results; `checkpoint_passed`, `lap_completed`, `racer_finished` → HUD; `standings()` → position. Only **authoritative finished results** may call `SaveService.record_race(event_id, elapsed_seconds, place)`. Do not treat the mock timer or F key as a real finish. Validate event IDs across the host catalog. The actual race engine owns ordered checkpoints/AI movement.
4. Replace schematic `minimap.gd` coordinates with an overlay derived from canonical `road_graph_v1.json` and transform player X/Z into map UV. The mock drawing intentionally cannot be used as road navigation. Avoid editing world data.
5. For 3D garage preview, replace the primitive turntable with `res://assets/curated/models/vehicles/{vela_gt,orion_rs,kestrel_xr}.glb` after the Art PR is merged. Keep original GLB wheel-pivot hierarchy. Preview is strictly visual; the Core VehicleAdapter owns real suspension/physics. Vehicle selection must switch parked real vehicle instances safely, with no mid-race swap.
6. Reconcile `shell_*` default input actions with Core's `DriveInput` and the shared gamepad; do not drive physics twice. Preserve Godot `ui_*` navigation. The shell applies mock steering sensitivity only; move that setting to Core's actual controller as needed. Pause should ultimately freeze the authoritative race/physics loop, not just this mock clock.
7. Create optional Music/SFX audio buses in the host layout before expecting the saved values to affect them. Master bus always applies. Reconcile graphics presets with the actual engine/terrain/LOD quality settings (the demo currently changes 3D viewport scale only).
8. The host must define its `user://` profile strategy, including whether save version 2 replaces any existing future saves. Backups and migrate-v1 code are already implemented; do not edit a live save file by hand.

## No shared-document edits

Requested `docs/PROJECT_STATUS.md` updates are deferred to the integration owner because parallel-workstream ownership explicitly disallows edits there. This handoff and `TEST_REPORT.md` are the scoped record. No auto-merge; obtain Godot runtime, hardware input and Windows-export results before approval.

## Independent verification commands

```sh
godot --headless --path modules/game_shell --editor --quit
godot --headless --path modules/game_shell --script res://tests/run_tests.gd
godot --path modules/game_shell
```

Do not run those as root `--path .` until the shell is integrated; its standalone resources resolve from the module project root.
