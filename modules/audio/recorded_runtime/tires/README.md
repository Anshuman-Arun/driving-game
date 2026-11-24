# Track C: Recorded Tire Sound Controller

Located in `modules/audio/recorded_runtime/tires/`.

## Architecture Overview

`RecordedTireController` (`recorded_tire_controller.gd`) manages physical tire and surface acoustics for Aster Valley:
- **Wheel Telemetry Ingestion**: Seamlessly reads telemetry from live GEVP `Vehicle` nodes (evaluating `wheel_array`, `is_colliding()`, `slip_vector`, and `surface_type`) or duck-typed telemetry dictionaries (via `AsterAudioTelemetry` or QA harnesses).
- **Surface Roll Loops**: Continuous, seamless looping surface audio for `asphalt`, `gravel`, and `grass`.
  - Uses `assets/audio/recorded/payload/tires/roll_gravel.wav` (48 kHz mono PCM16) for gravel.
  - Fallbacks and surface loops for `roll_asphalt.wav` and `roll_grass.wav` are automatically resolved.
  - Speed-dependent pitch (`0.65` to `1.55`) and volume (`smoothstep(0.5, 30.0, speed)`).
  - Airborne fade-out with ~100ms time constant upon loss of wheel ground contact.
- **Tire Scrub & Screech**:
  - Moderate slip (`0.15` to `0.45`): **Tire scrub** provides textured, low-pitched rubber friction.
  - Severe slip (`> 0.45`): **Tire screech** triggers high-slip squeal using `assets/audio/recorded/payload/tires/screech.wav`.
  - **Hysteresis**: Enters screech at `slip >= 0.45`, but does not exit back to scrub until `slip < 0.38`. This eliminates chattering around the break of traction.
- **Envelope Followers**:
  - Attack: ~80ms (`ATTACK_TIME_S = 0.080`)
  - Release: ~180ms (`RELEASE_TIME_S = 0.180`)
  - Prevents clicks, pops, and jarring transitions.
- **Stationary Speed Gate**:
  - Speed below `1.5 m/s` (~5.4 km/h) completely gates out squeal and scrub, eliminating stationary squeal when turning or parked.
  - Smooth ramp from `1.5 m/s` to `3.5 m/s` where full squeal amplitude is enabled.
- **Audio Bus Routing**:
  - Automatically targets the `Tires` bus (falling back to `SFX` or `Master` if custom layouts are not yet registered).

---

## Class Reference

### `RecordedTireController` (`recorded_tire_controller.gd`)
Extends `Node`.

#### Key Methods:
- `bind_vehicle(vehicle: Node)`: Attaches a vehicle node for automatic per-physics-tick telemetry extraction.
- `unbind_vehicle()`: Clears bound vehicle reference and silences vehicle-driven telemetry.
- `update_telemetry(telemetry: Dictionary, delta: float = 0.0167)`: Ingests normalized dictionary telemetry.
- `compute_tire_targets(telemetry: Dictionary, state: Dictionary, delta: float = 0.0167) -> Dictionary`: Pure deterministic synthesis target calculator for tests and QA benches.
- `get_players() -> Dictionary`: Returns `{ "roll_asphalt": ..., "roll_gravel": ..., "roll_grass": ..., "scrub": ..., "screech": ... }`.
- `get_debug_state() -> Dictionary`: Returns a snapshot of internal envelope values, speed gates, and surface weights.

#### Export Properties:
- `master_tire_gain: float` (default `1.0`): Overall master gain for all tire sounds.
- `roll_gain: float` (default `0.85`): Surface rolling volume scalar.
- `scrub_gain: float` (default `0.70`): Tire scrub volume scalar.
- `screech_gain: float` (default `0.85`): Tire screech volume scalar.
- `is_enabled: bool` (default `true`): Subsystem enable flag.

---

### `AsterTireTelemetry` (`tire_telemetry.gd`)
Extends `RefCounted`.

#### Key Methods:
- `from_vehicle(vehicle: Node) -> Dictionary`: Extracts `speed_mps`, `slip_amount`, `on_ground`, `surface`, and `surface_weights` from a GEVP `Vehicle` and its `wheel_array`.
- `from_dictionary(dict: Dictionary) -> Dictionary`: Normalizes input from `AsterAudioTelemetry`, bridge, or QA test runner.
- `normalize_surface(raw: String) -> String`: Maps surface strings ("dirt", "gravel", "grass", "road", etc.) to `"asphalt"`, `"gravel"`, or `"grass"`.

---

## Integration Guide (for `@integrator`)

To use in `audio_controller.gd` or vehicle scene:

```gdscript
const RecordedTireControllerScript = preload("res://modules/audio/recorded_runtime/tires/recorded_tire_controller.gd")

var tire_controller: RecordedTireController

func _ready() -> void:
    tire_controller = RecordedTireControllerScript.new()
    add_child(tire_controller)

func bind_car(car: Node3D) -> void:
    tire_controller.bind_vehicle(car)

# Or update explicitly each tick:
func update_audio(telemetry_dict: Dictionary, delta: float) -> void:
    tire_controller.update_telemetry(telemetry_dict, delta)
```

---

## Test Suite (for `@qa`)

Run the standalone verification suite:
```bash
godot --headless --path . --script res://modules/audio/recorded_runtime/tires/tests/test_recorded_tires.gd
```
Verification checks:
1. Audio stream loading, valid loop endpoints (`loop_end = frames - 1`), and bus assignment.
2. Telemetry normalization from vehicle and dictionaries.
3. Speed gating (< 1.5 m/s silent, > 3.5 m/s enabled).
4. Scrub range (`0.15 - 0.45`) and Screech hysteresis (`> 0.45` entry, `< 0.38` exit).
5. Attack (~80ms) and release (~180ms) envelope timing.
6. Airborne fade-out on loss of ground contact.
7. Dynamic surface transitions between asphalt, gravel, and grass.
