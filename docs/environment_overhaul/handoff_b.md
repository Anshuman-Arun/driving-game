# Agent B — vegetation asset handoff

Base: 67023539e56e5e80d5efcd3f3239be9650c6f462 (verified identical to main at dispatch). Branch: feat/env-b-vegetation-assets. Draft PR #45: https://github.com/Anshuman-Arun/driving-game/pull/45. Original candidate commit: 69eb322bbabcf77adb78e8640c536355ed08867c. Verified implementation revision: b83037654f2782d9d3a1a3e4f0cc5762d2465f2b. Exclusive scope: assets/environment_overhaul, tools/environment_assets and this handoff.

## Deliverable and corrections

Five species, ten real self-contained glTF payloads, manifest v1, license notice, deterministic CLI and strict validation, CPU silhouette regression, optional existing-scan audits, Godot import tests and a contact sheet. Original assets use one opaque double-sided vertex-color PBR material, no external textures or normal maps, meter-scale Y-up ground-centered geometry. Total glTF payload 969478 bytes. No mature tree replacement, no fine grass, no root wiring, no shared status/license edits.

Initial review reproduced nine false positives: node translation, extra scene node, wrong active scene, index accessor zero, wrong accessor offset/stride/sparse override, missing PBR texture and invalid color factor. Fixed strict profile validation; later refactored to native Node crypto/Buffer with one strict decode pass, eliminating the duplicate validation path. Thirty negative fixtures require the intended failure reason, including noncanonical base64, duplicate geometry, wrong normals, overlapping buffer views and null accessors/materials. Corrected independent LOD RNG/normalization; both LODs share geometry landmarks and physical bounds. Second review found mismatched stem rings at joints and fern leaflet roots on a smooth curve instead of the sampled stem; replaced frusta with continuous tapered sweeps, anchored fern roots to the actual polyline and sapling branches to the trunk, replaced point-connected reed leaves with continuous blades. LOD1 now retains foliage density, simplifying folds and rings instead of dropping leaves/petals. The 35% minimum triangle reduction remains enforced. Projection test fails when any of 24 views per species has IoU below 0.80 or projected area ratio outside 0.8..1.2.

## Baseline asset audit

- Curated pine_tree_lod0.gltf and pine_tree_lod1.gltf: 120 and 49 triangles across seven/four meshes, original generator; deciduous_tree.gltf 1448 triangles across 15 meshes. These low-poly curated glTFs are not new candidates or evidence for premium derivatives.
- valley_tree_factory.gd builds a phototextured instanced surface using procedural trunks/canopy sprays and existing pine_bough/broadleaf_spray and bark shader inputs. Preserve it.
- premium_mesh.gd collects transformed mesh parts, fits to a ground-centered parcel, groups material/format and preserves UV/material association; enables anisotropic mipmaps and scissor at 0.39 for known alpha textures. valley_vegetation.gd uses PremiumMesh.fit("fern", Vector3(1.5, 0.92, 1.5)).
- premium_world payload ledger lists Fern 02 and Fir Sapling Medium complete; source glTF metadata shows 6232 and 1533513 source triangles. Source fern diffuse JPG cannot hold its mask, fir twigs originally used BLEND. The alpha_fix record identifies original opacity restoration. Prior ASSET_LICENSES.md and WORLD_VISUAL_QA.md describe UV-matched scissor runtime conversions.
- Fern 02: https://polyhaven.com/a/fern_02, Rob Tuytel (scanning), Rico Cilliers (modeling), CC0-1.0. Runtime GLB LFS expected 1908084 bytes, SHA-256 b081b04855ef451972742bc4e4d3862eb9567a31dad55600b547ac26aeebc4cd.
- Fir Sapling Medium: https://polyhaven.com/a/fir_sapling_medium, Rob Tuytel (photography), Rico Cilliers (modeling), CC0-1.0. Runtime GLB LFS expected 14585660 bytes, SHA-256 cff013dfbe455ce8016aa82a26faf1c6747ebf72f95c18d7a59979689447f149.

Actual PNG bytes fetched via connector at pinned base and decoded in JavaScript with bounded DEFLATE, PNG chunk CRC, zlib Adler-32 and all five scanline filters; verified known 3x2 Pillow RGBA fixture before processing sources. Both source textures are 1024x1024 RGBA8, not opaque rectangles. At scissor 0.39 (alpha bytes >=100 retained):

| Existing source PNG | SHA-256 | Below | Above | Partial alpha | Coverage |
|---|---|---:|---:|---:|---:|
| fern_fern_02_diff-fern_02_alpha.png | 077638c74ae88184f8eba1dfc8608904eafd3272aa4d2e587f05109bd5b9c943 | 884688 | 163888 | 60917 | 15.6296% |
| fir_fir_sapling_medium_twigs_diff-fir_sapling_medium_twigs_alpha.png | 83c7b1863d533a6e86e2d6b2509ad4ee883f8877c11b5549fee1f6bb5baa9603 | 793931 | 254645 | 142862 | 24.2848% |

