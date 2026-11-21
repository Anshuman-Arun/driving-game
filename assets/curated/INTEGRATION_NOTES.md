# Integration notes — Aster Valley curated art

**Scope:** only `assets/curated/` and `tools/asset_pipeline/`. No project.godot, game scenes, controller, addons, road data or shared docs were changed.

## Coordinates and car attachment

- Godot +Y up, **1 unit = 1 meter**, +X car right, **-Z forward**. The car origin is near ground level at chassis center.
- All six primary vehicle GLBs are fictional; no real manufacturer marks. Their unique scene roots are `AssetRoot` with separate `Wheel_FL_Pivot`, `Wheel_FR_Pivot`, `Wheel_RL_Pivot`, `Wheel_RR_Pivot` nodes. Each pivot has named `Tire_`, `Rim_`, `Brake_` visual meshes and hub features.
- Front axle: negative Z, rear axle: positive Z. The wheel visual rolls around its local **X** axis. Front wheel steering rotates around **Y**, or is applied via a parent transform owned by the vehicle controller. Attach imported GLB scenes as **visual children** of physics bodies; do not use the GLB scene itself as a physical vehicle.
- Visual tire radius approximately **0.355 m** for sports and **0.345 m** for traffic; centers Y ≈ 0.36–0.37 m. Author or tune collision bodies independently, starting around 95% of body length and 90% of width. Wheel pivots are for animation and alignment, not physics authority.

| Primary car | Length m | Width m | Height m | Wheelbase m | Tris |
|---|---:|---:|---:|---:|---:|
| Vela GT | 4.55 | 1.88 | 1.37 | 2.70 | 2,252 |
| Orion RS | 4.19 | 1.78 | 1.28 | 2.47 | 2,252 |
| Kestrel XR | 4.72 | 1.95 | 1.36 | 2.78 | 2,340 |
| Alder Hatch | 3.94 | 1.72 | 1.53 | 2.50 | 1,748 |
| Cedar Sedan | 4.53 | 1.82 | 1.50 | 2.67 | 1,748 |
| Valley Wagon | 4.46 | 1.83 | 1.57 | 2.68 | 1,748 |

Supplementary traffic visual LOD models at `models/traffic_lod/` contain **952 triangles each**, with all four wheel pivot nodes. Alternate car models from `models/vehicle/` are a separate original collection and are not interchangeable with primary model hierarchy without checking node names; select which family the core integrator prefers after visual tests.

## Godot 4.7.2 import workflow

1. Merge this art PR only after the core Godot prototype is stable, and allow Godot to import `*.glb`, standalone `*.gltf` and `*.png` files. All authored glTF buffers are embedded; no external remote dependencies.
2. Instantiate a chosen visual vehicle under an existing controller root, align independent wheel pivots to its tire/suspension outputs and create the collider shapes elsewhere.
3. Apply `materials/*.tres` StandardMaterial3D resources to **UV-mapped terrain/road/scenery meshes**. Each preset references a 256×256 original albedo PNG and tangent-space normal PNG; roughness is stored as a scalar. Car/prop meshes use PBR colors, not UV texture coordinates.
4. Use `pine_tree_lod0` nearby, `pine_tree_lod1` farther away. Use MultiMesh or batching for tree/rock populations. Add low-poly colliders only for reachable solid roadside obstacles.
5. Benchmark traffic density with **0/5/10/20 cars** and log draw calls, not just triangle counts; even low-poly models contain several separate mesh/material surfaces.

## Repeatable offline tooling

From repository root, Node.js 20+:

```sh
node tools/asset_pipeline/validate.mjs
node tools/asset_pipeline/render_previews.mjs
node tools/asset_pipeline/generate_environment.mjs
node tools/asset_pipeline/generate_textures.mjs
node tools/asset_pipeline/convert.mjs --all
```

Open `previews/gallery.html` locally for model-derived SVG previews. Treat generated environment and texture outputs as art sources; check `git diff` before committing regenerated files. The supplementary `generate.js` was committed concurrently and its outputs must be compared independently before replacement.

**Unverified:** Godot editor import/runtime scene, Blender viewing/editing, Forward+ appearance, physical wheel linkage and game FPS. These require an integrator's actual local Godot runtime check.
