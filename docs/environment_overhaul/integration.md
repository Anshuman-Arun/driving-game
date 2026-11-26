# Environment overhaul pilot — coordinator handoff

Draft PR #52, base 67023539e56e5e80d5efcd3f3239be9650c6f462 (map-width PR #43 included). Initial integration 0c615e27952fde98dfc0f654a78b78da31630f22 preserves exact Git subtrees and parent histories; all six candidate PRs still unmerged to main. A 8d88b103b26ee9dbc39229d1a1dedcd827bf320f, B d10f33a27a453120933fc0fb130ac2db972e2993, C 317894f48de470640ef171f7a386e5ea706c2a0b, D cd7367825f024132397fdc502b73b3c9190fd624, E 55d4953fb9ed4a190e3d124106cd58be7d8d854d, F 3a586ff64038eb48d65061e319be68f5509122aa.

## Opt-in game
Baseline default (unset or off). Windows PowerShell, root checkout with LFS and real mask:
```powershell
$env:ASTER_ENV_PILOT="cedar" # or valley
godot --path .
```
Cedar XZ Rect2(-990,-274,240,240) is anchored on F's actual road pose (-870,-154), Valley Rect2(-48,50,240,240) at (72,170). These deliberately small 240m pilots respect D's 256m raster bound, not a whole-map override. Select one per session (public drive.configure_environment_pilot allows runtime A/B); no spawn position or gameplay change. Drive to the site or use existing QA pose capture.
Set ASTER_ENV_GRASS, ASTER_ENV_TERRAIN, ASTER_ENV_UNDERSTORY, ASTER_ENV_RENDERING to 0 for independent isolation, 1/default enabled. ASTER_ENV_BEND default 0. ASTER_ENV_PILOT=off or unset disables all, no save changes. Live quality changes restore E before applying original quality, then reapply E inside the pilot on next frame; Ultra leaves E inactive and uses A High cap. A owns only published 16m chunks, including legitimately empty mask cells; legacy kind-2 offsets remain intact, other species unchanged; eviction restores old grass; affected visible 48m batches rebuilt. D is applied only to the selected pilot, restored on scenery-off. E is global lighting while vehicle is inside selected region (not a spatially blended light); no paint or camera preview. Understory verifies mask provenance and source/asset hashes, exact transformed union-of-LOD bounds, road and shoulder clearance, finite terrain footprint/slope, C's authored source exclusions plus actual retained plant and selective collider footprints, fixed 1600 placement cap, 32m cells with two LOD ranges, no new colliders. Missing/corrupt data refuses or skips; no fabricated assets. Live noncollidable authored props use C's conservative source exclusions, not a new exact render-overlap oracle. Headless doesn't validate actual mesh visibility, shader compilation on Vulkan, or frame timings. Full export needs smoke to verify raw glTF/source-hash availability; safe skip if missing.

## Mask and CI
With full checkout and pinned Python 3.12:
```bash
git lfs pull
python -m pip install -r content/scenery/environment_overhaul/requirements.txt
python content/scenery/environment_overhaul/bake_biomes.py --project . --output content/scenery/environment_overhaul/masks --seed 20261121
python content/scenery/environment_overhaul/verify_package.py --project . --mask-dir content/scenery/environment_overhaul/masks
python tests/environment_overhaul/qa.py --mode integrated --prepare-mask --out /tmp/aster-env-integrated
```
F's workflow runs the actual strict integrated mode on this branch; retains real mask and QA logs. The one-time mask publication run [45740717963](https://github.com/Anshuman-Arun/driving-game/actions/runs/45740717963) passed both jobs and committed the four verified files at `03eac9972dd578090ac24a3d8c86af86ad837865`. SHA-256 `af558d42230a2bd153b2a12d00e47afc3ab41c191dca3a63a0c2f68e81d531dc`, 15 verified sources, 2,585 placements, zero geometry misses, reproducible bake. The temporary write-capable publication workflow has been removed; later rebakes require explicit reviewed commits. Production pilot test extends the real F root fixture with per-region build, coverage/legacy ownership, terrain/environment restore and lifecycle checks.

## PR #51
Local preservation snapshot 2f666399df0c5a6a73a9c3986e2c199955ad8103 based on c4ad06887fad338e30d63837f28d8369806f811f, not current main. 250 changed files include replacement vegetation.bin and bake, valley_vegetation.gd, aster_valley_environment.gd, road/terrain shader/materials, tree and understory LODs, many assets, tools/environment_assets and reports. Do not transplant the older root, canonical bake or materials: conflicts with current widened roads and A–E contracts. Candidate mature tree LOD and source texture improvements are promising but need per-file/license/clearance audit and matched local A/B, deferred rather than blindly merged.

## Local acceptance
Run F capture.ps1 following handoff_f.md, matched native 1080p Senna baseline/candidate, Cedar/Valley stationary, physical route, off-road, low/medium/high; start with all env vars unset for F independent adapters (its capture currently isolates A/D/E, not this production switch). Then inspect the actual game with the production switch and isolate each feature. Tune A cap/density/radii, D local tint/normal/roadside controls, E shadows/exposure in that order. No claim of graphical approval, GPU timing, 60 FPS, or integrated traffic. Main's live root has no traffic wiring (F documents this); do not add gameplay changes or fabricate traffic telemetry. Baseline CI F run 45731411855 passed seven jobs. Initial combined CI run 45740078156 passed six jobs but found a grass parser error before cancellation. The single-argument maxf call was fixed in 843f43617ffbb24905ac577be7988180873af58f. Final integrated and packaged acceptance pending.
