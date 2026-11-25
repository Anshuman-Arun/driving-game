# Phase A QA & Visual Realism Report — Aster Valley

- **Branch:** `feat/environment-realism-swarm`
- **Hardware / Driver:** NVIDIA GeForce RTX 4050 Laptop GPU (Driver `32.0.15.9282` / `592.82`, 6141 MiB VRAM), Windows 11
- **Engine:** `Godot_v4.7.2-stable_win64_console.exe` (Forward+, Vulkan 1.4.325)
- **Harness:** `tests/visual_realism/phase_a_benchmark.gd`

## 1. Pre-Edit Regression Baseline
- `tests/core/smoke.gd` (`--headless`): **PASS** (`Core driving smoke failures: 0`, 27 assertions)
- `tests/integration/roadworks_check.gd` (`--headless`): **PASS** (`Verified five widened approaches and three crossings`, 0 failures)

## 2. BEFORE Baseline Performance (Cedar Woods 417.3 m Corridor, `lane_alder_cedar_ab`)

| Config | Window | Internal 3D | AA / Upscaler | Speed (mph) | Mean FPS | 1% Low FPS | FT med / p95 / p99 (ms) | GPU med / p95 / p99 (ms) | CPU med / p95 (ms) | Draw Calls med / max | Primitives med / max | Static / Video MiB |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Native 100% (`medium`) | 3440×1440 | 3440×1440 | TAA | 55.5–57.7 (med 56.0) | **93.0** | **70.6** | 10.70 / 13.19 / 13.73 | 9.96 / 11.86 / 12.19 | 1.30 / 2.01 | 369 / 637 | 4.47M / 6.90M | 298.0 / 800.9 |
| Scaled 75% (`medium`) | 3440×1440 | 2580×1080 | FSR2 | 55.6–57.7 (med 56.0) | **86.3** | **57.5** | 11.37 / 14.35 / 15.08 | 10.50 / 11.93 / 12.27 | 1.54 / 2.88 | 477 / 734 | 4.62M / 6.90M | 309.7 / 997.4 |

**Baseline Perf Note:** Native 3440×1440 TAA currently runs at 93.0 FPS (10.70 ms median), leaving ~6.0 ms GPU headroom below 60 FPS (16.67 ms). At current light scene complexity, FSR2's temporal upscaling overhead (+0.54 ms GPU, +196.5 MiB VRAM) makes 75% FSR2 slightly slower than native 100% TAA; Cycle 1 will re-evaluate 75% FSR2 vs 75% TAA/FXAA vs 100% TAA once dense foliage and SSAO land.

## 3. BEFORE Visual Critique & Scores (0–5)

| Criterion | BEFORE Score | Observed Defects (from locked 3440×1440 captures) |
|---|---|---|
| Grass coverage & blade shape | **1.5 / 5** | Sparse dark-green tufts over flat olive/yellow ground; stiff pale/white grass/flower spikes (`01`, `02`, `05`, `08`); bare road verges (`04`). |
| Tree silhouette & species | **1.5 / 5** | Repetitive procedural cone conifers with planar card slabs and blocky grey trunks (`01`–`05`); umbrella-fan broadleaf trees (`06`–`08`). |
| Undergrowth & layering | **1.0 / 5** | Missing ferns, woodland shrubs, saplings, and forest debris; isolated neon-green blob bushes (`01`, `03`); boulders perched awkwardly on steep slopes (`01`, `09`). |
| Depth & composition | **2.0 / 5** | Bare, open hillsides lacking forest corridor enclosure (`01`–`03`, `09`); stepped shoreline water edges (`10`). |
| Lighting & contact grounding | **2.0 / 5** | `aster_valley_environment.gd` sets `ssao_enabled = false` and `light_angular_distance = 0.0`, leaving tree bases (`05`), grass tufts, and car (`01`, `07`) weakly grounded. |
| Asphalt & terrain cohesion | **2.0 / 5** | Over-cracked longitudinal asphalt lines (`01`, `04`, `06`), harsh dark-brown shoulder seams (`02`, `04`), flat junction pads (`07`, `08`), mismatched ground vs grass colors. |
| Performance & popping | **4.0 / 5** | 93.0 FPS native 3440×1440 baseline headroom; minor distant fog cutoff in overview (`03`). |

## 4. Cycle 1 & Cycle 2 Results
*(Pending worker integration — baseline locked and cleared for W4/W5 edits.)*
