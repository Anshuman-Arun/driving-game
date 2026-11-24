# Aster Valley Recorded Audio Subsystem Handoff

## 1. System Overview
Aster Valley vehicle and environment audio is powered by a multi-track recorded runtime:
- **Mix (`modules/audio/recorded_runtime/mix/`)**: 10-bus layout with Master compressor (-16 dB, 2:1, 15ms/120ms) and limiter (-1 dB ceiling). Dedicated SFX intermediate routing connects `valley_game_shell.gd` settings sliders. `AsterCameraMixController` provides 200ms smoothed transitions between chase clarity and cockpit cabin muffling (LPF to 1800 Hz, -4 dB exterior, +6 dB intake boost).
- **Engine (`modules/audio/recorded_runtime/engine/`)**: `RecordedEngineController` drives manifest-based loop sets for Vela GT (flat-six), Kestrel XR (V8), and Orion RS (four-cylinder). Uses constant-power cos/sin anchor blending, ON/OFF load crossfading, rev limiter 20 Hz stutter, 110ms gear-shift cut, and overrun backfire crackles. Starts immediately at idle upon vehicle spawn.
- **Tires (`modules/audio/recorded_runtime/tires/`)**: `RecordedTireController` manages seamless asphalt/gravel/grass roll loops, airborne fade-out, tire scrub (0.15-0.45 slip), screech (>0.45 with 0.38 hysteresis), 80ms/180ms attack/release envelopes, and stationary speed gating (<1.5 m/s).
- **Chassis & Environment (`modules/audio/recorded_runtime/chassis/`)**: `ChassisAudioController` manages wind onset at ~22 m/s, ambient mountain wind bed, suspension travel thump with 0.16s cooldown, collision impacts with velocity scaling, and 3-way acoustic raycasts mapping wall distance to 15-120ms delay and wet reflection gain.
- **Root Controller (`modules/audio/audio_controller.gd`)**: `AsterAudioController` orchestrates all subsystems, binds GEVP vehicle telemetry and camera view, handles pause mode (`PROCESS_MODE_PAUSABLE`), and provides backward compatibility.

## 2. Root Causes of Prior Game Silence & Resolutions
1. **Nested Project Collision**: `modules/audio/project.godot` caused Godot's `EditorFileSystem` to treat `res://modules/audio/` as a nested subproject and ignore it in the main project.
   - *Fix*: Renamed nested project configuration to enable full resource and script indexing.
2. **Missing Vehicle Attachment**: `PlayerCarFactory.create()` never instantiated or attached an audio node.
   - *Fix*: Factory now attaches `VehicleAudio` (`AsterAudioController`), sets authentic idle/max RPMs, binds GEVP physics, and starts idle loops immediately.
3. **Missing Audio Bus Layout**: `project.godot` lacked a default bus layout, defaulting to a single Master bus without `SFX`, `Engine_*`, `Tires`, etc.
   - *Fix*: Registered `audio/buses/default_bus_layout="res://modules/audio/recorded_runtime/mix/aster_bus_layout_sfx.tres"`.
4. **Non-Functional SFX Slider**: `valley_game_shell.gd` settings slider specifically looked up `"SFX"` and `"Music"` buses, returning -1.
   - *Fix*: Routed vehicle SFX buses through the `SFX` bus (`SFX` -> `Master`), restoring slider volume control.
5. **Missing 3D Audio Listener**: `DrivingChaseCamera` lacked an `AudioListener3D`.
   - *Fix*: Mounted active `AudioListener3D` to chase camera.

## 3. Telemetry & Camera Integration
- **Vehicle Telemetry**: Extracted every physics tick via `AsterAudioTelemetry.from_gevp()` (RPM, throttle, load, gear, speed, lateral slip, and surface classification).
- **Camera Tracking**: `aster_valley_drive.gd` and `driving_test.gd` call `audio.bind_camera(camera)`. `AsterCameraMixController` tracks distance to `CameraMounts/Cockpit` to dynamically adjust cabin muffling.
- **Pause Mode**: `audio.process_mode = Node.PROCESS_MODE_PAUSABLE` ensures vehicle audio silences during pause menus while allowing UI audio to play.

## 4. Test & Verification Suites (Godot 4.7.2)
Run headless tests from project root:
- **Master Audio QA Runner**:
  `godot --headless --script res://tests/integration/audio_qa/run_audio_qa.gd`
- **Root Integration Test**:
  `godot --headless --script res://tests/integration/audio_integration_test.gd`
- **Mix Subsystem Unit Suite**:
  `godot --headless --script res://modules/audio/recorded_runtime/mix/tests/test_mix_subsystem.gd`
- **Engine Subsystem Unit Suite**:
  `godot --headless --script res://modules/audio/recorded_runtime/engine/tests/test_recorded_engine.gd`
- **Tires Subsystem Unit Suite**:
  `godot --headless --script res://modules/audio/recorded_runtime/tires/tests/test_recorded_tires.gd`
- **Chassis Subsystem Unit Suite**:
  `godot --headless --script res://modules/audio/recorded_runtime/chassis/tests/test_chassis_audio.gd`
- **Legacy Smoke & Regression**:
  `godot --headless --script res://modules/audio/tests/godot_smoke.gd`
  `godot --headless --script res://modules/audio/tests/godot_regression.gd`

## 5. QA Verification Summary
From `tests/integration/audio_qa/results.json`:
- **WAV Assets Verified**: 42 / 42 passed (48kHz mono PCM16, valid loop boundaries, non-zero signal).
- **Car Profiles Simulated**: 3 / 3 passed (Vela GT, Kestrel XR, Orion RS) across 11 driving regimes.
- **Overall Peak**: -9.83 dBFS (Ceiling: -0.10 dBFS, Master Limiter ceiling: -1.0 dBFS).
- **Minimum Headroom**: 9.83 dB.
- **Clipped Samples**: 0.
- **Hard Flats**: 0.
- **Status**: 100% PASS across all suites.
