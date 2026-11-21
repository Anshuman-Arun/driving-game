# World-runtime integration notes (module-only ownership)

## Authority, branch boundaries and exact baseline

- Current target source: World PR #3, feat/worldgen at 306d0be4a1fe72d8c529a1ab2b44e29a911da3a4. Do not rewrite or merge that branch to test this module.
- Source graph blob 9bba378d68879df3baed2c97a4885c0adde88406; source R16 blob d951ce11a831dad5430b4c7157e2296f73c6b151.
- World metadata: 501 x 501 uint16 little endian at 4 m stride; (-1000,-1000) origin; samples in centimeters. Map is +Y up. Elevation decodes to 5.00–240.45 m (metadata quotes 240.449 m before quantization).
- The 27 graph road records contain 16 physical corridors and 11 junction pseudo-roads. The 104 directed lanes contain 32 physical travel lanes and 72 junction connectors. Only matching AB/BA pairs create road strips; turn lanes build intersection pad coverage only.
- Some turn centerlines depart up to ~21 m from the physical corridor. Intersection pads must be generated from those actual turn paths, **not** a disk around an invented junction center. The terrain raster is already graded; do not grade it a second time.
- Core PR #6 remains separate; no vehicle physics, global scene, root project file, add-on source or shared docs are modified here. docs/PROJECT_STATUS.md is intentionally untouched because it is outside this workstream's ownership.

## Reusable runtime API

Use the script at modules/world_runtime/src/world_runtime.gd, instantiated as a Node3D in the existing application's world root. On the root Godot project after World PR #3 merges, it auto-detects res://data/world/. Before that, point build_world(directory_override) to World PR #3's exported data directory; the standalone viewer can use the module-local ignored staging cache.

Do not load both this runtime's generated collision and an overlapping Terrain3D/Road Generator collision at the same time. The importer is a fallback standalone road/terrain renderer that already provides a drivable collidable surface. Native plug-ins are integration options, not installed or runtime-tested dependencies of this PR.

### Terrain3D 1.1.0 adapter

- Instantiate the importer, call create_height_image_rf() and get_world_metadata().heightfield. The image stores *meters* in the R channel using RF float format, one pixel per 4 m sample, increasing +Z row order.
- Terrain3D 1.1.0 expects its own region storage, size and splat/height import workflow. In the editor, resample/pad the 501x501 RF image to its supported region size without shifting the origin or changing the vertical scale. Map local XY heightmap pixels to Godot X/Z. Validate the four corners and center against get_surface_height_at() before enabling native collision.
- Image conversion is provided, but native Terrain3D allocation/region import is **not claimed tested**; the binary GDExtension distribution is not bundled, and its native storage is not emulated here. Use the official 1.1.0 release matching Godot 4.7.2 on Windows.
- If replacing the generated terrain, switch off its colliders or remove generated TerrainChunks. Keep junction pads/road meshes above that native terrain at their sampled Y, and compare final road seams at terrain patch boundaries.

### Godot Road Generator 0.9.5 adapter

- Call get_physical_road_centerlines(); each record has road id/name, typed PackedVector3Array center points, 6.8 m total travel width, original asphalt/gravel surface and speed limit. Construct one native Curve3D/RoadContainer road per record in the parent integration layer. Preserve actual XY grades; do not drive road geometry directly from 104 directed lanes.
- Keep get_road_graph() unchanged for traffic/racing; next_lane_ids remain directed and the 72 turn lanes remain semantic routes.
- Native Road Generator 0.9.5 may have its own terrain connector or road intersections. Those editor resources and connector bindings must be tested with actual installed release before replacing the independent mesh. Do not assume 0.9.5 has a supported API to import this specific junction-hull geometry automatically. Our fallback pads are the collision-safe baseline and should remain until a native replacement can pass raycast checks on all 72 connector centerlines.
- For a bridge to native road curves: for each corridor record, create Curve3D.new(); loop through record.points and call curve.add_point(point). Assign the resulting Curve3D to the native road node through its tested API; apply total width_m from the record. Do not duplicate AB and BA.

### Core PR #6 / vehicle integration

- Place world runtime as a child of the world root, at transform identity. After build_world() succeeds, place the Vela GT at a road point at least 10 m from a junction, oriented to the lane tangent, at least wheel radius above sampled collidable Y.
- Both generated road and pad meshes have ConcavePolygonShape3D StaticBody3D collision in the default layer. Match collision layer/mask settings to the vehicle and camera raycasts in Core PR #6. Disable overlapped existing 500x500 m prototype collisions in the *integrated* scene; do not modify that agent's branch here.
- Test wheel ground contacts, speed through steep grades (up to 13.605%), braking on gravel, inner/outer lane edges, cliff-side shoulders, pad boundaries, underside collision and transitions from road to terrain in the Godot physics runtime.
- Capture baseline memory, generation time, editor FPS, real vehicle physics collision checks and Windows export performance before deciding whether distance-based terrain chunk streaming or native Terrain3D tiles are needed. The module reports generation time and static memory only when actually run in Godot.

## Test results in this environment

