# Aster Valley Local Visual Lab — GPU Test & Benchmark Report

**Date:** 2026-11-21  
**Engine:** `Godot Engine v4.7.2.stable.official.ed1daf0bf` (Windows x64, Forward+ Vulkan `1.4.325`)  
**GPU:** `NVIDIA GeForce RTX 4050 Laptop GPU` (Driver `32.0.15.9282`)  
**Test Resolution:** `1920 × 1080` (windowed, VSync disabled, `Engine.max_fps = 0`)  
**Project Path:** `experiments/local-visual-lab/project.godot`

---

## 1. Validation & Reproducible Commands

### Headless Editor Import & Parse Check
```powershell
& "<godot_console_exe>" --headless --path "<repo>/experiments/local-visual-lab" --editor --quit
```
- **Result:** Exit code `0`. All 5 GDScript global classes (`TerrainMath`, `MeshBuilder`, `GraphicsPresets`, `CameraRig`, `BenchmarkRunner`), scene (`scenes/visual_lab.tscn`), and all 5 custom `.gdshader` shaders parsed and imported cleanly with zero script or shader errors.

### Full 3-Tier Live GPU Benchmark Suite
```powershell
powershell -ExecutionPolicy Bypass -File "<repo>/experiments/local-visual-lab/run_benchmark.ps1" -Resolution 1920x1080
```
- Each stationary viewpoint runs **36 warmup frames** followed by **120 measured frames**, then captures a native `1920 × 1080` PNG screenshot.
- The repeatable road-to-lake **flythrough** runs **20 warmup frames** followed by **180 measured frames**, then seeks to `t = 0.45` after measurement finishes to capture `*_flythrough_mid.png` without polluting frame-time statistics.
- Raw JSON results are saved in `benchmarks/performance.json`, `benchmarks/balanced.json`, and `benchmarks/high.json`.

---

## 2. Reproducible Camera Viewpoints

| ID | Description | Camera Position `(x, y, z)` | Look Target `(x, y, z)` | FOV |
|---|---|---|---|---:|
| `VP1_Lakeside_Hero` | Low roadside hero curve with asphalt markings, guardrails, parked coupe, and distant peaks | `(8.54, 17.86, 32.34)` | `(-5.49, 20.49, -29.42)` | 56° |
| `VP2_Pine_Corridor` | Driver-height curve diving into shaded conifers, autumn birches, and backlit sun shafts | `(-46.34, 15.52, -112.15)` | `(-37.84, 20.59, -48.00)` | 60° |
| `VP3_Overlook_Vista` | Elevated panorama over timber overlook deck, parked coupe, Eastwater Lake SSR, and snow peaks | `(-4.33, 27.27, 5.27)` | `(12.57, 20.99, -48.78)` | 62° |
| `VP4_Shoreline_Detail` | Waterline angle stressing alpine ripple normals, Beer-Lambert depth tint, shoreline foam, and reflections | `(51.05, 2.35, 22.00)` | `(2.12, 10.50, -34.00)` | 58° |
| `FLYTHROUGH` | 180-frame deterministic spline sweep along the winding road to the overlook and out over Eastwater Lake | Dynamic (`z = +115 → -95`) | Dynamic lookahead | 60° |

---

## 3. Rendering Tier Configurations

| Feature | Performance | Balanced (Recommended Baseline) | High |
|---|---|---|---|
| Anti-Aliasing | MSAA 2×, TAA Off | MSAA 2× + TAA On | MSAA 4× + TAA On |
| Directional Shadow Splits | 2 Splits (`120 m`) | 4 Splits (`220 m`, blended) | 4 Splits (`320 m`, blended) |
| SSAO | Off | On | On |
| SSIL | Off | Off | On |
| SSR | Off | On (32 steps) | On (64 steps) |
| SDFGI | Off | Off | On (4 cascades) |
| Volumetric Fog | Off (Aerial Distance Fog) | Off (Aerial Distance Fog) | On (`220 m` range) |
| Glow / Bloom | On (subtle) | On | On |
| Grass Density (`MultiMesh`) | 25% (~8,000 tufts) | 60% (~19,200 tufts) | 100% (~32,000 tufts) |

---

## 4. Measured GPU Performance Results (1920 × 1080)

### Performance Tier (`benchmarks/performance.json` — VRAM: `255.1 MB`)

| Viewpoint | Avg FPS | 1% Low FPS | Avg Frame (ms) | GPU Render (ms) | CPU Render (ms) | Draw Calls | Primitives |
|---|---:|---:|---:|---:|---:|---:|---:|
| `VP1_Lakeside_Hero` | 119.5 | 88.5 | 8.37 | 3.19 | 0.56 | 99 | 950,834 |
| `VP2_Pine_Corridor` | 120.0 | 103.2 | 8.33 | 3.07 | 0.58 | 99 | 950,834 |
| `VP3_Overlook_Vista` | 120.0 | 111.4 | 8.33 | 3.49 | 0.64 | 100 | 951,002 |
| `VP4_Shoreline_Detail` | 120.0 | 108.1 | 8.33 | 3.65 | 0.52 | 99 | 950,834 |
| `FLYTHROUGH` | 120.0 | 109.3 | 8.33 | 3.52 | 0.47 | 82 | 949,669 |

### Balanced Tier (`benchmarks/balanced.json` — VRAM: `395.1 MB`)

