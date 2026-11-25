# Project status — single current-state log

Last updated: 2026-11-24

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

## Network-wide road envelope (feat/map-road-width-overhaul; pending runtime QA)

The root game uses explicit target pavement widths on all sixteen existing corridors: 10–11.2 m asphalt, 8.4–9 m gravel, with 2.0/1.6 m shoulders. Smooth tapers retain existing junction seams and three bridge decks. Junction hull buffers expand by 1 m. The canonical graph and existing roadworks heightfield remain unchanged; the authored corridor grading is reused. The runtime generates a conservative road/shoulder clearance raster to filter existing vegetation and relocate nearby roadside furniture where terrain permits. The vegetation bake uses the same profile for future verge placement. The standalone runtime without roadworks retains the original geometry. A separate 105 m elevated section of Meadow Causeway now gets bridge structure, level shoulders and solid rails above an existing deep depression, without changing water or terrain. Asphalt markings use metric width so painted stripes and texture scale stay consistent. Connector-side data check: 11,720 m of physical centerline, 9.86 m length-weighted mean pavement width versus the 6.8 m canonical baseline; 2,972 full-width edge height samples showed no terrain more than 0.15 m above the centerline (maximum 0.02 m). This is not a physics or render test. Godot import, collision regression, render and driving verification are still required; no new performance measurements are claimed.

### Regression audit, 2026-11-24

