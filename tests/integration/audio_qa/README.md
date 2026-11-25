# Aster Valley Audio QA Integration Tests

Integration test suite for the recorded vehicle audio subsystems.

## Files

- `run_audio_qa.gd`: Master Godot headless SceneTree script. Executes asset checks, telemetry verification, and Master bus audio capture across Vela GT, Kestrel XR, and Orion RS.
- `test_telemetry_bench.gd`: Validates that the deterministic telemetry bench covers all 11 driving scenarios across all 3 car profiles.
- `verify_assets.py`: Standalone Python script validating offline WAV integrity, PCM 16-bit format, 48 kHz sample rates, and loop seam deltas.
- `results.json`: Output report detailing asset health, telemetry metrics, and captured bus headroom/clipping measurements.

## Standards & Acceptance Criteria

- **Audio File Standards**: 48,000 Hz, 16-bit Mono PCM, valid loop endpoints (`loop_begin = 0`, `loop_end = frames`), non-zero signal (`peak > 0.05`).
- **Dynamic Headroom**: Master bus peak dBFS must not exceed 0.0 dBFS (strictly enforced by Master limiter ceiling of -1.0 dBFS).
- **Clipping Threshold**: 0 samples >= 0.9999 (-0.01 dBFS) and 0 hard flats (runs of identical samples near peak).
- **Signal Presence**: Non-zero audio active across all simulated driving regimes.