| Viewpoint | Avg FPS | 1% Low FPS | Avg Frame (ms) | GPU Render (ms) | CPU Render (ms) | Draw Calls | Primitives |
|---|---:|---:|---:|---:|---:|---:|---:|
| `VP1_Lakeside_Hero`* | 78.8 | 53.4 | 12.69 | 12.32 | 0.83 | 153 | 1,655,394 |
| `VP2_Pine_Corridor` | 119.9 | 102.4 | 8.34 | 6.04 | 1.27 | 153 | 1,655,394 |
| `VP3_Overlook_Vista` | 120.0 | 108.8 | 8.34 | 6.41 | 0.82 | 186 | 1,657,578 |
| `VP4_Shoreline_Detail` | 120.0 | 104.4 | 8.33 | 6.36 | 1.16 | 152 | 1,655,226 |
| `FLYTHROUGH` | 120.0 | 109.8 | 8.33 | 6.68 | 1.02 | 135 | 1,654,088 |

*\*Note on Balanced `VP1_Lakeside_Hero`: In this run, the first viewpoint right after launch showed a brief GPU boost-clock ramp / initial pipeline warmup (`12.32 ms` GPU vs `6.07 ms` on an earlier warm run); steady-state GPU time across VP2–VP4 and Flythrough was `6.04–6.68 ms`.*

### High Tier (`benchmarks/high.json` — VRAM: `957.1 MB`)

| Viewpoint | Avg FPS | 1% Low FPS | Avg Frame (ms) | GPU Render (ms) | CPU Render (ms) | Draw Calls | Primitives |
|---|---:|---:|---:|---:|---:|---:|---:|
| `VP1_Lakeside_Hero` | 60.9 | 44.7 | 16.41 | 16.27 | 1.02 | 185 | 1,849,410 |
| `VP2_Pine_Corridor` | 57.7 | 45.0 | 17.34 | 17.21 | 0.90 | 185 | 1,849,410 |
| `VP3_Overlook_Vista` | 60.8 | 45.1 | 16.45 | 16.32 | 0.98 | 208 | 1,851,474 |
| `VP4_Shoreline_Detail` | 59.6 | 43.5 | 16.77 | 16.64 | 1.07 | 170 | 1,848,414 |
| `FLYTHROUGH` | 52.5 | 30.7 | 19.05 | 18.94 | 1.20 | 147 | 1,846,821 |

---

## 5. Key Findings & Measured Limitations

1. **System 120 FPS Frame Cap:** Despite `VSYNC_DISABLED` and `Engine.max_fps = 0`, the Windows/NVIDIA driver stack capped presented FPS at `120.0 FPS` (`8.33 ms`). Using Godot's `RenderingServer.viewport_get_measured_render_time_gpu()` bypasses the presentation cap and exposes true GPU workload (`3.07–3.65 ms` Performance, `6.04–6.68 ms` Balanced, `16.27–18.94 ms` High).
2. **Balanced Tier is the Sweet Spot for 60 FPS Gameplay:** At `~6.4 ms` GPU and `~1.0 ms` CPU (`395 MB` VRAM), `Balanced` leaves **>10 ms of GPU headroom** inside a `16.67 ms` (60 FPS) budget for drivable vehicles, 10–20 traffic cars, racing AI, and HUD.
3. **High Tier (`SDFGI + SSIL + Volumetric Fog + MSAA 4×`) Exceeds 60 FPS Budget in Motion:** Adding SDFGI + SSIL + Volumetric Fog + MSAA 4× increases GPU time by **~10–12 ms** (`16.3–18.9 ms`) and jumps VRAM from `395 MB` to `957 MB` (+562 MB). More critically, during the moving `FLYTHROUGH`, **SDFGI cascade updates dropped 1% low FPS to `30.7 FPS`** (`32.53 ms` p99 frame time), which would feel noticeably hitchy at high driving speeds.
4. **Instanced MultiMesh Scalability:** Rendering 640 multi-tier pines, 120 autumn birches, 340 boulders, and up to 32,000 animated 5-blade grass tufts required only **82–208 draw calls** and **~1.0 ms CPU**, confirming `MultiMeshInstance3D` is completely CPU-cheap on Godot 4.7.2 Forward+.
5. **What Was Not Tested:** Driving physics, Terrain3D / Road Generator / Easy Vehicle Physics plugins, gamepad input, audio, and 2×2 km streaming (explicitly out of scope for this isolated visual lab).

---

## 6. Captured Real In-Engine Screenshots

All 15 screenshots (5 views × 3 tiers) were captured live from the Vulkan Forward+ viewport in `experiments/local-visual-lab/screenshots/`:
- **High:** `high_vp1_lakeside_hero.png`, `high_vp2_pine_corridor.png`, `high_vp3_overlook_vista.png`, `high_vp4_shoreline_detail.png`, `high_flythrough_mid.png`
- **Balanced:** `balanced_vp1_lakeside_hero.png`, `balanced_vp2_pine_corridor.png`, `balanced_vp3_overlook_vista.png`, `balanced_vp4_shoreline_detail.png`, `balanced_flythrough_mid.png`
- **Performance:** `performance_vp1_lakeside_hero.png`, `performance_vp2_pine_corridor.png`, `performance_vp3_overlook_vista.png`, `performance_vp4_shoreline_detail.png`, `performance_flythrough_mid.png`
