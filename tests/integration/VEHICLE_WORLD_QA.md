# Aster Valley vehicle and world integration QA

## What boots

The root Godot project opens `scenes/free_roam/aster_valley.tscn`. This scene calls the existing World Runtime in full-world mode and creates one Vela GT using the corrected Core factory, adapter, input, and chase/hood camera. World build uses the original coordinate system and canonical files in `data/world/`.

The World Runtime exposes each collider's source surface as metadata. The scene translates asphalt, gravel, and terrain into the matching GEVP groups. One road or pad body still covers its deck and shoulders. The per-wheel grip blend from Core handles changes between colliders. Spawn and respawn project onto the canonical travel lanes, reserve 26 m from lane endpoints, and ray-check the center and all four wheel positions. Out-of-map recovery uses the same lane search. The prototype remains individually launchable at `res://scenes/bootstrap/main.tscn`.

## Driving controls

W / ↑ accelerates, S / ↓ brakes or reverses, and A/D or ←/→ steers. Space is the handbrake. R resets to a nearby road, C cycles the two chase views and hood, and Esc pauses or resumes. Existing Core controller mappings are retained.

## Verified on Godot 4.7.2 for Windows

- Root editor import and normal launch passed. The editor recognizes `modules/world_runtime` as a nested standalone project and skips its automatic filesystem scan. The runtime is explicitly referenced by the free-roam scene and successfully loads.
- Canonical world and turn-generator checks passed from a Git archive that preserved LF bytes. The stock Windows checkout converts the SVG line endings, which affects the generator's exact text comparison without changing world data.
- Standalone full-world smoke passed with 72/72 junction mid-rays, 216 turn samples, 642/642 road rays, and 196 terrain-seam checks.
- Core smoke and steering/camera regressions at 30, 60, 83, and 144 simulated render FPS passed with physics at 120 Hz.
- The integrated scene loaded 256 terrain chunks, 16 physical road corridors, and 11 junction pads. It contained **283 world static colliders** and one Vela chassis collider. Spawn settled with **four asphalt wheel contacts**.
- Integrated headless and graphical drives passed. R righted the car near the current road, out-of-bounds recovery returned it to a drivable lane, and cycling to the hood kept the camera attached.

## Graphical drive and performance

Godot 4.7.2 Forward+ on the NVIDIA RTX 4050 Laptop GPU, Vulkan 1.4.325, 1600×900 window. The regression drove the production Vela and scene through three routes using test-only input commands. It repositioned the car between routes. All three drives had at least three grounded wheels for 100% of recorded ticks, with no ticks of complete contact loss.

| Route | Distance | Peak speed | Observation |
| --- | ---: | ---: | --- |
| Alder junction | 100.8 m | 22.0 km/h | Wheel contact on the authored junction pad while turning onto the road to Cedar. |
| Quarry Gravel Cut | 123.9 m | 36.9 km/h | Climbed 16.63 m under engine power, averaging approximately 13.4% rise over the run. |
| Green Valley to Eastwater | 104.0 m | 27.3 km/h | Asphalt to grass to four asphalt contacts. Peak one-tick grip change was 0.143. |

Normalized steering changed by no more than 0.030 in one tick across the three runs. A separate stationary three-pulse A/D check moved chase aim by 0.001°. The user described the live build as looking better. The brief feedback did not identify particular speeds or maneuvers, so higher-speed handling on the full map still needs hands-on confirmation.

World generation took **2.629 s**, Vela and camera were ready in **2.728 s**, and the 100-tick settle check completed in **3.770 s** from scene initialization. During the moving routes, **5,567 frames** averaged **119.7 FPS**, with an **85.8 FPS 1% low** and **9.68 ms p99 frame time**. Peak Godot static and renderer-reported video memory were **237.3 MiB** and **101.7 MiB**. Peak submitted work was **215 draw calls** and **241,116 primitives**. Timing excludes startup, route changes, and image readback or PNG writes. This is one local run.

### Actual viewport captures

- [Alder spawn](screenshots/01-alder-spawn.png)
- [Alder junction contact](screenshots/02-alder-junction-contact.png)
- [Gravel climb](screenshots/03-mountain-gravel.png)
- [Road-to-grass transition](screenshots/04-road-grass-road-contact.png)
- [Hood view after reset](screenshots/05-hood-after-reset.png)

### Remaining limitations

The wide Alder pad has visible shoulder/skirt seams where it meets its approaches. Roads have no line markings and the terrain uses the existing flat-color materials, so orientation is less clear at wide junctions. The Vela can roll downhill with the brakes released. The route checks covered three representative low- to moderate-speed sections. Sustained high-speed travel on the canonical map and physical controller behavior remain unverified.

## Reproduce

```powershell
godot --headless --path . --import --quit
godot --headless --path modules/world_runtime --script res://tests/smoke.gd -- --full-world
godot --headless --path . --fixed-fps 60 --script res://tests/integration/vehicle_world.gd
godot --path . --resolution 1600x900 --script res://tests/integration/vehicle_world.gd -- --capture-dir <existing-folder>
godot --path . --resolution 1600x900
```
