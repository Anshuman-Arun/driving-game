# Aster Valley · Original Offline Audio System

This is a self-contained Godot **4.7.2** audio module. It requires no add-ons, network access, proprietary recordings, or global audio buses. The standalone module project uses Godot's lightweight GL Compatibility renderer; the main game can continue to use Forward+.

## What's implemented

- Three original synthetic drivetrains: `vela_gt` (rounded six-cylinder character), `orion_rs` (bright high-revving four-cylinder character), `kestrel_xr` (low/throaty eight-cylinder character). Each has low/mid/high seamless-periodic PCM engine layers with speed/RPM pitch and throttle/load crossfading. Engine braking/overrun and short gearshift attenuation/transient are modeled.
- Asphalt, dirt/gravel and grass rolling, low/high grip tire squeal/skid, wind versus speed, countryside beds, gearbox shifts, collisions, and suspension-thump one-shots.
- `AsterAudioController` takes ordinary telemetry dictionaries and optionally samples the current `Vehicle` / `Wheel` implementation in PR #6 through `AsterAudioTelemetry`. Supports alternative vehicles via `update_telemetry()` without importing vehicle scripts. No shared-code modifications.
- A self-contained graphical test bench with RPM, throttle, load, speed, slip, grip, gear, handbrake, contact, surface and car-profile controls, and manual events.

## Audition the standalone demo

```bash
# Run from the full repository checkout; no root game project is required.
godot --path modules/audio --editor
godot --path modules/audio
```

Choose a car, drag RPM/load/throttle sliders, then try speed, road surface, lateral slip and handbrake. Gear changes automatically produce a short shift transient; the event buttons exercise gearshift, suspension and collision. Turn off ground contact to hear rolling and tire skid disappear. The demo does not require PR #6 to be merged.

## Integration (future integrator; PR #6 is still separate)

After merging the core branch and this module, add from the *vehicle-owning* code (not in this branch):

```gdscript
var audio_script = load("res://modules/audio/audio_controller.gd")
var vehicle_audio = audio_script.new()
add_child(vehicle_audio)
vehicle_audio.set_profile("vela_gt")  # or "orion_rs" / "kestrel_xr"
vehicle_audio.bind_gevp_vehicle(vehicle_body)
```

PR #6 exposes `motor_rpm`, `idle_rpm`, `max_rpm`, `throttle_input`, `brake_input`, `current_gear`, `handbrake_input`, `linear_velocity` and `wheel_array`. Wheels expose `surface_type`, `slip_vector`, `spring_current_length`, and `is_colliding()`. The bridge normalizes `Road→asphalt`, `Dirt→gravel`, `Grass→grass`, estimates grip/slip, and watches compressed suspension. Binding also attaches to `RigidBody3D.body_entered`; PR #6's factory enables `contact_monitor` and 8 reported contacts. If a different vehicle body is used, supply telemetry dictionaries directly and call `trigger_suspension(strength)` / `trigger_collision(strength)` from its physics/contact events.

`update_telemetry()` contract: `rpm`/`idle_rpm`/`max_rpm` as RPM; `speed_mps` (not km/h); `throttle`,`load`,`grip`,`lateral_slip` in `[0,1]`; `gear` integer; `surface` in `asphalt|gravel|grass`; `handbrake`,`on_ground`,`engine_braking` booleans. Unspecified fields have defaults. `compute_targets(Dictionary, String)` is a pure static function to enable deterministic audio-logic smoke tests.

## Rebuild and tests

```bash
python modules/audio/tools/synthesize.py
python -m unittest discover -s modules/audio/tests -v
godot --headless --path modules/audio --editor --quit
godot --headless --path modules/audio --script res://tests/godot_smoke.gd
godot --headless --path modules/audio --script res://tests/godot_regression.gd
```

The generator uses only the Python standard library and fixed mathematical frequencies/phases. Outputs 20 distinct **22,050 Hz, mono, signed 16-bit PCM WAV** files (nine engine layers, eight looped effects, three one-shots). No downloading. Deterministic tests assert sample-by-sample regeneration, headroom, minimum loop duration, seam slope and profile distinctions. Engine loops and background beds are periodic with integer-frequency components over an integer number of seconds, avoiding hard splice points. Godot loops use `AudioStreamWAV.LOOP_FORWARD`.

**Validation performed in the authoring environment:** Python assets regenerated; 2 Python test cases passed on 20 WAVs. **Not run:** Godot 4.7.2 project import, live audio output, headphones/speakers listening, Windows playback or integration, because no Godot executable/audio playback device was available here. Do those before audio mix acceptance. No claim of measured loudness, performance or runtime safety on Windows.


## Runtime-readiness follow-up (2026-11-21; `fix/audio-runtime-readiness`)

Loop boundaries use **decoded stream duration × sample rate**, not the imported WAV resource byte count: Godot can encode imported WAVs as Quite OK Audio (QOA), so dividing `wav.data.size()` by two is not a valid sample-frame count. Godot import and listening must still check actual seams.

The controller now uses **two three-voice engine banks for a 0.28-second profile crossfade**, caches one-shot WAV resources, throttles repeat transients and caps event playback at three voices. A conservative simultaneous-peak budget attenuates loop layers before applying the 2D output mix; this is a calculated amplitude guard, **not** a listening or device-peak measurement. Rapid successive profile choices are queued until a fade finishes.

