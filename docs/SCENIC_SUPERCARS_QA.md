# Scenic driving and supercar QA

The implementation at `732b3b2` starts from the local visual repair at `498ccf0` and integrates the owner's recorded audio merge at `cdf5ebd`. It uses the existing 2 km × 2 km map and the consolidated premium acquisitions at `86116e9`.

## World changes

- Matte road aggregate and road paint reduce white specular streaks toward the sun. Road and junction materials use the same tints. The meadow and mountain shaders use different mineral, pasture, and canopy tones. The scene has cooler overhead fill, warm direct sun and distance haze.
- MultiMesh undergrowth uses the UV-matched fern scan. Alder Town includes the fuel station and scan-based street lamps. Eastwater uses the timber pier from the source pack. The clearance audit still runs against the generated road surfaces and the rendered prop footprints.
- The North Ridge rail beam runs along its authoring bearing. Visual length and collision box dimensions use the same local axis and scale. The ornamental mountain ridges outside the drivable map use a single mesh, no collision, and no shadow pass.
- Bridge fascia, footways, and piers use a matte concrete shader with casting variation, streaks, and footway joints.
- Vehicle paint now samples supplied normal maps in the range expected by Godot. Untextured paint uses the mesh normals.

## Vehicles

The two cars use the original source mesh designs. The source Aventador is an exterior model with dark glazing. The Senna retains its cabin and steering wheel. Each GLB has four normalized wheel pivots with independent rims and rotors, static caliper meshes, and separate lamp emitters. The Aventador has an AWD preset and staggered radii. The Senna has an RWD preset. The original downloadable models, credit and transformation notes are listed in [the asset ledger](ASSET_LICENSES.md).

| Game resource | Optimized triangles | Materials drawn as mesh surfaces |
|---|---:|---:|
| Aventador SVJ | 314,418 | 56 |
| McLaren Senna | 252,108 | 61 |

The default engine profile is shared by the Aventador and Vela. The Senna uses the existing Kestrel V8 recording bank. The package includes the audio profile manifests used by the local audio runtime. Recorded audio starts and stops individual engine loops as their crossfade gains rise above or fall below −80 dB. The synthetic loops remain available in legacy audio mode.

## Automated checks

- The garage test exercises the two exact cars through selection, live chassis swap, four-wheel contact, steering, roll, acceleration, and save reload. The route audit loaded and drove all six cars.
- The clearance test found zero overlaps in 230,076 accepted vegetation placements, 3,559 authored near/far mesh instances and 1,057 authored collider shapes. All 2,450 lane samples hit pavement first. All 48 live corridor samples passed, including the four gravel links. The bridge test drove across the three spans and checked all five widened approaches.
- The material audit inspected 233 distinct materials and 220 texture bindings. Both alpha-cutout vegetation tests passed.
- Core smoke, steering and camera, drift and controller, and recorded audio integration returned success. The recorded-engine and legacy audio regression suites passed after the mixer change. Core smoke and recorded audio reported resource cleanup warnings during test-process exit.
- The offline Windows executable booted, and a package-only smoke test showed the Aventador in the garage and drove the Senna at 12.43 m/s with a recorded exhaust voice active. The loader reported the existing world-script UID warning and resolved its packaged resource path.

## Forward+ screenshots

| Region | Previous graphics build | Scenic pass |
|---|---|---|
| Alder Town | [Before](world_visual_qa/after-alder.jpg) | [After](scenic_supercars_qa/alder.jpg) |
| Cedar Woods | [Before](world_visual_qa/after-cedar.jpg) | [After](scenic_supercars_qa/cedar.jpg) |
| North Ridge | [Before](world_visual_qa/after-ridge.jpg) | [After](scenic_supercars_qa/ridge.jpg) |
| Green Valley | [Before](world_visual_qa/after-valley.jpg) | [After](scenic_supercars_qa/valley.jpg) |
| Eastwater Lake | [Before](world_visual_qa/after-eastwater.jpg) | [After](scenic_supercars_qa/eastwater.jpg) |
| Aventador SVJ | [Showroom](scenic_supercars_qa/garage-aventador_svj.jpg) | [North Ridge drive](scenic_supercars_qa/road-aventador_svj.jpg) |
| McLaren Senna | [Showroom](scenic_supercars_qa/garage-mclaren_senna.jpg) | [Eastwater drive](scenic_supercars_qa/road-mclaren_senna.jpg) |

## 1080p performance

The Forward+ benchmark used a 1920 × 1080 SubViewport on the RTX 4050 Laptop GPU and 120 frames per site. The [three-preset capture metrics](scenic_supercars_qa/metrics.csv) preceded the audio fix. The [Medium retest](scenic_supercars_qa/medium-retest.csv) includes the previous graphics build, the scenic branch before the audio fix, the scratch comparison with vehicle audio disabled, and the delivery build with recorded audio enabled.

| Region | Previous graphics FPS | Scenic before audio fix | Scenic with active-loop mixing | Final median GPU time |
|---|---:|---:|---:|---:|
| Alder Town | 59.6 | 17.3 | 52.0 | 5.36 ms |
| Cedar Woods | 60.6 | 53.5 | 48.0 | 9.40 ms |
| North Ridge | 60.6 | 50.8 | 50.5 | 7.02 ms |
| Green Valley | 60.7 | 28.9 | 56.2 | 5.90 ms |
| Eastwater Lake | 60.6 | 56.0 | 56.9 | 5.74 ms |

The final Medium samples averaged 53.6 FPS with the Aventador on North Ridge and 46.8 FPS with the Senna at Eastwater. Peak measured Medium VRAM was 680.7 MiB with the Aventador. The audio fix recovered much of the frame pacing in Alder Town and Green Valley. A stable 60 FPS across the full map remains unverified.

## Reproduction

```text
godot --headless --editor --import
godot --headless --fixed-fps 120 --script res://tests/integration/garage_world.gd
godot --headless --fixed-fps 120 --script res://tests/integration/world_visual_qa.gd
godot --headless --fixed-fps 120 --script res://tests/integration/roadworks_check.gd
godot --disable-vsync --script res://tests/integration/visual_compare.gd -- <absolute-capture-directory>
godot --headless --export-release "Windows Desktop" <output-dir>/AsterValley.exe
godot --headless --main-pack <output-dir>/AsterValley.pck --fixed-fps 120 --script <repo-dir>/tests/integration/packaged_smoke.gd
```

The GLB prep script `tools/vehicle_upgrade/rig_exact_supercars.py` takes the exact source ZIP, GLB and an output directory and runs with Blender Python. The staged GLBs use gltfpack 1.3.0 with `-kn -km -noq` and simplification ratios of 0.44 and 0.65 respectively.
