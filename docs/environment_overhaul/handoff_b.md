# Agent B — vegetation asset handoff

Base: 67023539e56e5e80d5efcd3f3239be9650c6f462 (verified identical to main at dispatch). Branch: feat/env-b-vegetation-assets. Original candidate commit: 69eb322bbabcf77adb78e8640c536355ed08867c. Exclusive write scope: assets/environment_overhaul, tools/environment_assets and this handoff.

## Deliverable

Five species, ten actual self-contained glTF payloads plus v1 manifest, license notice, reproducible staging/validation, Godot import/instantiation test and local contact sheet. See assets/environment_overhaul/README.md. Each original candidate uses geometric leaves with vertex colors, one opaque double-sided PBR surface, no external textures or normal maps. Approximate LODs have matching physical bounds; not optimized for a measured GPU target. Total glTF payload 669194 bytes (excluding docs/tool/manifest). No mature tree changes and no fine grass. No root wiring, data or shared license/status changes.

## Baseline asset audit

- Curated pine_tree_lod0.gltf and pine_tree_lod1.gltf: 120 and 49 triangles across seven/four meshes, original generator; deciduous_tree.gltf 1448 triangles across 15 meshes. These low-poly curated glTFs are not new candidates or evidence for later premium derivatives.
- valley_tree_factory.gd builds a phototextured single instanced surface, procedural trunks and canopy sprays, with existing pine_bough/broadleaf_spray and bark shader inputs. Preserve it.
- premium_mesh.gd collects transformed mesh parts, fits to a ground-centered parcel, groups by material and format, retains UV/material association, enables anisotropic mipmaps and scissor at 0.39 for known alpha textures. valley_vegetation.gd uses PremiumMesh.fit("fern", Vector3(1.5, 0.92, 1.5)).
- premium_world payload license ledger marks Fern 02 and Fir Sapling Medium complete; source glTF metadata shows 6232 and 1533513 source triangles respectively. The fern diffuse JPG cannot hold its mask and source fir twigs used BLEND. The alpha_fix record identifies separately acquired original opacity maps and restoration; existing runtime conversions are documented as UV-matched and scissor in ASSET_LICENSES.md and prior world QA.
- Fern 02: https://polyhaven.com/a/fern_02, Rob Tuytel (scanning), Rico Cilliers (modeling), CC0-1.0. Runtime GLB LFS expected 1908084 bytes, SHA-256 b081b04855ef451972742bc4e4d3862eb9567a31dad55600b547ac26aeebc4cd.
- Fir Sapling Medium: https://polyhaven.com/a/fir_sapling_medium, Rob Tuytel (photography), Rico Cilliers (modeling), CC0-1.0. Runtime GLB LFS expected 14585660 bytes, SHA-256 cff013dfbe455ce8016aa82a26faf1c6747ebf72f95c18d7a59979689447f149.
- Connector returned only pointers for both runtime GLBs. Real payload, actual triangle counts, alpha statistics and normal/tangent data could not be inspected here. Do not present scans as newly verified. Reuse via unchanged PremiumMesh.fit only after local audit, as illustrated by the optional comparison row; no new scan LODs or duplicated files. Original fern/sapling are independent candidates, not conversions of the scans.

## Evidence and exact reproduction

The actual generator/validator functions executed in the cloud JavaScript tool before the first commit. Five pairs, 10 glTFs, 7 negative fixture rejections, 2 SHA-256 known vectors and byte-identical repeated generation passed. See manifest for per-LOD triangle/size data. No Godot, local Blender, or graphical execution in the connector. Node CLI wrapper and GDScript import test authored but not executed in that environment. No visual or performance approval. Baseline map-regression workflow listens only on feat/map-width-current-main pushes or manual dispatch. No ownership of workflow files; do not alter them or fabricate CI.

From repo root, after checkout and git lfs pull, run:

    node tools/environment_assets/generate.mjs --self-test
    node tools/environment_assets/generate.mjs --verify
    python tools/environment_assets/audit_existing.py
    godot --headless --version
    godot --headless --path . --editor --import
    godot --headless --path . --script res://tools/environment_assets/test_import.gd
    godot --headless --path . --fixed-fps 60 --script res://tests/integration/map_width_check.gd
    godot --headless --path . --fixed-fps 60 --script res://tests/integration/roadworks_check.gd
    godot --headless --path . --fixed-fps 60 --script res://tests/integration/world_visual_qa.gd
    godot --headless --path . --fixed-fps 60 --script res://tests/integration/garage_world.gd
    godot --headless --path . --fixed-fps 60 --script res://tests/integration/vehicle_world.gd
    godot --path . res://tools/environment_assets/contact_sheet.tscn

Use the exact Godot 4.7.2 stable standard installation/checksum in .github/workflows/map-regression.yml, run each with appropriate timeout (420 s per regression), capture logs and exit codes; inspect script/parse/shader errors even on exit 0. The local contact sheet is a comparison only; inspect near/oblique/backlit views and rotating silhouettes, check LOD changes and bounds at 25/65 m, tune material roughness and brightness without changing source UVs, then compare in pilot with F's QA. Do not infer real FPS from headless.

## Proposed ledger entry (coordinator only)

| Original procedural understory (shrub, fern, sapling, reed, wildflower, two LODs each) | local://tools/environment_assets/generate.mjs | Aster Valley project original procedural geometry | CC0-1.0 generated assets; assets/environment_overhaul/LICENSE.txt | assets/environment_overhaul/manifest.json (per-resource SHA-256) | No external model, texture, download or AI-image source; meter-scale Y-up leaf/stem geometry |

Proposed PROJECT_STATUS entry: Agent B added five optional original understory species with ten standalone glTF scenes, deterministic generator and validation (in-memory geometry/hash/determinism/negative tests passed); existing premium scan pointers audited only, no source duplication. Godot import, actual scan bytes, graphical acceptance and GPU tuning outstanding. No production integration.