GitHub Actions run [45554634525](https://github.com/Anshuman-Arun/driving-game/actions/runs/45554634525) completed the data job and Godot 4.7.2 root import successfully. World regeneration, turn geometry, world-data preflight, race authoring, seven traffic fixture cases, three 90-second deterministic traffic simulations, two WAV asset tests and Python bake syntax checks passed. Independent connector-side audit performed 10,568 assertions with zero failures: 104 lanes, 144 exact directed links, four connected race routes, 3,338 pavement-edge samples (maximum terrain protrusion 0.085 m), and 3,250 non-elevated shoulder samples (maximum terrain drop 0.56 m). This is data analysis, not physics. Root regression group reported failure; detailed engine logs pending at time of writing. No visual, controller or FPS certification. The CI workflow is split into independent root and standalone jobs, stages scenery models before importing the standalone module, and continues testing after individual failures.

### CI rerun 2 (run 45554913247)

Root import, core smoke/steering/drift, all three existing live bridge crossings, garage-world, and headless showcase passed. Standalone world passed 642/642 road rays and 72/72 junction mid-rays. Traffic passed 48 checks; racing passed 156 + 66 + 483 checks, shell 53 checks, scenery 2,791 placements. Failures: two of 594 exact-station road-edge rays, stale fixed collider count and grass-route crossing the new elevated span, vehicle visual test configured a missing hero but real distant model, four audio type-inference errors, and missing canonical traffic controls in standalone context. Follow-up retains road coverage by checking both sides of each shared section edge, tests grass transitions on a dry widened corridor, derives expected collider counts including bridges, explicitly configures all absent visual LODs in the fallback test, types audio loop keys, and stages the pinned traffic-controls PR dependency only in CI. These changes require a new run; isolated seam misses, if any, are reported separately. No graphical or physical controller validation.

### CI rerun 3 (run 45556573201)

Data and complete root Godot suites passed: 1,782 widened-edge rays, zero isolated seam misses, all three legacy bridges, zero failures in vehicle/world, core, cameras, drift, garage, visuals (10/10) and headless showcase. Three live driving routes each recorded 100% ticks with at least three wheel contacts. Standalone world, racing, traffic fixture, shell, scenery and both audio assertions passed. Advanced traffic safety failed two 45-second combined flow checks (83/85); the traffic implementation and canonical graph are byte-identical to main, so this is not caused by the widened pavement. Added explicit failure diagnostics to the test without weakening its assertions. Also guard audio telemetry on detached vehicles, allow audio test teardown to complete, and add a direct live chassis and two-sided rail check for the new elevated span. These follow-ups require rerun; no new GPU or physical controller results.

### CI rerun 4 (run 45557180082)

All data and root-game suites passed again, including 1,782 edge rays and direct live-car crossing of the new 105 m elevated span with rails verified on both sides. Traffic diagnostics identify the sole failing assertions: 990 and 984 consecutive WAIT_AT_JUNCTION ticks (33.0/32.8 s; required <30 s) on Alder's market approach. Both seeds reached 20 cars, performed lane transitions and reported zero reservation-ownership, conflict or capacity violations. Traffic change: full stop dwell now progresses while existing reservations block entry; eligible conflicting all-way-stop arrivals use oldest-first priority with stable ID tie-breaking while independent movements remain eligible. Added explicit higher-ID older-arrival checks; existing 85 assertions remain. Audio smoke passed but leaked 15 resource references at exit, so stop and detach streams during teardown and allow audio processing to finish. Pending verification in subsequent CI run.

### CI rerun 5 (run 45557429329)

The experimental oldest-first scheduling change did not reduce canonical queue waits (1,002/984 ticks) and introduced an overlap failure in the ordinary traffic fixture (47/48). Reverted the behavioral experiment and its new priority fixture to the previous traffic implementation; retained all original safety tests and expanded diagnostics to identify the blocking reservations and downstream leaders. A separate traffic CI job now exposes those results independently. Audio smoke teardown passed cleanly, while regression teardown still reported leaked references; allow the same 0.10 s cleanup interval in both tests. No failed test is waived.

### CI rerun 6 (run 45557610817)

Root game, data and standalone jobs passed; basic traffic restored to 48/48. Advanced traffic remains 83/85: 990/984 consecutive WAIT_AT_JUNCTION ticks at Alder, no reservation/capacity violations. Diagnostics show waiting drivers' stop dwell remains incomplete while conflicting owners are moving through long connectors. A narrower follow-up completes mandatory stop dwell during conflict occupancy only for authored movements (no changes to legacy fixture admission or reservation conflict checks). Added three focused assertions and retained the original 30-second threshold. Both audio functional suites pass, though regression teardown still reports 20 resource references; this is not a clean engine exit. Pending verification.

### CI rerun 7 (run 45558759924)

Data, root and standalone jobs passed; traffic fixtures 48/48 and authored stop-dwell checks passed. Advanced canonical waits fell from 990 to 902 ticks for seed 20261121, remained 984 for seed 73; no reservation/capacity violations. Add oldest-completed-stop priority only between different conflicting authored movements, preserving legacy scheduling and same-movement headway. New priority fixture, unchanged 30-second limit. Pending CI.

### CI rerun 8 (run 45559138036)

Data, root and standalone passed; both audio tests exited without resource leaks in this run. Basic traffic 48/48; advanced 89/91. Arrival-order priority increased one canonical wait to 1,002 ticks and left the other at 984; removed that unsuccessful policy and kept the verified authored stop-dwell correction. Inspection found a structural traffic-demand bias: equal probability per lane, followed by sampling its entire length, makes shorter town roads far more likely to supply nearby traffic than long roads crossing the same radius. Replace authored automatic spawning with cached 12 m arc-length slots filtered to the actual local radius, excluding protected connectors and a 32 m approach buffer (or safe stop offset plus 12 m). Explicitly spawned/assigned cars, legacy fixture spawning, geometric reservations, speed limits and 20-car cap are unchanged. Add local distribution checks; original canonical queue thresholds and seeds unchanged. Pending verification.

Main independently advanced to ffb791f60afbbf9e8ef98af4c26038d7350bbc89 (52 commits since original base), including overlapping audio, world-runtime and scenery files; PR #38 reports merge conflicts and no new PR-triggered CI. Added a push trigger restricted to this feature branch, preserving main and its newer work. Branch CI verifies this branch only; reconciliation with new main is a separate integration task. Invalidate the cached travel spawn grid on control reconfiguration.
