# Integrator hand-off / status (2026-11-21)

- Feature branch: `feat/audio`, **only** `modules/audio/**` modified, base `main`.
- Does not alter `project.godot`, vehicle physics, shared docs or other workstreams. No integration claims while core PR #6 is unmerged.
- Bootstrap Godot root game with `AsterAudioController` and call `bind_gevp_vehicle(vehicle_body)` once after the body is added to scene tree. For any non-GEVP engine, use `update_telemetry` with units documented in README.
- Manual collision and suspension methods are safe for callers with their own events. Keep the demo project under `modules/audio/project.godot` isolated; the demo scene uses paths relative to the module root.
- Verification: original generator executed; `python -m unittest discover -s modules/audio/tests -v` passed (2 cases/20 WAVs); all WAVs mono PCM16 at 22.05 kHz, peak ceiling <=0.80, test sample regeneration and loop boundary checked. Godot import/engine tests and audible playback remain **pending** because Godot is not installed in this environment.
- Proposed shared `docs/PROJECT_STATUS.md` update for lead: Audio branch generated 20 CC0 synthetic WAV assets, GDScript controller and standalone demo, Python tests pass, Godot runtime/manual tests outstanding, do not merge until Godot 4.7.2 checks pass.
