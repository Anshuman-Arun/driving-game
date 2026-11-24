# Project status — single current-state log

Last updated: 2026-11-23

## Consolidated premium asset handoff (`feat/consolidated-premium-assets`)

Combined verified binary payloads from PRs #30, #31 and #32, without changing runtime files or importing source branch workflows. Six full vegetation/rock models, three texture-only packages, 20 complete garage/world packages, and 35 WAVs including 32 engine loops; missing asphalt and impact files documented in manifests. Asset checksum/structure workflows passed; runtime adoption, license review of audio candidates, visual QA and performance remain pending. See prompts/WORLD_VISUAL_PREMIUM_OVERHAUL.md. Local uploaded car candidates not distributed; see docs/LOCAL_VEHICLE_EVALUATION.md.

## Water crossings, roadside detail and instruments (`feat/local-showroom-dashboard`)

Eastwater Viaduct, Alder Creek Bridge and Needle Pass Trestle carry existing routes over new water at lake, valley and mountain elevations. Five corridors have wider pavement with tapered approaches. The bridge decks, rails and shoulder surfaces participate in driving collision. The root game loads a separate roadworks heightfield while the standalone runtime can still load the canonical world. The scenery layer accounts for 12 placements displaced by the new banks.

Rebuilt trees use tapering branches, textured foliage, two levels of detail and nearby shadow casting. Camera-local batches stream from 235,686 terrain-aligned placements, including thicker conifer stands, road-edge grass, wildflowers and rocks. Alder houses, barns and workshops have new materials and facade details. The driving HUD shows a heading-up contour map with the new water and an open RPM dial with live gear and MPH.

`content/scenery/tools/bake_roadworks.py` writes the roadworks profile and heightfield to a staging directory. Run `content/scenery/tools/bake_vegetation.py` with the same project and output arguments to regenerate vegetation and the map atlas against that heightfield.

Godot 4.7.2 verified all five widened sections with collision rays and drove the live chassis over all three spans. The garage-world regression passed, and the standalone world passed all 642 road rays. Forward+ captures covered the crossings, all five regions and the HUD at 1600×900 and 1280×720. At a fixed Cedar Woods camera on the RTX 4050 Laptop GPU, the vegetation-enabled run measured 5.74 ms median and 6.01 ms 99th-percentile GPU time. Presented frames hovered around 60 in the test window, and uncapped frame rate remains unverified.

## Valley scenery and instruments (`feat/local-showroom-dashboard`)

The five regions now share 110,099 baked, visual-only placements for groves, meadow cover, wildflowers and boulders. Camera-local MultiMesh cells load the ground cover, nearby canopy casts real sun shadows, and the graphics preset adjusts active coverage. Photogrammetry meadow, leaf litter and mossy rock textures distinguish the terrain. A bounded leaf pool uses gravity and wind to land leaves on the surface. The driving HUD uses contour relief, water, a rotating compass, and region names alongside a segmented RPM bar, gear display and MPH readout.

Godot 4.7.2 imports and the garage-to-world integration passed. The Forward+ run captured all five regions, exercised live speed and gear, and checked leaves settling, terrain shadows, and quality changes. At 1600×900 on the RTX 4050 Laptop GPU, a fixed Cedar Woods camera measured 3.22 ms median GPU render time with supplemental vegetation visible and 2.93 ms with it hidden. The respective presented frame-rate readings were 61 and 119 FPS in that short sample. This was a scene-specific measurement. Low and High coverage changes were also checked headlessly.

## Home, garage, driving HUD and rendering (`feat/local-showroom-dashboard`)

Home and Settings share an original color treatment and bundled Barlow typography. Settings keeps the offline profile, exposes the live controller steering response, and supports directional focus through Display, Controls and Audio. The garage keeps its live turntable, and the pause screen now leaves the world visible. Free roam shows live MPH, gear, engine RPM, and a heading-up minimap built from the canonical road data.

