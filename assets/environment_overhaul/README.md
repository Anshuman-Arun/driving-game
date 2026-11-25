# Original understory candidates (not accepted production art)

This directory holds ten actual self-contained glTF 2.0 scenes, five species and two LODs. Manifest v1 uses res:// resource keys for both LOD paths and SHA-256. All assets are meter-scale, Y up, centered in X/Z with lowest point Y=0, one double-sided matte vertex-color surface, no textures, no normal maps, no alpha/blending and no opaque rectangular cards. Leaf shapes are real geometry; detailed LODs use folded leaves, simplified LODs use fewer flat leaflets and fewer stem sides. No collision, physics, animation or runtime generation.

| Species ID | Size X/Y/Z m | LOD0 triangles | LOD1 triangles |
|---|---|---:|---:|
| shrub | 1.05 / 0.65 / 1.05 | 480 | 200 |
| fern | 1.05 / 0.44 / 1.05 | 1088 | 320 |
| sapling | 0.95 / 1.65 / 0.95 | 394 | 166 |
| reed | 0.68 / 1.15 / 0.68 | 342 | 130 |
| wildflower | 0.42 / 0.52 / 0.42 | 432 | 180 |

LOD bounds are matched exactly; silhouettes are approximations and must be judged locally. Fir and fern scans in assets/premium_runtime remain separate optional existing candidates. No legacy files changed.

## Reproducible staging and validation

From repository root, Node.js 20+ (no npm packages):

    node tools/environment_assets/generate.mjs --self-test
    node tools/environment_assets/generate.mjs --stage
    node tools/environment_assets/generate.mjs --verify

Staging writes only generated candidates and their manifest/notice, skips identical files, and atomically replaces changed individual files. Never stages external input or performs network access. glTF embeds the vertex payload as base64, not LFS. Validation is deliberately strict for this original format rather than a general-purpose glTF validator. Negative tests cover absent texture/payload, LFS pointer, malformed accessor, missing license, wrong hash and degenerate geometry. Because assets have no textures, alpha-channel stats/mipmap checks and tangent validation are not applicable.

Godot 4.7.2 (root project):

    godot --headless --path . --editor --import
    godot --headless --path . --script res://tools/environment_assets/test_import.gd
    godot --path . res://tools/environment_assets/contact_sheet.tscn

The latter is a local graphical contact sheet, not a screenshot or visual acceptance claim. It optionally compares existing UV-matched premium fern/fir if available. Existing scans require real LFS bytes; after checkout run git lfs pull and python tools/environment_assets/audit_existing.py. After Godot import, run godot --headless --path . --script res://tools/environment_assets/test_existing.gd to measure actual cutout alpha statistics, bounds, triangle/surface counts and tangent availability on the existing fitted scans. This test is optional and was not run by the cloud agent. Do not copy the scans, rescale their textures independently, or replace their UV/material bindings. Existing PremiumMesh.fit preserves material/UV association, applies scissor threshold 0.39 to known alpha textures and selects anisotropic mipmaps. For the existing foliage only, check cutout silhouettes, alpha mips and tangent/normal behavior in Forward+; preserve UVs and use mask, not blend, if authoring new LODs from those scans. No new normal-map textures here. For original candidates consider roughness 0.8-0.95 and restrained backlight in a later material experiment; preserve the opaque geometry, avoid unnecessary transparency and measure draw calls. Local Blender cleanup is optional: import glTF at scale 1, inspect folded leaf normals and branches, merge only genuinely duplicated vertices, retain vertex colors and exact bounds, export separate LODs, and regenerate hashes/validation if a variant is accepted.

Integration: use species_id from C, choose variant_id and LOD, load PackedScene and instantiate/flatten mesh preserving material/vertex colors. Apply placement yaw and uniform scale about ground center; use actual transformed bounds for road/shoulder clearance. This package does not implement scatter, grass, LOD switching, road clearance, or root scene wiring.
