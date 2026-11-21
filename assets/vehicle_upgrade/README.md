# Vela GT — HD vehicle art handoff (2026-11-21)

**Status: PARTIAL / art not accepted.** The hero GLB is **not yet present**.
Do not claim this PR replaces the current placeholder. The read-only Core
factory is on PR #20, which has not been merged to `main`.
This branch is deliberately limited to the three owned directories.

## Source evaluation

| Candidate | Verified listing / license | Geometry and hierarchy evidence | Decision |
|---|---|---|---|
| **Spectral GT RS** | [Upstream](https://github.com/JaronKBragg7337/spectral-gt-rs), author Jaron Bragg, [CC0 text](https://github.com/JaronKBragg7337/spectral-gt-rs/blob/34499c501908818a2b08e589a7aecf963343cee7/LICENSE) | 4,688,844-byte downloadable GLB and editable BLEND. README claims 263 exported objects, cockpit, 4 animation clips, 59 mechanics parts, detailed wheels/brakes. **Binary geometry not yet inspected**. +X forward; independent parts but not a known GEVP rig. | **Preferred lawful model to prepare and test**, NOT yet shipped or cosmetically approved. |
| [Fab Spectra V35](https://www.fab.com/listings/15708b2a-78f7-405d-878a-74e96fab58ef) | Commercial catalog; exact entitlement/price unavailable in anonymous view | Publisher claims ~35k triangles, original futuristic body, interior, UVs/PBR, FBX/GLB. Wheel pivots and source geometry not inspected. | Shortlisted for licensed procurement only; **not downloaded**. |
| [Fab Generic Sport Car with Interior GameReady](https://www.fab.com/listings/8e584a96-5fce-4b3a-bb8d-f69291e78c99) | Commercial catalog; no purchase authorization | Publisher claims interior, wheels/doors, 9 materials, **up to 200k triangles/79 objects**; outside intended near-game budget without reduction. | Shortlisted if purchased + LOD optimized; **not downloaded**. |
| [Blendkit Generic Sportscar PL](https://www.blendkit.com/asset-gallery-detail/e4ac3813-f337-4c62-a61f-3fb85cab9a78/) | Free listing / Blenderkit royalty-free terms, plugin+account access | 523,639 polygons, 204.9 MiB, basic interior. Not verified as separate wheel hierarchy; far too heavy directly. | Rejected for hero runtime without extensive retopology and gated access. |
| [Sketchfab Generic Sport Coupé](https://sketchfab.com/3d-models/generic-sport-coupe-car-820a13c4831c41959ce75e6c2014e882) | Listing advertises CC BY attribution and simple interior | Original hierarchy, exact triangle count and lawful direct download not inspected. | Alternate only after rights and geometry verification. |
| [Innerscene generic mid-engine supercar](https://www.innerscene.com/tools/library/3d-parts/generic-mid-engine-supercar-73f252c5) | Author states original unbranded **CC0**, 3.8 MB free GLB | 4.631 m long / 2.090 m wide / 1.189 m tall, 2.7 m wheelbase. No confirmed interior or four independent wheel components. | Free alternative pending actual geometry/cockpit audit. |
| [Grab3D Sports Car](https://grab3d.com/models/vehicles/sports-car/) | Advertises CC0 and direct GLB | Four independent wheels but **opaque glass / no interior**, site describes lightweight model. | Rejected for cockpit hero use. |

**None of the two Fab listings have been licensed or paid for by the project.**
Storefront previews and watermarked files are not admissible project assets.

## Exact planned incorporated source

No third-party geometry has been committed yet. The only copied third-party
content is the CC0 legal notice `UPSTREAM_LICENSE.txt` from upstream.

- Asset ID: `vela_gt_spectral_cc0`
- Author: Jaron Bragg / JaronKBragg7337
- Original source:
  https://github.com/JaronKBragg7337/spectral-gt-rs/blob/34499c501908818a2b08e589a7aecf963343cee7/spectral_gt_rs_game_ready.glb
- Source revision: `34499c501908818a2b08e589a7aecf963343cee7`
- Source Git blob SHA-1: `f5b814848453a6c75a48f5047fdadaa7bdc78969`
- Source byte count: `4,688,844`
- License: CC0-1.0, [upstream license](https://github.com/JaronKBragg7337/spectral-gt-rs/blob/34499c501908818a2b08e589a7aecf963343cee7/LICENSE).
- Proposed changes: suppress upstream badge and plate text, orient -Z forward,
  rescale to chassis wheelbase and tire radius, separate static calipers,
  material-preserving draw-call consolidation, triangle LODs.
- Required artwork/output after actual build: `vela_gt_hero.glb`,
  `vela_gt_mid.glb`, `vela_gt_distant.glb` (currently **absent**).
- Existing legal fallback: the original Aster Valley Vela GT art,
  `assets/curated/models/vehicles/vela_gt.glb`, CC0 per the merged art manifest.

## Reproduction on a legitimately connected Blender machine

From project root on a workstation with Python 3 and **Blender 4.3/5.x**:

```bash
python tools/vehicle_upgrade/download_spectral.py
blender -b -t 4 --python tools/vehicle_upgrade/prepare_spectral.py -- \
  --source assets/vehicle_upgrade/source/spectral_gt_rs_game_ready.glb \
  --output assets/vehicle_upgrade
python tools/vehicle_upgrade/inspect_glb.py --enforce-lod hero assets/vehicle_upgrade/vela_gt_hero.glb
python tools/vehicle_upgrade/inspect_glb.py --enforce-lod mid assets/vehicle_upgrade/vela_gt_mid.glb
python tools/vehicle_upgrade/inspect_glb.py --enforce-lod distant assets/vehicle_upgrade/vela_gt_distant.glb
```

The downloader checks upstream **Git blob content SHA**, byte count and GLB
header, so the source cannot silently change with a branch update. Store source
geometry in the owned asset directory only; the local source is not a render
preview. The Blender script uses original mesh objects, not arbitrary new
primitive cars. It should refuse suspiciously incomplete wheel groupings.

After the actual model exists and the full Core project is present, run:

```bash
godot --headless --path . --editor --quit
godot --path . --script res://tools/vehicle_upgrade/capture_views.gd -- \
  --out /absolute/path/to/vehicle-qa
```

The second command must run in a **graphical GPU context**, not in headless CI.
It captures the existing and HD car at the same six camera angles, including
road-scale side, wheel, and cockpit. Inspect transparent glass, clipped tires,
normals, paint energy, brake behavior, steering and body-to-collider clearance.
GPU draw calls, total memory and FPS must be measured during real driving
before acceptance. Source showroom renders are **not** game screenshots.

The authoring and validation tools are entirely offline except the one-time,
license-verified source download. Gameplay must never require internet access.

## Blockers and next gate

Current execution environment has **no Blender and no Godot executable** and
cannot obtain the binary from raw GitHub; the GitHub text connector returns
an empty payload for this binary. Thus none of the generated LOD GLBs,
real wheel geometry inspections, Godot imports, screenshots, GPU draw calls or
FPS measurements can be truthfully reported. This branch delivers a pinned
lawful source plan, retarget/LOD automation and a non-invasive runtime adapter;
it does **not** satisfy production-art visual acceptance yet. Do not merge as
a completed hero-art upgrade.