Read-only, independently computed against the actual GitHub source files through the connected GitHub app:

- R16 byte length: 502,002; decoded elevation range: 5.00–240.45 m.
- Roads: 16 physical corridors, 11 junction pseudo-roads; 104 directed lanes, 72 turn paths, 144 directed graph links. Maximum lane-link gap: 0.000 m.
- Maximum travel grade: 13.604786%; maximum bilinear lane/raster height discrepancy: 0.00055533 m.
- For 32-cell full-world terrain chunks: predicted 256 terrain chunks, 500,000 terrain triangles. For physical roads: 1,685 centerline segments, 13,480 triangles and 40,440 submitted road vertices. These are geometry-derived predictions and do not count pad triangles (depends on 2 m clipping resolution).
- Convex turn coverage with initial side offsets was validated for all 11 junction groups, then strengthened by explicit cardinal padding so even extreme turn points have clearance. Run the independent Node preflight after staging to measure padded hull area and clearance.

## Godot 4.7.2 local runtime QA results (Windows / RTX 4050)

Verified directly in Godot 4.7.2 (`4.7.2.stable.official.ed1daf0bf`, Forward+ / Vulkan 1.4.325, NVIDIA GeForce RTX 4050 Laptop GPU at 1920×1080) against staged `origin/feat/worldgen` data:

- **Headless editor import & parser gate**: PASS (0 errors, 0 warnings).
- **Preview collision & regression smoke test**: PASS (`51` terrain chunks, `7` corridors, `4` junction pads, `62` static colliders, `20/20` Alder junction mid-rays, `60` turn samples, `24/24` road rays, `31` terrain chunk-seam checks, deterministic rebuild verified, `~602 ms` build time).
- **Full-world collision & regression smoke test**: PASS (`256` terrain chunks, `16` physical corridors, `11` junction pads covering all `72` turn paths, `283` static colliders, `72/72` junction mid-rays, `216` turn samples, `642/642` road deck rays across left/center/right, `196` terrain chunk-seam checks, deterministic rebuild verified, `~2,805 ms` build time).
- **Dense 2 m corridor sweep (all 16 corridors, left/center/right)**: `20,109 / 20,109` road/junction collider hits, `0` terrain pokes, `0` misses.
- **1920×1080 RTX 4050 steady-state performance** (warmup & screenshot disk I/O excluded):
  - **Preview mode** (`104,270` tris, `66,453` verts, `62` colliders, `89.74 MB` static mem, `109.75 MB` VRAM, `650 ms` build): Stationary `119.9 FPS` avg / `113.0–114.7 FPS` 1% low (`0.40–0.44 ms` CPU, `0.88–1.08 ms` GPU); Traversal `119.9 FPS` avg / `114.9 FPS` 1% low (`0.34 ms` CPU, `1.62 ms` GPU, `0` stutter frames).
  - **Full-world mode** (`520,139` tris, `326,673` verts, `283` colliders, `231.92 MB` static mem, `118.99 MB` VRAM, `2,923 ms` build): Stationary `144.9 FPS` avg / `137.6–141.1 FPS` 1% low (`0.82 ms` CPU, `1.82 ms` GPU, `0` stutters); Traversal `118.2 FPS` avg / `62.2 FPS` 1% low (`0.64 ms` CPU, `1.38 ms` GPU, `2` stutter frames).
- **Fixes landed in `fix/world-runtime-qa`**:
  1. Fixed GDScript type-inference parse error on `local_path := get_script().resource_path.get_base_dir()` in `src/world_runtime.gd` and replaced deprecated `Image.create` with `Image.create_empty`.
  2. Fixed non-transitive `is_equal_approx` comparator in `_convex_hull` (`src/mesh_builder.gd`) that corrupted 7 of 11 junction hulls and dropped Alder Town's junction pad.
  3. Raised `PAD_LIFT_M` from `0.085` to `0.10` m so road decks no longer poke 1–3 mm above overlapping junction pads.
  4. Added `1.35 m` terrain-burying perimeter shoulder skirts to all junction pads so pad boundaries have smooth drivable ramps instead of a `10 cm` floating drop-off.
  5. Pre-allocated terrain chunk vertex/normal/UV/index buffers and inlined height array reads in `_build_terrain`, reducing full-world build time from `~6.2 s` to `~2.5–2.9 s`.
  6. Freed prior `GeneratedWorld` immediately via `free()` after `remove_child()` on rebuild to prevent transient `2×` static memory spikes.

## Potential follow-up improvements after engine verification

- The conservative convex pads intentionally overfill irregular junctions. For visual fidelity, replace with a polygon union of buffered connector strips after ensuring no holes and no collider coverage regression.
- Near-road seams currently overlap the terrain surface at the shoulder edge by 8 cm rather than topologically welding two separate meshes; check for sharp contact ramps on high crossfall roads. Tune shoulder width/vertical transition only based on visible and physics evidence.
- For production, enable region unloading and LOD / native Terrain3D paging based on measured GPU/render budgets, rather than assuming 256 concurrently resident terrain chunks are ideal.
