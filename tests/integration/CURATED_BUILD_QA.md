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

- Godot 4.7.2 root import and graphical boot passed. Game Shell standalone suite passed 53 checks. Core physics and steering/camera suites reported zero failures.
- Keyboard events in a real Forward+ window opened the garage, navigated focus, selected Orion, drove, gated the garage while moving, reset, swapped to Kestrel while parked and preserved hood mode. All three garage previews and all five regions rendered. A separate graphical Godot process read the same test save and spawned the Kestrel with its AWD preset.
- World Runtime full-world smoke passed all 642 road rays, 72 junction mid-rays and 196 seam checks. Enabling and disabling scenery retained the same 310 world collision bodies. The root loaded 2,791 terrain-aligned placements and 10,286 lake triangles. The standalone scenery smoke and source validator passed, including 102 race exclusion zones.
- The Vela completed the Alder junction, a 16.63 m gravel climb and the asphalt–dirt–grass–asphalt route in Forward+. Each route retained wheel contact on every sampled tick. Maximum one-tick grip change was 0.109. Stationary A/D reversal changed chase aim by 0.001°.
- RTX 4050 Laptop GPU, 1600×900 Forward+, scenery on, 120 Hz physics. Across 5,523 graphical route frames, mean was 119.7 FPS, the slowest 1% averaged 83.6 FPS, and p99 frame time was 9.62 ms. World entry took 2.76 s. Godot reported peak static memory of 256.9 MiB and video memory of 104.3 MiB. These are local measurements for this route.

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
~~~

## Visual limitations

The curated cars have faceted surfaces, opaque glazing and shared starter body styling. Their imported body proportions are fitted to the shared chassis track and wheelbase, while wheel geometry follows the existing suspension, steering and roll mounts. The hood view uses an exterior anchor. Scenery meshes are decorative in the integrated game, including guardrails and structures. Road markings are sparse and Eastwater's low-poly shoreline steps are visible. Physical controller testing remains open.
