# Validation and art-quality report — 2026-11-21

## Focused art-source revision after review of 0c79d2fc37b2

The branch already included later commit 1210a8a6 before this follow-up; these
changes were applied on that newer feature head, never rebased onto main.

**Changes prepared, not visually accepted:**
- Disabled repetitive procedural cliff-sheet blockouts in BOTH default
  beauty pipelines. Scanned/sculpted substitute remains **not acquired**.
- Six authored absolute camera XYZ/aim/FOV presets now live in one shared
  camera_shots_v2.json and drive both Godot and Blender. The integrated
  overlay no longer steals the game camera; beauty camera labels are off.
- Godot road/terrain shaders now use CC0 roughness-derived micro-bump
  approximation, road wear/polish/macro patch variation and cutout paint
  chipping; added terrain-conforming gravel verge strips. Source asphalt
  and ground normal maps are still MISSING and may not be claimed acquired.
- Blender source scene uses matching route-based UV tiling, conforming
  shoulders, direct roughness-based bump, steep-slope CC0 rock blending,
  bark microrelief, subtle foliage variation and worn road markings.
- Godot repeated vegetation/rock instances are grouped into 72 m
  MultiMesh cells for coarse frustum/distance culling; real LOD pop,
  correct mesh-transform import and GPU frame costs are unverified.
- A Godot Forward+ raw capture script, Blender raw Cycles render path,
  SHA-256 PNG verifier, and no-rebase merge staging instructions are
  committed in LOCAL_RENDER_HANDOFF.md.

**Actually checked:** all updated GitHub file blobs exist; the six fixed
camera rays were sampled against the embedded canonical 4 m heightfield
with minimum clearances 3.26, 1.68, 3.16, 1.42, 12.65, 1.21 m. The
connector-level checks also verified the integrated camera override and
both default cliff-disable flags. These are **source-data tests only**.

**Blocked:** Blender, Godot 4.7.2, GPU and a live local clone were
unavailable, so the new shader/GDScript import, Python/Node CLI
execution, six real renders, screenshot inspection, FPS measurements
and artistic approval have NOT occurred. No rendered frames exist here.

**Outstanding artist work:** acquired and hand-composed scanned geology,
more convincing hero conifers/bark/needles, physical fallen branches,
grass tufts and moss/forest litter, sourced road/ground normal maps,
real reflection and light tuning, and six image-by-image iterations.
Do not accept this draft PR as finished environment art.

---


## Observed

- Inspected current `main` world graph/metadata and PR #23 scenery placement data, PR #20 World Runtime integration, and merged Art PR #7. Source corridor `cedar_ridge` lane and R16 patch retain canonical positions and elevations.
- `showcase/environment_hd/data/corridor_v1.json` is an embedded 137×149 subset (20,413 source R16 elevation samples, 4m spacing) along a **553m** connected section of the **real** Needle Pass route. It includes 80 sampled centreline points and **205 placement records**, sourced from PR #23; every imported placement's *source-reported* road clearance is at least 8m. This is inherited source validation, not a fresh collider simulation.
- Verified new 5 authored glTF encoder output in JS before pushing: source counts **6,060+6,060+7,568+6,010+598=26,296 triangles** across five separate source files; counts exclude all instances and five reused project GLBs. More detail is not equivalent to hand-sculpted quality. Source geometry generation executed in a JavaScript runtime through the connected GitHub workflow; the checked-in generator is supplied for local reproduction.
- Scanned 3 new cliff-placement bounding rectangles against all 16 canonical road corridors' centreline segments; closest sampled distances **42.56, 47.70, 42.96 m** respectively, before considering complex cliff depth, terrain occlusion or sightlines. This is a planar clearance check only, **not** a Godot collision test.
- Four source **1024×1024** JPEGs and three **1024×512** rock JPEGs albedo/normal/roughness texture files were transferred into the branch with exact Git blob matches to their recorded public source mirrors. A complete rock PBR trio is present; normals for asphalt/ground are **missing**, not invented. Content origin/licensing documented in `assets/environment_hd/ASSET_MANIFEST.json`.
- Three-dimensional sources and Godot/Blender build scripts are committed. Standalone and integrated scene files use only owned directories; global physics world remains untouched.

## Executables not available in authoring environment

**Blender: unavailable. Godot 4.7.2: unavailable. Target GPU: unavailable.** Accordingly:
- No Blender `.blend` binary saved, no Cycles image produced, and no professionally evaluated portfolio scene shown.
- No Godot import/parser check, no rendering/frame screenshot, and no 60-FPS or VRAM benchmark.
- No observed GPU draw calls, shader compilation result, lighting quality, silhouette inspection in a real 3D viewport, culling behavior, or paired visual-quality comparison.
- Static source tests `node tools/environment_hd/validate.mjs`, `generate_models.mjs --check`, `stage.mjs --check` are provided but **must be executed by a machine that has the branch checked out**. Do not say they passed when they have not been run.

## Technical / artistic defects needing work

1. Real scanned model geometry and manually sculpted cliff meshes are still missing. Current rock surface gets scanned texture but geometry is original parametric height strips; the two cliff variants repeat a similar outline.
2. Trees use custom geometry but original low-LOD props remain apparent; no foliage SSS, wind, tree-species botanical accuracy, or detailed shadow card optimization.
3. Ground-cover is incomplete (no leaf litter, fine pine-needle debris, fallen logs, moss displacement/decals); near-field `Ground093C` is only a base layer.
4. No complete 1K or higher normal map for the road/soil; crack/patch road variation currently shader-based rather than authored decals.
5. No measured LOD switching/culling; high setting can issue many scene instances. Duplicate scenery systems need integration coordination.
6. Six camera compositions are **defined**, not photographically approved; rock-edge silhouettes, road junction continuity, forest light breakup, environmental depth, and actual material map fidelity await rendered viewing.
7. Blender source script only; no checked-in `.blend`, screenshots or production mesh refinement pass. Godot syntax/ABI remains unverified.

**Decision: not art-direction approved / draft PR.** It meets several source and spatial integrity deliverables; it does **not yet** meet acceptance criterion of demonstrated high-fidelity visual quality.