The viewport uses native TAA on Medium. Low uses an 85 percent 3D scale and FXAA, and High adds 2× MSAA to native TAA. Road, terrain, and water textures now import with mipmaps and VRAM compression. Duplicate same-facing triangles were removed from the three hero car GLBs, and preview and driving materials use smoother paint and glass reflections. Tire smoke and dust use a shared soft alpha texture at 14 particles per emitter.

Godot 4.7.2 import, 53 shell checks, the garage-world integration suite, and Forward+ checks of settings focus, live telemetry, parked car switching and off-road dust passed. At 1600×900 on the RTX 4050 Laptop GPU, the repeated showcase reported about 446 MiB peak video memory versus about 649 MiB before the overhaul. The North Ridge route with the HUD averaged 60.9 presented FPS on Medium, with a 4.97 ms median and 8.18 ms 99th-percentile GPU render time. All tested quality configurations hovered around 60 presented FPS in that run. Physical controller and uncapped FPS validation remain open.

## Forza visual fidelity overhaul (`feat/forza-fidelity-overhaul`)

Upgraded all three hero vehicles (`vela_gt.glb` Porsche 911, `orion_rs.glb` Khronos CarConcept, `kestrel_xr.glb` Porsche 918 Spyder Weissach), environment/building models, 2K Poly Haven CC0 PBR terrain/road/water shaders (distance-attenuated normals, 2x MSAA + FXAA + debanding + 16x Aniso + smooth SSAO, SSIL off), HDRI outdoor & garage studio lighting, Forza-style `DriftController` + Xbox Series controller + right-stick look-around camera, and `VehicleVisualFX`. Pass 6 Godot 4.7.2 Forward+ QA (RTX 4050 Laptop GPU, scenery on) passed with 0 failures across all 5 headless suites (`game_shell` 53/53, `core/smoke`, `steering_camera`, `drift_and_controller`, `world_runtime -- --full-world` 642/642 road rays) and graphical suites (`garage_world.gd`, `vehicle_world.gd`, `forza_showcase_qa.gd` 88.1 FPS mean at 1600x900, 648.9 MiB VRAM). See [CURATED_BUILD_QA.md](../tests/integration/CURATED_BUILD_QA.md) and [ASSET_LICENSES.md](ASSET_LICENSES.md).

## Curated vehicle and scenery integration

The root game enters the garage and menu, and launches canonical free roam with the selected Vela GT, Orion RS or Kestrel XR. Curated GLBs follow the existing chassis and wheel mounts. The five-region scenery layer can be disabled independently of the world collision. Godot 4.7.2 import, the full-world road sweep, the graphical garage and driving flows, and selection recovery after restart passed. The [build validation report](../tests/integration/CURATED_BUILD_QA.md) records commands, performance, screenshots and visual limitations. Physical controller checks and production vehicle-art integration remain open.

## Vehicle and world integration

The free-roam integration branch boots the full canonical Aster Valley terrain and roads with the corrected Vela GT. Import, the full-world collision sweep, Core regressions, and three integrated headless and Forward+ routes passed on Godot 4.7.2. See the [vehicle/world validation report](../tests/integration/VEHICLE_WORLD_QA.md) for performance, screenshots, and remaining handling checks.

## Confirmed
- GitHub repository Anshuman-Arun/driving-game exists and is private.
- Design documents, initial prompt, and shared agent workflow are committed on main.
- Target software stack and scope have been selected for a compatibility proof.

## Not yet done / do not claim otherwise
- No Godot project.godot, scene, imported addons or working executable exists yet.
- No Terrain3D + Road Generator + Easy Vehicle Physics integration has been performed.
- No driving performance, controller operation, FPS or visual quality has been tested.

## Next milestone: P0, then P1 if viable
Open the GitHub clone in Antigravity; use prompts/FIRST_EXECUTION_PROMPT.md to create the first playable 500x500 m driving scene. Verify the plugins individually and in combination. Stop and report any incompatibility.

## Report template for future agent updates
Date and branch:
Commit or PR:
What now works:
Tests and measured results:
Not tested:
Dependencies and asset licenses:
Known blockers:
Next task:

Do not mark a phase complete on the basis of code generation alone.
