# Aster Valley — Needle Pass (Cedar Woods → North Ridge)

**Status: source-complete first-pass, VISUAL ACCEPTANCE BLOCKED.** The user-requested ArtStation-class appearance has **not** been demonstrated. This branch is deliberately reviewable as a draft. Its new source models are more detailed than the existing blockout, but authored procedural geometry + 1K scans are **not a substitute for professional manual asset refinement**. Do not treat geometry volume or successful scene parsing as evidence of photorealism.

## What is included

- Exact **553 m** stretch of the real `cedar_ridge` road and canonical 4 m R16 terrain samples, extracted from existing `main`, not invented map data.
- **205** placements from scenery PR #23, constrained to terrain patch and prevalidated road clearances. Reuses compatible project original art; added 5 more-detailed authored source glTF meshes (fir variants, cliff variants and fern).
- 1K CC0 textures with exact source provenance; full rock albedo/normal/roughness and partial asphalt/ground PBR channels.
- Two scene workflows based on the *same data*: Godot 4.7.2 Forward+ `standalone.tscn` and Blender source-scene script `tools/environment_hd/build_blender.py`. Six stable comparison poses, key 1–6 in Godot, all present as named Blender cameras.
- `integrated.tscn` overlay root with **terrain/road rendering and standalone lighting disabled**. It owns no physics, cannot replace the World Runtime collision surface, and must be instanced by the integrator.

## Reproduce

From a checkout of the new feature branch with Node.js 22+:

```sh
node tools/environment_hd/validate.mjs
node tools/environment_hd/generate_models.mjs --check
node tools/environment_hd/stage.mjs
node tools/environment_hd/stage.mjs --check
godot --headless --path showcase/environment_hd --editor --quit
godot --path showcase/environment_hd
```

Use Godot **4.7.2 stable** and press 1–6 for the fixed views. Forward+ is enabled in the standalone subproject. `stage.mjs` duplicates files **only** into the locally ignored `staged_assets/` folder, because the standalone Godot project root cannot resolve another project's `res://assets` paths. Run `--clean` to remove only that local staging folder.

For the professional source scene, install Blender 4.x (any local Blender 4.x must be checked for API compatibility):

```sh
blender -b --python tools/environment_hd/build_blender.py
blender -b --python tools/environment_hd/build_blender.py -- --render
```

This creates `showcase/environment_hd/NeedlePass_Portfolio.blend` with six cameras, and optionally real `renders/view_01.png` ... `view_06.png` **only after Blender actually runs**. Such files are not in the PR because Blender was unavailable in the authoring runtime. Review and commit real output only after execution and inspection. No mock screenshots or synthetic beauty renders are included.

## Integration contract

Integrators should open the genuine world physics scene from PR #20 / World Runtime and add `res://showcase/environment_hd/integrated.tscn` as a child. Reuse `data/world/road_graph_v1.json` / R16 metadata in exactly the original world coordinates. The overlay defaults to visual foliage/geology only; it does NOT create `StaticBody3D`, `CollisionShape3D`, drive lanes, or new terrain colliders. If duplicate foliage from the existing scenery runtime is visible, **choose only one foliage renderer** in the showcase footprint; culling/LOD coordination is a remaining integration action. Avoid any collision-authority change.

For the integrated root-Godot project, assets resolve from `res://assets/environment_hd`. The standalone scene uses staged assets when needed. World spatial coordinates are Godot `(X east, Y up, Z south)` in **meters**; Blender transforms to `(X, -Z, Y)`. The same sample and placement data generate both scenes. Use `render_terrain_visual=false` and `render_road_visual=false` for the integrated overlay: existing World Runtime owns the visual road/terrain and authoritative collision.

## Performance expectations vs measurements

Budget controls: `foliage_quality=0/1/2`, authored fir only on high, low-detail original far pines on lower settings. No vehicle physics or gameplay impact by design; this first-pass scene currently places many independent nodes and **does not yet MultiMesh-batch the hero firs**. Source raster visual mesh contains 20,413 vertices, 40,256 triangles. This is only the cropped visual, not the full-world runtime. There is no real GPU memory/FPS/draw-call result. For a shippable scene, merge repeated same-material instances into grouped MultiMeshes, LOD/distance fade, shadow limits, and budget benchmarks on target hardware.

## Visual QA required before review passes

Every one of the six views needs an unblurred viewport/Cycles screenshot, scale audit, surfacing and silhouette critique, physically plausible roughness verification, obvious repetition check, edge paint wear check, road shoulder seam evaluation, and practical engine profiling. Reject view 2 if low-poly artifacts dominate close-up; reject view 4 if cliff mesh is floating/disconnected; reject view 5 if horizon and fog are flat; reject view 6 if exposure is masking weak surfacing.

See [VIEWPOINTS.md](VIEWPOINTS.md), [VALIDATION_REPORT.md](VALIDATION_REPORT.md), and [../../assets/environment_hd/ASSET_MANIFEST.json](../../assets/environment_hd/ASSET_MANIFEST.json). None of the above steps have been claimed executed unless documented as observed.
