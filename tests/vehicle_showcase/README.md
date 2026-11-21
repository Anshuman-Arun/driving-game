# Vehicle Visual-Quality Showcase & Benchmark

Reusable Godot 4.7.2 QA harness for side-by-side visual inspection, structural hierarchy auditing, and GPU/frame-time benchmarking of vehicle GLB/GLTF models under identical studio and outdoor road lighting.

## Run

1920×1080 capture + benchmark (default curated hero models):

```powershell
Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1920x1080 --script res://tests/vehicle_showcase/vehicle_showcase.gd -- --res=1920x1080 --out-dir=PATH_TO_SHOTS
```

3440×1440 ultrawide benchmark:

```powershell
Godot_v4.7.2-stable_win64_console.exe --path . --resolution 3440x1440 --script res://tests/vehicle_showcase/vehicle_showcase.gd -- --res=3440x1440 --bench-only
```

Compare a new candidate HD vehicle against the original Vela GT:

```powershell
Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1920x1080 --script res://tests/vehicle_showcase/vehicle_showcase.gd -- --res=1920x1080 --models=res://assets/curated/models/vehicles/vela_gt.glb,res://path/to/candidate_vela_gt.glb --out-dir=PATH_TO_COMPARE
```

## Outputs

- 6 standardized PNG screenshots per model: `01_front_quarter`, `02_rear_quarter`, `03_side_profile`, `04_wheel_detail`, `05_cockpit_angle`, `06_outdoor_road`.
- Structured `[VEHICLE_SHOWCASE_JSON]` report with triangle/vertex counts, mesh/surface/material/texture counts, bounding box dimensions, ground clearance (`min_y_m`), wheel pivot detection, interior mesh detection, and 120-frame steady-state FPS / 1% low / CPU ms / GPU ms / draw calls / VRAM.
