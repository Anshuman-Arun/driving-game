# Aster Valley — Local Visual Lab (Godot 4.7.2 Forward+)

A standalone, isolated rendering benchmark and visual prototype for **Aster Valley** built in Godot 4.7.2 Forward+. All geometry and shaders are original and procedural — no external copyrighted assets, and no modifications outside `experiments/local-visual-lab/`.

## What's Inside

- **360 m+ Alpine Lakeside Vista:** Smooth winding asphalt highway with weathered markings, tire-wear roughness tracks, steel W-beam guardrails with reflective delineators, timber overlook deck, parked fictional sports coupe (`Vela GT` visual reference sculpture), **Eastwater Lake** with Beer-Lambert depth shading and SSR reflections, 640 multi-tier pines, 120 autumn-accent birches, 340 granite boulders, up to 32,000 wind-animated grass tufts, and a 1.48 km snow-capped distant mountain ring.
- **3 Graphics Presets + Live Feature Toggles:** `Performance`, `Balanced`, and `High`, plus individual runtime toggles for `SSAO`, `SSIL`, `SSR`, `SDFGI`, `Volumetric Fog`, `Glow`, and `TAA`, and 3 lighting presets (`Golden Hour`, `Alpine Noon`, `Blue Dusk`).
- **Reproducible Camera Rig:** 4 stationary benchmark viewpoints (`VP1`–`VP4`), 1 deterministic road-to-lake spline flythrough, and optional free-camera navigation.
- **Automated GPU Benchmark Harness:** Measures real GPU render ms, CPU render ms, avg FPS, 1% low FPS, draw calls, primitives, and VRAM, and saves native PNG screenshots + JSON reports.

## How to Run

### Interactive GUI Mode
Open `experiments/local-visual-lab/project.godot` in Godot 4.7.2 and press **F5** (or run from PowerShell):
```powershell
& "<godot_exe>" --path "experiments/local-visual-lab"
```

**Interactive Controls:**
- `1` – `4`: Jump to stationary benchmark viewpoints (`VP1`–`VP4`)
- `F`: Start repeatable spline flythrough
- `P`: Cycle graphics tier (`Performance` → `Balanced` → `High`)
- `T`: Cycle lighting (`Golden Hour` → `Alpine Noon` → `Blue Dusk`)
- `H`: Toggle telemetry/controls HUD
- `F12`: Save manual PNG screenshot to `captures_tmp/`
- `WASD` + `Q`/`E` + `Right-Mouse Drag` (`Shift` for boost): Free camera

### Automated 3-Tier Benchmark Mode
```powershell
powershell -ExecutionPolicy Bypass -File "experiments/local-visual-lab/run_benchmark.ps1" -Resolution 1920x1080
```

## Documentation

- [ENVIRONMENT.md](ENVIRONMENT.md) — Local preflight environment & Vulkan Forward+ GPU verification
- [TEST_REPORT.md](TEST_REPORT.md) — Full measured 3-tier benchmark tables, camera specs, and findings
- [INTEGRATION_NOTES.md](INTEGRATION_NOTES.md) — Concrete rendering recommendations for Aster Valley Core/World/Art PRs
