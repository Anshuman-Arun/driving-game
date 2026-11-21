# Integrator hand-off / status (2026-11-21)

- Feature branch: `feat/audio`, **only** `modules/audio/**` modified, base `main`.
- Does not alter `project.godot`, vehicle physics, shared docs or other workstreams. No integration claims while core PR #6 is unmerged.
- Bootstrap Godot root game with `AsterAudioController` and call `bind_gevp_vehicle(vehicle_body)` once after the body is added to scene tree. For any non-GEVP engine, use `update_telemetry` with units documented in README.
- Manual collision and suspension methods are safe for callers with their own events. Keep the demo project under `modules/audio/project.godot` isolated; the demo scene uses paths relative to the module root.
- Verification: original generator executed; `python -m unittest discover -s modules/audio/tests -v` passed (2 cases/20 WAVs); all WAVs mono PCM16 at 22.05 kHz, peak ceiling <=0.80, test sample regeneration and loop boundary checked. Godot import/engine tests and audible playback remain **pending** because Godot is not installed in this environment.
- Proposed shared `docs/PROJECT_STATUS.md` update for lead: Audio branch generated 20 CC0 synthetic WAV assets, GDScript controller and standalone demo, Python tests pass, Godot runtime/manual tests outstanding, do not merge until Godot 4.7.2 checks pass.

## Runtime-readiness follow-up — PR #19 (unmerged draft, targeting `feat/audio`)

- Branch `fix/audio-runtime-readiness`, exclusively `modules/audio/**`. No shared project, vehicle or world files changed.
- Core PR #6 read-only: `VehicleAdapter.vehicle` is the GEVP body. The adapter swaps driving pedals in reverse. Bind that body with `vehicle_audio.bind_gevp_vehicle(vehicle_adapter.vehicle)` after adding the controller; select profiles with `set_profile("vela_gt")` etc.; rebind on car changes and `unbind_gevp_vehicle()` when detached.
- Corrected QOA/PCM WAV loop frame calculation, introduced engine-bank crossfades, event caching/cooldowns, bounded polyphony and summed loop peak guard. Telemetry handles longitudinal/lateral slip and freed bodies. `tests/godot_regression.gd` is a new deterministic GEVP-shaped bench, **not yet executed**.
- Executed: `python modules/audio/tools/synthesize.py` on the existing generator reconstructed in a scratch workspace, then `python -m unittest discover -s modules/audio/tests -v`: 2/2 pass. The generated WAVs have Git blob SHA-1 values exactly equal to all 20 GitHub `feat/audio` assets. Original synth code and asset files unchanged.
- Attempted `godot --version`, headless editor import, `godot_smoke.gd`, and `godot_regression.gd`: all exit **127** with `godot: command not found`. DNS prevents downloading the binary; no audio device is exposed at `/dev/snd`. No branch Actions runs are available. Import, parser/runtime behavior, GUI playback and listening remain blocked and must not be called passes.
- On a Godot 4.7.2 machine: run `godot --headless --path modules/audio --editor --quit`, `godot --headless --path modules/audio --script res://tests/godot_smoke.gd`, `godot --headless --path modules/audio --script res://tests/godot_regression.gd`, then `godot --path modules/audio` with speakers/headphones. Keep PR #19 unmerged until these are verified.
