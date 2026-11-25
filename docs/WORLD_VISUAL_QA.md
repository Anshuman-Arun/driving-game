# Aster Valley world and vehicle visual QA

The integration starts from the local graphics baseline `3bfcb63` and references premium source commit `86116e9`. The primary implementation is `93fbfbc`. A separate local checkout contains the audio integration in progress. The graphics branch verifies the audio payload and leaves playback to that integration.

## What broke and how it was repaired

The baseline submitted 25,025 instances through a second foliage runtime. Its cached scatter checked a candidate against its own road centerline and old nominal width. It missed widened sections, junction polygons and overlapping roads. It also rebound opaque diffuse maps to meshes authored for different UV islands. This caused stretched bark across pine crowns and rectangular grass cards that remained opaque.

The world builder now indexes the 20,139 triangles used for pavement, shoulders, and intersection approaches. Vegetation and authored props test their transformed mesh and collider bounds against those triangles before they enter a MultiMesh or a physics body. The test considers height clearance above and below decks. Authored barriers can sit on shoulders with a setback from the pavement. The same rule applies on every load and to regenerated vegetation.

The obsolete layer had 859 visual bounds over pavement and 3,680 over pavement or shoulders, using the same zero-margin overlap check. The retained vegetation bake rejected 5,610 candidates at the configured safety margins and rebuilt to 230,076 placements. Twelve authored props were displaced by bank excavation, and another 15 failed the clearance margins. The remaining 2,764 authored placements, 3,564 near and far render instances, and 1,063 selective collision shapes had zero audited overlaps on the final network. The baseline and retained-layer counts describe different placement sets.

Asphalt and gravel now use physical-distance UVs for aggregate and a separate normalized UV for markings and ruts. The junction wear and roughness were tuned to match adjacent pavement. Bridge water received valid tangents. The terrain uses the matching cliff albedo, normal and ARM maps and skips the expensive triplanar code on flat ground. The fir and fern original textures now have verified alpha channels and alpha-scissor materials. New texture imports use mipmaps and VRAM compression. Low, Medium and High adjust render scale, shadow distance and atlas, AO, and vegetation coverage.

## Regional composition and asset choices

| Region | Applied treatment |
|---|---|
| Alder Town | Existing streetwall and workshops supplemented with village house and storefront meshes. The central junction and parked spawn are clear. |
| Cedar Woods | Grounded fir scans, ferns, woodland soil, and retained canopy LODs. |
| North Ridge | Reduced photogrammetry cliff geometry and coordinated cliff PBR materials on alpine slopes. Gravel approaches remain connected. |
| Green Valley | Authored meadow, farm fences, and barns with lower-LOD premium structure variants. |
| Eastwater Lake | Existing pier and shores, mossy rocks, and corrected bridge-water normals. |

The original three bridge structures and their collision spans were a verified fit for the widening and terrain. The overpass and tunnel source models do not replace those spans. The fuel station, lamp, pier scan, deadwood and traffic vehicle source candidates stay in their verified packs. Runtime assets come from matching lot sizes and distinct regional treatments.

## Vehicles

All six candidates were decoded and captured in the same studio. The three existing car IDs, their handling presets and their saved selections are supported. The Solace GT is an additional fictional tourer. It uses the original independent wheel and brake geometry on the existing GEVP interfaces. Its imported wheel centers determine visual scale and alignment. Paint, glass, chrome and lamp assignments are shared between showroom and driving views. See [the candidate contact sheet](world_visual_qa/candidate-audition.jpg).

| Audition | Disposition |
|---|---|
| Electric Grand Tourer | Adopted as Solace GT. Its separate wheels and calipers, supplied cabin and coherent proportions supported the live rig. |
| Wedge Supercar | Held for further art review. The windshield and faceted panels read flat under the studio rig. |
| Mid-Engine Exotic | Held. High mesh-node count and opaque-looking glass need a dedicated optimization and rig pass. |
| Front-Engine Grand Tourer | Held. Its 397 mesh nodes and windshield treatment exceed the budget for a second tourer in this pass. |
| Retro JDM Coupe | Held. Its 400 mesh nodes and interior presentation need more work. |
| Spectral GT RS | Held. The audition reproduced the exposed cockpit components and disconnected-looking surfaces documented in the previous art review. |

## Matched Forward+ captures

All pairs were captured from a true 1920×1080 SubViewport at the same pose on the RTX 4050 Laptop GPU. An automated driver applies throttle during the Medium measurement. The 52-frame samples describe local performance and do not measure every moment of a full tour. [All timings and counters](world_visual_qa/metrics.csv).

