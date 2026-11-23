# Curated vehicles and scenery integration

## Run the build

Open the root `project.godot` with Godot 4.7.2. From the main menu, open **Garage**, select a car, return to the menu and choose **Play / Free Roam**. Press **G** while parked to swap cars, **C** for the two chase views and hood view, **R** to reset, and **F11** for native fullscreen. Settings includes a 3440×1440 windowed preset. The Shell saves the selection to `user://aster_valley_free_roam_v2.json`.

Scenery defaults on for the menu-driven game. Set `aster_valley/visuals/scenery_enabled` in Project Settings to turn it off on the next drive. `AsterValleyDrive.set_scenery_enabled()` also supports toggling it in an existing world. It uses the authoritative World Runtime height API and creates zero collision bodies. The standalone test scene and direct free-roam scene remain runnable.

## In-game screenshots

All images below were captured in the running Forward+ game at 1600×900. The Eastwater overview uses a test-only elevated camera over the live road.

| Vehicle | Garage | Chase | Hood |
| --- | --- | --- | --- |
| Vela GT | [Garage](screenshots/curated-build/garage-vela-gt.png) | [Chase](screenshots/curated-build/chase-vela-gt.png) | |
| Orion RS | [Garage](screenshots/curated-build/garage-orion-rs.png) | [Chase](screenshots/curated-build/chase-orion-rs.png) | |
| Kestrel XR | [Garage](screenshots/curated-build/garage-kestrel-xr.png) | [Chase](screenshots/curated-build/chase-kestrel-xr.png) | [Hood](screenshots/curated-build/hood-kestrel-xr.png) |

[Alder Town](screenshots/curated-build/alder-town.png) · [Cedar Woods](screenshots/curated-build/cedar-woods.png) · [North Ridge](screenshots/curated-build/north-ridge.png) · [Green Valley](screenshots/curated-build/green-valley.png) · [Eastwater Lake](screenshots/curated-build/eastwater-lake.png) · [Eastwater overview](screenshots/curated-build/eastwater-overlook.png)

## Validation

- Godot 4.7.2 root import and graphical boot passed (Pass 6). Game Shell standalone suite passed 53 checks (0 failures). Core physics (`tests/core/smoke.gd`), steering/camera (`tests/core/steering_camera.gd`), and drift/Xbox controller (`tests/core/drift_and_controller.gd`: `36.1°` peak drift slip at `14.12 m/s`, `0.1°` recovery, Forza right-stick orbit & recenter, Free Roam A-button safety) suites all reported 0 failures.
- Keyboard events in a real Forward+ window (`garage_world.gd`) opened the garage, navigated focus, selected Orion RS, drove, gated the garage while moving, reset, swapped to Kestrel XR while parked, and preserved hood mode (0 failures). All three Forza-caliber hero vehicles (`vela_gt.glb` Porsche 911, `orion_rs.glb` Khronos CarConcept, `kestrel_xr.glb` Porsche 918 Spyder Weissach) and all five regions rendered with 2K Poly Haven CC0 PBR shaders, HDRI sky/garage studio lighting, and AgX tonemapping.
- World Runtime full-world smoke passed all 642 road rays, 72 junction mid-rays, and 196 seam checks (310 static colliders, 251,001 height samples). Enabling and disabling scenery retained the same 310 world collision bodies. The root loaded 2,791 terrain-aligned placements and 10,286 animated lake water triangles.
- The Vela completed the Alder junction, a 16.63 m gravel climb, and the asphalt–dirt–grass–asphalt route in Forward+ (`vehicle_world.gd`, 0 failures). Each route retained 100.00% grounded wheel contact. Maximum one-tick grip change was 0.109. Stationary A/D reversal changed chase aim by 0.001°.
- RTX 4050 Laptop GPU, Forward+ (2x MSAA + FXAA + debanding + 16x Aniso + half-res smooth SSAO, SSIL off), scenery on, 120 Hz physics:
  - `forza_showcase_qa.gd` (1600×900, 179 driving frames, 0 failures): mean 88.1 FPS, 1% low 67.1 FPS, p99 frame time 14.68 ms, peak 475 draw calls, 477,272 primitives, 261.4 MiB static RAM, 648.9 MiB VRAM.
  - `vehicle_world.gd` (3440×1440 ultrawide, 1,857 frames, 0 failures): mean 39.9 FPS, 1% low 16.5 FPS, p99 frame time 53.27 ms, peak 870 draw calls, 1,228,065 primitives, 275.0 MiB static RAM, 972.5 MiB VRAM.

~~~sh
godot --headless --path . --editor --import
godot --headless --path modules/game_shell --script res://tests/run_tests.gd
godot --headless --path . --fixed-fps 60 --script res://tests/core/smoke.gd
godot --headless --path . --fixed-fps 60 --script res://tests/core/steering_camera.gd
godot --headless --path modules/world_runtime --script res://tests/smoke.gd -- --full-world
node modules/scenery/tools/stage_dependencies.mjs origin/main origin/main
node content/scenery/tools/validate.mjs modules/scenery/.world_source
godot --headless --path modules/scenery --editor --import
godot --headless --path modules/scenery --script res://tests/smoke.gd
godot --path . --resolution 1600x900 --script res://tests/integration/garage_world.gd -- --capture-dir <existing-directory>
godot --path . --resolution 1600x900 --script res://tests/integration/garage_world.gd -- --verify-profile <printed-profile>
godot --path . --resolution 1600x900 --script res://tests/integration/vehicle_world.gd -- --scenery --capture-dir <existing-directory>
godot --path . --resolution 1600x900 --script res://tests/integration/forza_showcase_qa.gd -- --capture-dir <existing-directory>
~~~

## Visual notes

All three curated vehicles feature smooth metallic clearcoat paint, transparent tinted glazing with visible cabins, suspension-synced static brake calipers, dynamic cool-white headlights, split red brake/tail lights, and matte-black inner wheel-well liners. Terrain, roads, and Eastwater Lake use 2K Poly Haven CC0 PBR textures with dual-scale anti-tiling, triplanar slope granite, and distance-attenuated water normals, alongside upgraded PBR environment and building models with grounded foundation skirts. Scenery meshes remain decorative in free roam, and physical controller testing remains open.
