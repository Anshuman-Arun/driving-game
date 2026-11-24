# Track D: Chassis, Environment, and Acoustics Controller

`modules/audio/recorded_runtime/chassis/`

Provides runtime audio systems for vehicle chassis, environmental wind, and acoustic space reflections in Aster Valley.

## Components

1. **`ChassisAudioController` (`chassis_audio_controller.gd`)**
   - Unified master node (extends `Node3D`) that coordinates wind, ambience, suspension, collision, and acoustics.
   - Can be attached directly as a child of any player car (`VehicleAdapter` / GEVP `Vehicle`) or integrated into `AsterAudioController`.
   - Exposes public methods: `bind_vehicle(vehicle)`, `update_telemetry(telemetry)`, `trigger_impact(velocity, strength)`, `trigger_suspension(strength)`, `trigger_landing(speed)`, `simulate_acoustics(left, right, up)`.

2. **`ChassisWind` (`chassis_wind.gd`)**
   - Dynamic airflow wind noise with onset at ~22 m/s (`onset_speed_mps = 22.0`).
   - Exponential volume curve (`wind_exponent = 1.8`) scaling up to top speed.
   - Dynamic lowpass filter shaping from 800 Hz up to 14,000 Hz, with pitch modulation (0.92 to 1.25).
   - Continuous ambient wind bed (`assets/audio/recorded/payload/ambience/mountain_wind_bed.wav`) routed to `Ambience` bus.
   - Wind noise routed to `Wind_Chassis` bus.

3. **`ChassisSuspension` (`chassis_suspension.gd`)**
   - Suspension travel and compression audio driven by `(spring delta / delta time)`.
   - Landing/contact thump when transitioning from airborne to grounded state.
   - Cooldown timer of ~0.16s to suppress flutter and multi-wheel trigger noise.
   - Collision impact audio with velocity-scaled volume and ~0.12s cooldown.
   - Routed to `Wind_Chassis` or `Master` bus.

4. **`ChassisAcoustics` (`chassis_acoustics.gd`)**
   - 3-directional raycasting: Left (-X), Right (+X), Up (+Y) up to 20 meters.
   - Executes every 4 physics ticks (`physics_tick_interval = 4`).
   - Proximity mapping: maps wall distance (1.0m to 20.0m) to echo delay (15ms to 120ms) and wet gain (0.85 to 0.08) on `Exhaust_Reflection` bus.
   - Open terrain clamp and bypass: when all rays miss or distance > 20m, automatically sets wet gain to 0.0 (-80 dB) and bypasses delay effect.

5. **`ChassisWavLoader` (`wav_loader.gd`)**
   - Safe audio asset loading utility that handles both Godot-imported resources and raw unimported PCM WAV files.

## Test Suite

Run the headless verification test:
```bash
godot --headless --script modules/audio/recorded_runtime/chassis/tests/test_chassis_audio.gd
```
Verifies all 7 subsystems deterministically.
