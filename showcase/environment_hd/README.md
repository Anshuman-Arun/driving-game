# Aster Valley — Needle Pass (Cedar Woods → North Ridge)

**Status: focused Needle Pass art-source revision, RENDERING AND VISUAL ACCEPTANCE BLOCKED.** The user-requested ArtStation-class appearance has **not** been demonstrated. This branch is deliberately reviewable as a draft. Its new source models are more detailed than the existing blockout, but authored procedural geometry + 1K scans are **not a substitute for professional manual asset refinement**. Do not treat geometry volume or successful scene parsing as evidence of photorealism.

## What is included

- Exact **553 m** stretch of the real `cedar_ridge` road and canonical 4 m R16 terrain samples, extracted from existing `main`, not invented map data.
- **205** placements from scenery PR #23, constrained to terrain patch and prevalidated road clearances. Reuses compatible project original art; added 5 more-detailed authored source glTF meshes (fir variants, cliff variants and fern).
- 1K CC0 textures with exact source provenance; full rock albedo/normal/roughness and partial asphalt/ground PBR channels.
- Two renderer workflows based on the *same canonical scene data* and the committed shared `camera_shots_v2.json`: Godot 4.7.2 Forward+ `standalone.tscn` and Blender source-scene script `tools/environment_hd/build_blender.py`. Six explicitly hand-authored world-space comparison poses, key 1–6 in Godot, all present as named Blender cameras.
- `integrated.tscn` overlay root with **standalone lighting and showcase camera/UI disabled**; visual-only terrain/road coatings are enabled. It owns no physics and cannot replace the World Runtime collision surface. Its old procedural cliff slabs are disabled by default in both renderers; a licensed scanned replacement remains pending.

## Reproduce

From a checkout of the new feature branch with Node.js 22+:

```sh
node tools/environment_hd/validate.mjs
node tools/environment_hd/generate_models.mjs --check
node tools/environment_hd/stage.mjs
node tools/environment_hd/stage.mjs --check
python -m py_compile tools/environment_hd/build_blender.py tools/environment_hd/verify_raw_renders.py
godot --headless --path showcase/environment_hd --editor --quit
godot --path showcase/environment_hd
```

Use Godot **4.7.2 stable** and press 1–6 for the fixed views. Forward+ is enabled in the standalone subproject. `stage.mjs` duplicates files **only** into the locally ignored `staged_assets/` folder, because the standalone Godot project root cannot resolve another project's `res://assets` paths. Run `--clean` to remove only that local staging folder.

For the professional source scene, install Blender 4.x (any local Blender 4.x must be checked for API compatibility):

```sh
blender -b --python tools/environment_hd/build_blender.py
blender -b --python tools/environment_hd/build_blender.py -- --render
python tools/environment_hd/verify_raw_renders.py blender --write-manifest
# For raw Godot Forward+ frames use an onscreen renderer (no --headless):
godot --path showcase/environment_hd --script res://capture_views.gd
python tools/environment_hd/verify_raw_renders.py godot --write-manifest
```

This creates `showcase/environment_hd/NeedlePass_Portfolio.blend` with six cameras, and optionally real `renders/view_01.png` ... `view_06.png` **only after Blender actually runs**. Such files are not in the PR because Blender was unavailable in the authoring runtime. Review real output only after execution and inspection. See [LOCAL_RENDER_HANDOFF.md](LOCAL_RENDER_HANDOFF.md) for exact evidence and no-rebase integration steps. No mock screenshots or synthetic beauty renders are included. Godot viewport captures and Blender Cycles output are required for visual approval.

## Integration contract

Integrators should open the genuine world physics scene from PR #20 / World Runtime and add `res://showcase/environment_hd/integrated.tscn` as a child. Reuse `data/world/road_graph_v1.json` / R16 metadata in exactly the original world coordinates. The overlay defaults to visual foliage/geology and **slightly raised visual-only terrain/road coatings**; it does NOT create `StaticBody3D`, `CollisionShape3D`, drive lanes, or new terrain colliders. If duplicate foliage from the existing scenery runtime is visible, **choose only one foliage renderer** in the showcase footprint; culling/LOD coordination is a remaining integration action. Avoid any collision-authority change.

For the integrated root-Godot project, assets resolve from `res://assets/environment_hd`. The standalone scene uses staged assets when needed. World spatial coordinates are Godot `(X east, Y up, Z south)` in **meters**; Blender transforms to `(X, -Z, Y)`. The same sample and placement data generate both scenes. The integrated overlay defaults to `render_terrain_visual=true`, `render_road_visual=true`, `enable_showcase_camera=false`, and `show_legacy_procedural_cliffs=false`, drawing visual-only coatings just above the canonical surface. The **existing World Runtime always owns collision**. Turn either flag off if integration exhibits double material layers or z-fighting. The production integrator must profile any duplicate visual draw costs.

## Performance expectations vs measurements

Budget controls: `foliage_quality=0/1/2`, authored fir only on high, low-detail originals on lower settings. Godot now groups repeated models in **72 m spatial MultiMesh cells** and adds camera-distance visibility fade, without touching vehicle physics. Actual culling correctness, shader compilation, GPU draw calls and frame rate still require target-device measurement. Source raster visual mesh contains 20,413 vertices, 40,256 triangles. This is only the cropped visual, not the full-world runtime. There is no real GPU memory/FPS/draw-call result. For a shippable scene, merge repeated same-material instances into grouped MultiMeshes, LOD/distance fade, shadow limits, and budget benchmarks on target hardware.

## Visual QA required before review passes

Every one of the six views needs an unblurred viewport/Cycles screenshot, scale audit, surfacing and silhouette critique, physically plausible roughness verification, obvious repetition check, edge paint wear check, road shoulder seam evaluation, and practical engine profiling. Reject view 2 if low-poly artifacts dominate close-up; reject view 4 if cliff mesh is floating/disconnected; reject view 5 if horizon and fog are flat; reject view 6 if exposure is masking weak surfacing.

See [VIEWPOINTS.md](VIEWPOINTS.md), [VALIDATION_REPORT.md](VALIDATION_REPORT.md), and [../../assets/environment_hd/ASSET_MANIFEST.json](../../assets/environment_hd/ASSET_MANIFEST.json). None of the above steps have been claimed executed unless documented as observed.