The GEVP bridge reads the current PR #6 properties without importing core scripts. It recognizes Core `VehicleAdapter`'s **swapped reverse pedals**, both the lateral wheel-slip angle (`slip_vector.x`) and longitudinal wheel slip (`slip_vector.y`), and the dominant contacted wheel surface. `speed_mps` stays an unsigned speed magnitude; the additive `forward_speed_mps` is positive forward/negative reverse. The established telemetry keys are unchanged. Binding a new vehicle suppresses false gearshift transitions; `unbind_gevp_vehicle()`, `bind_gevp_vehicle(null)`, and loss of a freed body reset motion telemetry without dereferencing invalid objects. Suspension sampling tolerates wheels missing optional properties.

To connect after integrating the audio directory into the **root Godot project**, instantiate the controller from `res://modules/audio/audio_controller.gd`, `add_child(vehicle_audio)`, select `set_profile("vela_gt")` (or `orion_rs` / `kestrel_xr`), then call `vehicle_audio.bind_gevp_vehicle(vehicle_adapter.vehicle)` **using the actual GEVP `Vehicle` body**, not the `VehicleAdapter` object. If the body changes, call `bind_gevp_vehicle(new_body)`; call `unbind_gevp_vehicle()` on intentional detachment. The controller reads telemetry in physics ticks. Collision transients require a `RigidBody3D` with `contact_monitor` enabled and sufficient `max_contacts_reported`; alternatively invoke `trigger_collision(strength)` and `trigger_suspension(strength)` directly. Do not run both body-auto collision playback and manual collision playback for the same contact if you want a single transient.

**Regression coverage:** in addition to the existing `godot_smoke.gd`, run `godot_regression.gd` after editor import. It exercises idle/high RPM, throttle lift, all surfaces, slip, handbrake, contact, forward/reverse, three profile changes, one-shot cooldowns, peak-budget behavior, binding/unbinding and freed bodies using a GEVP-shaped test double. Run with a headless Godot binary for deterministic API-level checks, then separately open the GUI demo on a machine with real speakers/headphones to check loop seams, perceived balance and clipping.

**Executed for this follow-up:** Python's 2 existing asset tests passed on a clean generated set of all 20 WAV files, and independently calculated Git blob hashes of all 20 files matched the original remote GitHub asset hashes byte for byte. The original synthesis and WAV assets were not changed. **Not executed:** Godot 4.7.2 editor import, either GDScript suite, playable demo or subjective listening. The available authoring runtime has no `godot`/ `godot4` binary; direct downloads fail DNS resolution. An expanded CI run was subsequently found, but it checked out **the older `feat/audio`**, not this correction branch. Do **not** treat any PR #19 native gate as passed until a Godot-equipped runner executes the commands above against its current head.

## Native CI findings and reproducibility (2026-11-21)

[Expanded-validation run 44955678724](https://github.com/Anshuman-Arun/driving-game/actions/runs/44955678724), job `audio — feat/audio` (job 137003136643), actually used **Python 3.12.12** and **Godot 4.7.2** with source SHA `68ec585f`. The original 2 Python methods and the Godot editor import **passed**. Full WAV regeneration completed but `git diff --exit-code -- modules/audio/assets` **failed for all 20 WAVs**. The smoke script **failed parsing at line 17** before its runtime checks; the newer regression suite was not executed. These are results for `feat/audio` only, not PR #19.

CI's passing sample-by-sample Python test establishes that the decoded PCM arrays matched before the rewrite. The CI output does not include a byte-offset comparison of the old and newly written WAV containers. To stabilize exact file bytes across Python WAV-writer versions, the generator now explicitly serializes the canonical **44-byte RIFF/PCM header** with fixed little-endian fields. `test_assets.py` checks full WAV bytes as well as the original samples. The 20 committed sound files and CC0 provenance are unchanged.

**Actually executed for this update:** with Python 3.13.5, the reconstructed `modules/audio` generator and original + extended asset tests passed **2/2**; repeated generation kept all **20/20** SHA-256 hashes identical, and their Git blob SHA-1s matched all 20 files on the remote audio branch. This is local verification, **not** Python 3.12 Linux CI confirmation. `godot_smoke.gd` now avoids the invalid `:=` inference from `load().new()`; `godot_regression.gd` is still unrun.

**Native blocker:** the current environment has no usable Godot 4.7.2 binary, and the read-only expanded CI workflow on `feat/ci-expansion` explicitly checks out `feat/audio` (not PR #19). Request a targeted runner pass against `fix/audio-runtime-readiness` with the import, original smoke and regression commands above, plus repeat the Python 3.12.12 WAV-diff gate. Only after that should manual Windows speaker/headphone listening and integrated GEVP driving be approved.

## Provenance & license

Every file in `assets/` is **original mathematical synthesis** authored for Aster Valley with `tools/synthesize.py` (including original, synthetic bird-like ambience). No sampled recordings, existing soundtrack, external audio packs or proprietary game media. This original audio is released under **CC0-1.0** by its author for unrestricted redistribution and modification; generator/controller source is supplied under the repository's applicable license (if any). Sound presets and this local provenance register can be mirrored to the shared asset ledger by the eventual integrator; no shared docs were modified in this branch.

## Design / limitations

The controller models player/listener-centered **2D** sound, not positional 3D audio for remote traffic; for NPCs use per-vehicle AudioStreamPlayer3D routing and budget voices. Peak checks protect individual WAV sources, but a device's complete game mix still needs listening/limiter calibration. Avoid exposing global sound buses from this module, because doing so would break exclusive path ownership. Engine character is expressive synthesis rather than a physical cylinder-by-cylinder acoustic simulator.
