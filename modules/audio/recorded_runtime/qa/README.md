# Recorded Audio QA Subsystem (Track E)

The QA subsystem provides automated verification of the Aster Valley modular recorded audio pipeline (`modules/audio/recorded_runtime/`).

## Architecture & Components

1. **Asset Verifier (`asset_verifier.gd`)**
   - Validates all recorded engine WAV loops, tire sounds, ambience beds, and fallback SFX.
   - Decodes PCM 16-bit headers, enforces 48 kHz mono specifications.
   - Evaluates non-zero signal presence, peak dBFS, RMS dBFS, and loop boundary continuity (seam delta).
   - Validates loading into Godot `AudioStreamWAV` with forward loop configuration (`loop_begin = 0`, `loop_end = frames`).

2. **Deterministic Telemetry Test Bench (`telemetry_test_bench.gd`)**
   - Headless, repeatable physics/telemetry generator supporting 3 vehicle profiles:
     - **Vela GT**: Flat-six engine, 950 idle RPM, 8500 redline RPM, 7-speed gearbox.
     - **Kestrel XR**: V8 twin-turbo engine, 800 idle RPM, 7800 redline RPM, 7-speed gearbox.
     - **Orion RS**: Four-cylinder rally engine, 1000 idle RPM, 8000 redline RPM, 6-speed gearbox.
   - Eleven sequenced driving regimes (31.0 seconds total per profile):
     1. `idle_stationary`: 1.0s at idle, 0 speed.
     2. `rpm_sweep_idle_to_redline`: Full-throttle sweep from idle to redline.
     3. `throttle_transitions`: Tip-in, steady load, and lift-off overrun triggers.
     4. `gear_shifts`: Gear transitions with torque-cut envelope and shift clunks.
     5. `reverse_maneuver`: Gear -1 selection, reverse pedal mapping, negative velocity.
     6. `surface_transitions`: 24 m/s driving over asphalt, gravel, and grass.
     7. `jumps_and_landings`: Airborne roll fade followed by touchdown suspension compression thump.
     8. `wall_proximity`: Proximity sweeps (20m -> 2m -> 20m) for raycast reflections.
     9. `high_speed_wind`: Acceleration past 22 m/s onset up to 72 m/s.
     10. `lateral_slip_and_braking`: Moderate slip (scrub), high slip (screech), and stationary squeal gating.
     11. `camera_perspective_switching`: Cockpit muffling & intake boost vs. chase clarity.

3. **Audio Effect Capture Runner (`audio_capture_runner.gd`)**
   - Coordinates end-to-end headless audio integration.
   - Applies canonical `AsterAudioBusBuilder` bus layout.
   - Attaches `AudioEffectCapture` to the `Master` bus.
   - Feeds telemetry to `RecordedEngineController`, `RecordedTireController`, `ChassisAudioController`, and `AsterCameraMixController`.
   - Real-time DSP analysis: measures peak dBFS, RMS dBFS, dynamic headroom, and flags any digital clipping (> 0 dBFS or hard flats).
   - Exports results to `tests/integration/audio_qa/results.json`.

## Usage & Execution

```bash
# Full Godot Integration QA Runner
godot --headless --script tests/integration/audio_qa/run_audio_qa.gd

# Telemetry Test Bench Unit Verification
godot --headless --script tests/integration/audio_qa/test_telemetry_bench.gd

# Offline Asset Integrity Verification
python tests/integration/audio_qa/verify_assets.py
```
