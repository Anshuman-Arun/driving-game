# Original understory candidates (not accepted production art)

Ten self-contained glTF 2.0 scenes: five species and two LODs. Manifest v1 uses res:// resource keys for both LOD paths and SHA-256. All assets are meter-scale, Y up, centered in X/Z with lowest point Y=0, one double-sided matte vertex-color PBR surface, no textures, no normal maps, no alpha blending and no opaque rectangular foliage cards. Original leaf shapes are geometry, not photographs. No collision, physics, animation or runtime generation.

| Species ID | Size X/Y/Z m | LOD0 triangles | LOD1 triangles | Minimum CPU projection IoU (24 views) |
|---|---:|---:|---:|---:|
| shrub | 1.05 / 0.65 / 1.05 | 640 | 348 | 0.9454 |
| fern | 1.05 / 0.44 / 1.05 | 1280 | 812 | 0.8932 |
| sapling | 0.95 / 1.65 / 0.95 | 536 | 290 | 0.9527 |
| reed | 0.68 / 1.15 / 0.68 | 376 | 220 | 0.9454 |
| wildflower | 0.42 / 0.52 / 0.42 | 600 | 336 | 0.8364 |

Total model payload: 969478 bytes. LODs share one procedural scaffold and physical normalization; LOD1 retains all leaflets and petals, flattens folds, and simplifies continuous tapered stem rings. Every LOD1 vertex position/color occurs in LOD0, and extreme groups preserve bounds. Fern leaflet roots lie on the piecewise-linear rachis, sapling branches start on the leaning trunk, reeds have continuous leaf geometry. Closed sweep ends and shared intermediate rings prevent the previous mismatched tube joints. Projected silhouettes pass an 80% intersection-over-union gate in 120 deterministic CPU views; this is not visual or GPU acceptance. Existing fir and fern scans remain separate optional candidates; no legacy files changed.

## Reproducible staging and validation

From repository root, Node.js 20+ and Python 3.10+ (standard libraries only; no npm or pip packages needed):

    node tools/environment_assets/generate.mjs --self-test
    node tools/environment_assets/generate.mjs --stage
    node tools/environment_assets/generate.mjs --verify
    python tools/environment_assets/verify_headless.py --data-only

The CLI uses native Node SHA-256 and Buffer, separate geometry, strict validator, and staging modules. Staging preflights owned paths, rejects symbolic links/nonregular destinations, skips identical bytes, takes an exclusive staging lock, writes all changed bytes to temporary files, replaces files individually and publishes the manifest last. A power loss or rename error can leave a partially replaced pack; rerun --stage and --verify. If a crashed process left .stage-lock, remove it only after confirming no staging process is running. Scoped .gitattributes forces LF for hashed resources on Windows. No network access or external source archives. glTF embeds the vertex payload as base64, not LFS. The strict validator is for the original format, not arbitrary glTF. Thirty reason-specific negative fixtures cover hidden scene transforms, material texture dependencies, accessor offsets/strides/sparse data, wrong hashes/licenses, nonfinite/degenerate/duplicate triangles, wrong normals, invalid base64 and mismatched LOD scaffolds. The data gate also runs filesystem checks, synthetic existing-scan GLB/PNG fixtures, fail-closed subprocess-runner tests and the 120-view CPU silhouette check. Original models have no texture alpha or tangent-space normal maps, so those checks do not apply.

Godot 4.7.2 (root project, after real LFS checkout):

    git lfs pull
    python tools/environment_assets/verify_headless.py --existing --regressions
    godot --path . res://tools/environment_assets/contact_sheet.tscn

The runner fails on timeouts, nonzero exits, missing exact completion markers and engine error logs even when Godot returns zero. Omit --existing to validate only original candidates; omit --regressions to skip inherited integration suites. --data-only explicitly skips all Godot gates. Do not confuse a passing data gate with a passing headless import. The contact sheet is a local graphical comparison, not a screenshot or visual approval claim.

## Existing scans (read-only)

    python tools/environment_assets/audit_alpha.py
    python tools/environment_assets/audit_existing.py

The first command independently decodes and verifies pinned 1024x1024 RGBA PNGs, checks CRC and alpha statistics. The two source PNGs have actual threshold coverage of 15.63% (fern) and 24.28% (fir). The second command requires real LFS GLB bytes; validates pinned size/hash, chunk and buffer bounds, image signatures/references, material texture references, finite float geometry, stride/offset/index bounds and nondegenerate triangles. It deliberately rejects unsupported compressed/sparse geometry rather than falsely passing it; actual pinned GLBs still need to be checked. It does not decode JPEG pixels. After Godot import, test_existing.gd checks alpha on the actual bound materials, fitted bounds and tangent availability. Source PNG alpha coverage alone does not prove correct UV alignment or material binding. Do not copy the scans, rescale their textures independently, or replace their UV/material bindings. Existing PremiumMesh.fit preserves materials/UVs, sets scissor threshold 0.39 for known alpha textures and anisotropic mipmaps. Inspect cutout silhouettes, mip behavior, and tangents in Forward+. Preserve UVs and use mask, not blend, when authoring scan LODs.

For original candidates start roughness at 0.88 and test restrained backlight later. Preserve opaque geometry, avoid unnecessary transparency and measure draw calls. Optional Blender cleanup: import glTF at scale 1, inspect folds and branches, merge only truly duplicate vertices with compatible normals/colors/UVs, retain bounds and export separate LODs. Changes require regenerated hashes and validation.

Integration: choose species_id and variant_id from the manifest; load each PackedScene and instantiate/flatten the mesh preserving material and vertex colors. Apply placement yaw and uniform scale about ground center; use actual transformed bounds for road/shoulder clearance. No scatter, fine grass, LOD switching, road clearance or root scene wiring is implemented here.