| Scene | Baseline | Integrated |
|---|---|---|
| Alder Town | [Before](world_visual_qa/before-alder.jpg) | [After](world_visual_qa/after-alder.jpg) |
| Cedar Woods | [Before](world_visual_qa/before-cedar.jpg) | [After](world_visual_qa/after-cedar.jpg) |
| North Ridge | [Before](world_visual_qa/before-ridge.jpg) | [After](world_visual_qa/after-ridge.jpg) |
| Green Valley | [Before](world_visual_qa/before-valley.jpg) | [After](world_visual_qa/after-valley.jpg) |
| Eastwater Lake | [Before](world_visual_qa/before-eastwater.jpg) | [After](world_visual_qa/after-eastwater.jpg) |
| Garage | [Before](world_visual_qa/before-garage.jpg) | [After](world_visual_qa/after-garage.jpg) · [Solace GT](world_visual_qa/after-garage-solace.jpg) |

| Medium at native 1080p | Baseline FPS | Integrated FPS | Baseline GPU p99 | Integrated GPU p99 |
|---|---:|---:|---:|---:|
| Alder Town | 76.4 | 120.0 | 14.35 ms | 4.84 ms |
| Cedar Woods | 53.5 | 121.8 | 20.16 ms | 7.60 ms |
| North Ridge | 48.6 | 123.0 | 22.19 ms | 6.08 ms |
| Green Valley | 63.3 | 122.2 | 17.12 ms | 5.17 ms |
| Eastwater Lake | 72.3 | 122.7 | 15.28 ms | 4.62 ms |

Peak measured Medium video memory fell from 827.1 to 650.9 MiB. Medium's highest p99 engine frame interval was 9.10 ms. High averaged 84.1–119.7 FPS across these scenes and had one p99 interval of 16.71 ms at Green Valley. The 1080p viewport still reports engine frame intervals, which can differ from physical monitor refresh. All three presets accepted and persisted their values. The renderer's primitive counter includes shadow passes. It rose in Cedar Woods with the detailed firs even while renderer time and draw submissions fell.

## Verification and regression results

- Each of the 2,450 sampled directed-lane positions first hit a road surface. Forty-eight live chassis driving samples covered the 16 physical corridors, including all four gravel connectors. All three bridges passed full-span driving and barrier collision, and all five widening sites passed edge collision.
- Four cars loaded in the garage and mounted on the live chassis with four grounded suspension contacts. The garage regression passed for selection, parked swapping, save reload, camera cycling and hood anchor tracking. The shell passed 53 checks. Core smoke, steering, camera, drift, car-material, and guardrail tests passed.
- The material audit inspected 171 bound materials and 190 texture bindings, and directly checked decoded alpha and alpha scissor on the two converted foliage assets. Final 1080p traces showed zero shader errors.
- The standalone world suite passed 642 road rays, 72 junction midpoint rays, and 196 seam checks. Racing passed 156 checks and traffic passed 48. Canonical junction safety passed 83 of 85 on both revisions. The same two 45-second traffic-flow assertions failed with seeds `20261121` and `73` on the baseline and integration. The canonical controls fixture comes from `origin/feat/world-traffic-content` and was copied into the QA checkouts for that run.
- Offline acquisition verification passed for 60 world files, 67 garage/world files and all 35 WAVs. Windows line-ending conversion on the upstream glTF JSON files initially changed their checksums. The byte-preserving Git attributes restore exact acquisition hashes. Source ledgers still record the unavailable asphalt and impact downloads.
- The standalone Windows executable boots offline. The package-only smoke test loads the world, scenery, and license ledger, selects Solace GT through the garage, mounts the car, and accelerates to 7.08 m/s. Godot emits one UID warning for the nested world script and successfully loads the same script by its packaged path.
- The driving sweep uses distributed start points on each corridor plus end-to-end drives on the three bridges. A continuous manual drive and physical controller were outside the verified coverage. The interactive Windows session ended when the user stopped desktop control. The final package was exercised through the launcher boot and the package-only smoke script.

### Reproduction commands

Use the Godot 4.7.2 console binary from the integration checkout. Put the captures and build outside the repository.

```text
godot --headless --editor --import
godot --headless --fixed-fps 120 --script res://tests/integration/world_visual_qa.gd
godot --headless --fixed-fps 120 --script res://tests/integration/roadworks_check.gd
godot --headless --fixed-fps 120 --script res://tests/integration/garage_world.gd
godot --headless --path modules/world_runtime --script res://tests/smoke.gd -- --full-world
godot --headless --path modules/game_shell --script res://tests/run_tests.gd
godot --headless --path modules/racing --script res://tests/run_tests.gd
godot --headless --path modules/traffic --script res://tests/run_tests.gd
godot --disable-vsync --script res://tests/integration/visual_compare.gd -- <absolute-capture-directory>
godot --headless --export-release "Windows Desktop" <absolute-output-directory>/AsterValley.exe
godot --headless --main-pack <absolute-output-directory>/AsterValley.pck --fixed-fps 120 --script <absolute-repo-directory>/tests/integration/packaged_smoke.gd
```

Use `-- --rebake=<absolute-binary-path>` with `world_visual_qa.gd` to regenerate the filtered vegetation cache from its candidates after a road or scenery change. The checked-in bake produced zero rejections on a second audit. The two offline visual verification scripts can also run from a separate checkout using absolute paths.