audit_alpha.py independently reproduces pinned byte and coverage checks with Python stdlib zlib. Its four native synthetic PNG tests passed; it has not been run against local copies of the two actual source PNGs. Actual connector analysis above is not a Godot material/UV or GLB byte verification. Connector returns only LFS pointers for both runtime GLBs. GLB audit now checks real accessor bytes, offsets, strides, finite data, index range and nondegenerate triangles in addition to container/reference checks. Unsupported compressed/sparse geometry fails explicitly. Existing actual GLB triangle counts, tangent data, texture binding and artistic quality remain unverified. Reuse via unchanged PremiumMesh.fit only after actual audit. No duplicated scans or new scan LODs.

## Executed evidence (latest revision)

Node 22.16.0, Python 3.13.5:
- Full native generator CLI --self-test, --verify and --stage executed successfully. Fresh isolated staging wrote 12 files, repeat changed zero. Final sapling edit staged three changed files, full latest data gate verified the manifest and ten payloads. Native SHA-256 from the tested files compared to GitHub readback at b830376: 13/13 Node/Python modules and 12/12 asset/manifest/license files matched exactly.
- 30/30 reason-specific glTF negative fixtures rejected; two SHA-256 known vectors, deterministic regeneration, shared LOD vertex/color correspondence and budget checks passed.
- 20/20 staging filesystem checks passed (Linux). Synthetic Git core.autocrlf=true checkout preserved LF bytes for the three hashed resource types.
- 19/19 synthetic GLB fixture tests passed, including real nondegenerate position data, offset/stride/sparse errors, nonfinite data and out-of-range indices. The synthetic embedded image in GLB reference fixtures is a signature-only fixture, not a decoded texture.
- 4/4 synthetic RGBA PNG tests passed (exact alpha counts, corruption, truncation and LFS-pointer rejection).
- 8/8 strict subprocess runner tests passed, including zero-exit engine error, stderr error, missing exact marker, timeout and invalid report.
- Final CPU silhouette suite 120/120 passed, minimum IoU shrub 0.9454, fern 0.8932, sapling 0.9527, reed 0.9454, wildflower 0.8364. Coverage ratios 0.8364..0.9986 across views. Independent trimesh 4.11.1 load of all ten glTFs succeeded; finite vertices/face normals and nondegenerate face areas checked. These are CPU geometry checks, not GPU validation.
- Full data gate exit 0 with explicit "Godot gates NOT RUN (--data-only)". No engine or renderer available. Attempted pinned official Godot archive URL with bounded curl timeout; failed DNS (Could not resolve host: github.com). No local LFS clone, actual LFS bytes remain unavailable.
- Existing map-regression.yml triggers only its own branch pushes or manual dispatch; connector exposes no workflow-dispatch action. No changes to F's workflow or other agents' branches. No CI pass claimed. No real Godot import, integration suites, source scan GLB validation or local graphical/GPU approval claimed.

## Reproduction and remaining gates

From repository root, use Node 20+ and Python 3.10+, no external packages:

    python tools/environment_assets/verify_headless.py --data-only
    node tools/environment_assets/generate.mjs --self-test
    node tools/environment_assets/generate.mjs --stage
    node tools/environment_assets/generate.mjs --verify
    python tools/environment_assets/audit_alpha.py

After git lfs pull and installing the checksum-pinned Godot 4.7.2 standard editor using .github/workflows/map-regression.yml:

    python tools/environment_assets/verify_headless.py --existing --regressions
    godot --path . res://tools/environment_assets/contact_sheet.tscn

Use --godot /path/to/executable if needed. The runner performs strict log/exit/marker checks, bounded timeouts (420s per inherited regression), root import, owned test_import.gd, optional existing-scan test_existing.gd, and applicable map_width_check.gd, roadworks_check.gd, world_visual_qa.gd, garage_world.gd and vehicle_world.gd. It reports inherited failures without loosening assertions. Omit --existing for original candidates only. Local compare near/oblique/backlit views, rotating silhouettes, roughness and foliage color, LOD transitions at 25/65m, pilot density and scene timing. No FPS inference from CPU projections or headless.

## Proposed ledger entry (coordinator only)

| Original procedural understory (shrub, fern, sapling, reed, wildflower, two LODs each) | local://tools/environment_assets/generate.mjs | Aster Valley project original procedural geometry | CC0-1.0 generated assets; assets/environment_overhaul/LICENSE.txt | assets/environment_overhaul/manifest.json (per-resource SHA-256) | No external model, texture, download or AI-image source; meter-scale Y-up leaf/stem geometry |

Proposed PROJECT_STATUS entry: Agent B delivered five optional original species, ten standalone glTF scenes, native deterministic staging and strict validation; all CPU/data gates passed, actual existing source alpha PNGs decoded and checksum-pinned. Real scan LFS GLBs, Godot import/integration, local graphical acceptance and GPU timing remain outstanding. No production integration or other agent changes.
