# Recorded Engine Sound Controller (Track B)

`modules/audio/recorded_runtime/engine/`

The Recorded Engine Sound Controller provides manifest-driven, multi-anchor granular playback of recorded car engine audio in Godot 4.7.2. It supports seamless switching between:
- **Vela GT** (`vela_gt`): Flat-six sports exhaust (7 ON loops, 7 OFF loops, 2000–8000 RPM).
- **Kestrel XR** (`kestrel_xr`): V8 performance engine (7 ON loops, 5 OFF loops, 1000–7000 RPM).
- **Orion RS** (`orion_rs`): Four-cylinder fallback engine (6 ON loops, single-layer fallback, 1000–8000 RPM).

---

## Architecture & Components

1. **`EngineWavLoader`** (`engine_wav_loader.gd`):
   - Runtime loader supporting Godot's `ResourceLoader`, `AudioStreamWAV.load_from_file`, and a direct binary RIFF/WAV parser fallback.
   - Programmatically sets `loop_mode = AudioStreamWAV.LOOP_FORWARD`, `loop_begin = 0`, and `loop_end = round(length * mix_rate)`.
   - All 32 engine WAV files decode to 48 kHz mono PCM16.

2. **`EngineProfileManifest`** (`engine_profile_manifest.gd`):
   - Locates and parses `assets/audio/recorded/payload/engines/{profile}/manifest.json`.
   - Organizes anchors into ascending sorted `on_anchors` and `off_anchors`.
   - Implements `find_bracketing_anchors(layer, rpm)` to locate the lower anchor, higher anchor, and normalized crossfade fraction $t \in [0, 1]$.

3. **`RecordedEngineController`** (`recorded_engine_controller.gd`):
   - Main `Node` controller.
   - **Constant-Power RPM Blending**:
     $$gain_{low} = \cos(t \cdot \frac{\pi}{2}), \quad gain_{high} = \sin(t \cdot \frac{\pi}{2})$$
     $$\cos^2 + \sin^2 = 1.0$$
   - **Pitch Scaling**:
     $$pitch = \text{clampf}\left(\frac{current\_rpm}{anchor\_rpm}, 0.75, 1.35\right)$$
     (Smooth sub-idle extension down to $0.45$ for low idle RPM below the lowest anchor).
   - **Smoothing Filters**:
     - Exponential RPM smoothing with time constant $\tau = 45$ ms (range 30–60 ms).
     - Exponential throttle load smoothing with time constant $\tau = 80$ ms.
   - **Load Layer Blending (ON vs OFF)**:
     - Constant-power crossfade based on smoothed throttle:
       $$gain_{on} = \sin(throttle \cdot \frac{\pi}{2}), \quad gain_{off} = \cos(throttle \cdot \frac{\pi}{2})$$
     - Graceful single-layer fallback for profiles without OFF loops (e.g. Orion RS).
   - **Rev Limiter Stutter**:
     - Engages at $\ge 98.5\%$ redline.
     - 20 Hz stutter oscillation alternating between ignition cut ($-18$ dB) and combustion fire.
   - **Gear Shift Torque-Cut Envelope & Clunk**:
     - Triggers on gear changes ($gear \ne 0$).
     - 110 ms torque-cut envelope (80–140 ms configurable range) dipping engine volume down to $0.20$ ($-14$ dB) with smooth recovery.
     - Plays `gearshift.wav` clunk transient.
   - **Overrun Backfire**:
     - Triggers on rapid throttle lift-off ($throttle_{prev} > 0.55 \to throttle < 0.15$) when $RPM / redline > 0.65$.
     - Enforces a 1.2s cooldown between triggers.
     - Fires primary backfire on `overrun.wav` and schedules a random burst of 1–3 delayed crackle pops.
   - **Bus Routing**:
     - Engine loops and backfires route to `Engine_Exhaust`.
     - Induction roar loops route to `Engine_Intake` (scaled with throttle curve).
     - Safely falls back to `Master` if buses are not yet registered in `AudioServer`.
   - **Zero Latency Idle**:
     - `snap_to_idle()` ensures engine audio starts immediately at idle upon vehicle spawn with zero ramp-up delay.

---

## Integration Guide for `@integrator`

Add `RecordedEngineController` as a child node or instantiate via GDScript:

```gdscript
var engine_audio: RecordedEngineController = RecordedEngineController.new()
engine_audio.car_profile = "vela_gt" # or "kestrel_xr", "orion_rs"
engine_audio.exhaust_bus = &"Engine_Exhaust"
engine_audio.intake_bus = &"Engine_Intake"
add_child(engine_audio)
```

On every telemetry or physics tick:

```gdscript
engine_audio.update_telemetry({
    "rpm": vehicle.motor_rpm,
    "throttle": vehicle.throttle_input,
    "gear": vehicle.current_gear,
    "idle_rpm": vehicle.idle_rpm,
    "max_rpm": vehicle.max_rpm
})
```

To switch vehicle profiles dynamically:
```gdscript
engine_audio.set_profile("kestrel_xr")
```

---

## Deterministic Testing for `@qa`

Run the test suite headless with Godot 4.7.2:
```bash
Godot_v4.7.2-stable_win64_console.exe --headless --path wt-audio-swarm-pass1 --script res://modules/audio/recorded_runtime/engine/tests/test_recorded_engine.gd
```

All 9 test suites pass deterministically:
1. `test_manifest_loading`: Verifies manifests for Vela GT, Kestrel XR, Orion RS.
2. `test_wav_loader_and_loop_config`: Verifies all 32 WAV files load at 48 kHz mono with sample-accurate loop points.
3. `test_constant_power_blending`: Sweeps RPM idle to redline and verifies constant power sum $\sum gain^2 = 1.0$ and pitch clamp $[0.75, 1.35]$.
4. `test_load_layer_blending`: Sweeps throttle 0 to 1 and verifies ON/OFF power sum = 1.0.
5. `test_controller_lifecycle_and_smoothing`: Verifies 30–60ms RPM and 80ms throttle smoothing.
6. `test_rev_limiter_stutter`: Verifies 20 Hz oscillation near redline.
7. `test_gear_shift_envelope`: Verifies 110 ms torque-cut envelope and shift clunk.
8. `test_overrun_backfire`: Verifies rapid lift-off above 65% RPM and 1.2s cooldown.
9. `test_profile_switching`: Verifies dynamic switching between Vela, Kestrel, and Orion.
