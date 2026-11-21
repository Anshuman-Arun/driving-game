# Garage and vehicle integration QA

The root game opens the corrected Game Shell. Play starts the canonical Aster Valley scene with the chosen physics preset. The Shell garage is also accessible with **G** below 4 km/h. Pausing while moving does not unlock the garage. A parked swap replaces the chassis at the same pose, rebinds the camera, and keeps the active view mode. Reset still finds a safe road pose.

The free-roam profile at `user://aster_valley_free_roam_v2.json` offers all three cars. It uses the Shell's versioned save service with real selection persistence and no mock progression. The standalone Shell retains its existing profile and race unlock behavior. Presets share a placeholder chassis envelope and use distinct physical mass, engine torque, gearing, and driven-axle configuration.

| Car ID | Mass | Engine torque | Final drive | Drivetrain |
| --- | ---: | ---: | ---: | --- |
| `vela_gt` | 1,390 kg | 480 Nm | 3.60 | RWD |
| `orion_rs` | 1,190 kg | 380 Nm | 3.90 | RWD |
| `kestrel_xr` | 1,540 kg | 575 Nm | 3.30 | AWD (35% front torque) |

## Baseline and road reconciliation

This branch starts from PR #20 at `d34bad1`. It stages the exact `modules/game_shell/` tree from corrected PR #17 at `96cc085`, without modifying its scripts or merging that branch. PR #17 was subsequently merged into `feat/game-shell`. The corrective shoulder idea from Antigravity's `72ea8bd` is applied directly to PR #20's runtime. Render geometry and canonical data remain intact. The 27 shoulder/skirt collision bodies now contain separate triangles from the deck, with Dirt traction. The 310 resulting static colliders match the 310 generated surfaces. Respawn wheel checks accept asphalt and gravel decks and reject shoulders. Core steering and the scene's existing 3,000 m far clip are retained.

The real asphalt/shoulder/grass route confirmed Dirt wheel contact and a maximum one-tick grip change of **0.109**, down from **0.143** on the corresponding PR #20 run. The vehicle retained at least three wheel contacts for every sampled tick. The Alder junction and 16.63 m gravel climb also passed.

## Executed verification

- Godot 4.7.2 root editor import and headless launch passed. The nested standalone project scan warning is expected. Explicit references load the Shell and World Runtime.
- The independent Shell suite passed all 53 assertions. The World Runtime sweep passed 72/72 junction midpoint rays, 642/642 road rays, 216 connector samples, and 196 terrain seam checks.
- Core smoke and steering/camera regressions passed at 30, 60, 83 and 144 simulated render FPS. The standalone prototype is still launchable.
- The real keyboard garage loop passed in headless and in a 1600×900 Forward+ window on Windows. It selected Orion from the menu, drove it, rejected a moving garage entry, switched camera modes, reset, selected Kestrel while parked, resumed in hood view, and switched back to chase. Kestrel had four wheel contacts after replacement. Visual subscribers received each real chassis with its wheel nodes and anchors already present.
- A second Godot process read the selected Kestrel from disk and started the canonical world using its physical preset.
- These tests use keyboard events and scripted on-road inputs. Physical gamepad and high-speed handling for the new vehicle presets remain unverified.

## Captures

- [Garage, Orion selected](screenshots/garage-orion.png)
- [Orion in the world](screenshots/free-roam-orion.png)
- [Garage, parked Kestrel swap](screenshots/garage-kestrel.png)
- [Kestrel hood view after swap](screenshots/hood-kestrel.png)
- [Kestrel chase view after swap](screenshots/chase-kestrel.png)

## Reproduce

```powershell
godot --headless --path . --import --quit
godot --headless --path modules/game_shell --script res://tests/run_tests.gd
godot --headless --path modules/world_runtime --script res://tests/smoke.gd -- --full-world
godot --headless --path . --fixed-fps 60 --script res://tests/integration/vehicle_world.gd
godot --headless --path . --fixed-fps 60 --script res://tests/integration/garage_world.gd
godot --path . --resolution 1600x900 --script res://tests/integration/garage_world.gd -- --capture-dir <existing-folder>
godot --headless --path . --fixed-fps 60 --script res://tests/integration/garage_world.gd -- --verify-profile <printed-profile>
```

Use the `GARAGE PROFILE` path emitted by the first garage run. Tests write to isolated QA profiles. See the [vehicle art handoff](VEHICLE_VISUAL_HANDOFF.md) for the interface and acceptance checks.
