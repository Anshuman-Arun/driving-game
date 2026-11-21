# Aster Valley — Technical Architecture v1.0

## Platform baseline
- Godot **4.7.2 stable**, standard GDScript build, **Forward+**, Windows x64. Do not upgrade to 4.8 beta automatically.
- **Terrain3D v1.1.0 stable** (released 2026-10-30): documented support includes Godot 4.7.
- **Godot Road Generator v0.9.5** (released 2026-10-13): documented for 4.4+, with Terrain3D connector work. Import from **official release artifact**; preserve LICENSE.
- **DAShoe1/Godot-Easy-Vehicle-Physics**: documented for Godot 4.2+, MIT, demo_simcade available. Choose a tested commit SHA and store it in `docs/DEPENDENCIES.md`; do not treat upstream `main` as a pinned release.
- IMPORTANT: This exact combination has **not yet been tested together**. First task is a small integration spike. If incompatibility is found, isolate it and document reproducible evidence; do not silently switch engines or rewrite all vehicle physics.

### Dependency validation sequence
1. Clean Godot 4.7.2 project opens with console output and no parsing errors.
2. Import Terrain3D **1.1.0 release files only**, test a sample terrain scene and Windows GDExtension binary loading.
3. Import Road Generator **0.9.5 release files only**; create a road mesh, verify collision and lane metadata.
4. Connect `Terrain3D`, `RoadManager`, and `RoadTerrain3DConnector` per official wiki. Test terrain grading and restore/reopen persistence.
5. Import Easy Vehicle Physics `addons/gevp` and relevant licensed demonstration content; instantiate simcade example on a simple collision plane, then road. Test pause, wheel rays, friction and reset.
6. Reopen from a fresh import (after deleting only `.godot/` cache), run a headless editor parse check; investigate log warnings.

Terrain3D connector reference: https://github.com/TheDuckCow/godot-road-generator/wiki/Using-the-Terrain3D-Connector
Terrain3D installation: https://github.com/TokisanGames/Terrain3D/blob/main/doc/docs/installation.md

## System ownership and dependencies
```text
App/SessionManager (autoload; minimal session state)
  ├── InputRouter (keyboard/gamepad normalized analog actions)
  ├── WorldRoot
  │   ├── Terrain3D instance + authored terrain data
  │   ├── RoadManager + RoadTerrain3DConnector + lane/path data
  │   ├── Environment (sky/light/atmosphere)
  │   ├── PlayerSpawn + PlayerVehicle
  │   │   ├── VehicleAdapter wrapping Easy Vehicle Physics
  │   │   └── ChaseCamera rig
  │   ├── TrafficManager -> pooled TrafficVehicle agents (later)
  │   └── RaceEventManager -> race zones and AI racers (later)
  ├── UI (HUD, pause, garage, world map, race results)
  └── SaveService (user:// versioned JSON; later)
```

Do not build all managers and empty abstractions in phase 1; create only those essential to the playable test, and document intended APIs as future interfaces.

## Proposed Godot project organization
```text
project.godot
addons/terrain_3d/           # vendor official release; preserve copyright
addons/road-generator/       # vendor official release; preserve copyright
addons/gevp/                 # vendor tested upstream SHA; preserve copyright
scenes/bootstrap/main.tscn
scenes/prototypes/driving_test.tscn
scenes/world/aster_valley.tscn
scenes/vehicles/player_car.tscn
scenes/ui/hud.tscn
scenes/ui/pause_menu.tscn
scripts/core/input_router.gd
scripts/vehicles/vehicle_adapter.gd
scripts/vehicles/chase_camera.gd
scripts/world/traffic_manager.gd
scripts/world/traffic_vehicle.gd
scripts/racing/race_event.gd
scripts/racing/racer_ai.gd
scripts/save/save_service.gd
resources/cars/*.tres
resources/races/*.tres
assets/models/ assets/materials/ assets/audio/
world_data/terrain/ world_data/roads/
tests/
docs/
prompts/
```
*The above is aspirational organization; don't create all folders/files as empty placeholders in the first agent pass.*

## Contract interfaces to prefer

### InputRouter
A single place converts `InputMap` actions into neutral `steer∈[-1,1]`, `throttle∈[0,1]`, `brake∈[0,1]`, `handbrake∈{false,true}`, plus one-shot camera/reset/pause inputs. GDScript constants, actual action names and mappings live together. Analog triggers must not cancel one another unexpectedly. Keyboard steering interpolation belongs here (or one documented vehicle adapter), not scattered among UI and camera scripts.

### VehicleAdapter
The rest of the game calls `set_drive_input(steer, throttle, brake, handbrake)`, `get_speed_mps()`, `get_forward_speed_mps()`, `get_gear_display()`, `reset_to(transform)` and reads `vehicle_moved`/`vehicle_crashed` events if necessary. Adapter encapsulates GEVP-specific fields, so car models, racing AI and HUD do not reach directly into third-party internals. Expose baseline handling configuration in resources once tuning begins.

### RoadNetwork
Use Road Generator to author road centerlines, intersections and lane geometry. Create an export/preprocessing step that exposes directed graph edges for AI. Each edge has `lane_id`, sampled centerline positions, direction, speed limit and adjacency. Geometry is authoritative; do not separately hand-draw a disconnected map and traffic graph.

### TrafficManager (later)
Simple finite-state controllers: `FOLLOW_LANE`, `BRAKE_FOR_OBSTACLE`, `WAIT_AT_JUNCTION`, `RESPAWN`. Pool vehicles near player; suspend distant agents. Use the RoadNetwork graph rather than free-form navmesh pathfinding. AI traffic can use a simplified kinematic controller away from the player; physics bodies/collision only when nearby. Traffic must not simulate beyond the populated region.

### Racing AI (later)
Prefer the same vehicle physics through an adapter, with path tracking (pure pursuit/Stanley-type steering), curvature-aware target speed, lookahead based on speed, fallback for road blockages, and recoveries after prolonged immobilization. Route and waypoint timing must be reproducible. Any simplified AI model must maintain credible collisions with the player.

### RaceEventManager (later)
Data-driven `RaceDefinition` resources include `event_id`, race type, path/lane references, checkpoints, finish, player start, opponent starts, laps, rewards and allowed vehicles. Race event flow is a state machine with ordered checkpoint sequence, laps, disqualification of missed checkpoints, abort path and results.

### SaveService (later)
Read/write versioned `user://save_v1.json`. Include schema version, vehicle selection, race records, unlocks, options; use defaults when missing and backup or reject invalid corrupt data. Do not require remote auth.

## Scene asset policy and license handling
- Third-party add-ons go in `addons/` with original LICENSE/NOTICE kept. Record upstream URL, **exact SHA/tag**, license, inclusion scope and date in `docs/DEPENDENCIES.md`.
- Textures/models go in `assets/`; every external source has a ledger row in `docs/ASSET_LICENSES.md` and a retained license link or file. Copy only actual needed assets, never indiscriminately rehost entire third-party demos.
- PBR materials: Poly Haven or ambientCG CC0. Starter cars/props: Kenney CC0. Candidate sports car: Spectral GT RS CC0 with mesh/rig/performance validation.
- Avoid car-brand logos and data extracted from commercial games. Avoid assets without a license or with unclear derivative rights.

## Performance architecture
- Initial prototype: no elaborate streaming framework; test framerate before introducing chunking.
- Full world: terrain LOD through Terrain3D, foliage instancing, `MultiMeshInstance3D` as appropriate, frustum/distance culling, near/far traffic budget, reduced far-away physics, shadow distance quality presets. Roads must maintain colliders near playable routes.
- Scope limit: gameplay on 2×2 km; visual-only skybox/backdrop beyond it. Do not generate high-fidelity geometry that the player cannot reach.
- Benchmark separately with 0, 5, 10, 20 traffic units, three graphics presets, low vs high foliage density, town vs ridge vs shoreline. Save actual FPS and GPU/CPU observations; don't label targets as measured.

## CI and tests
- `godot --headless --path . --editor --quit` for import/parse sanity (first import can take longer); check nonzero status and logs.
- Lightweight GDScript smoke test optional for each incremental feature; no overengineered test architecture.
- Manual playtest matrix: keyboard only, gamepad only, controller unplugged, road seam, off-road, pause/resume, reset after rollover, restart from disk.
- Before Windows export: install Godot export templates matching 4.7.2; export Windows Desktop, run executable without editor, verify save and controller.

## Main technical risks and mitigation
| Risk | Evidence gate | Fallback |
|---|---|---|
| Terrain3D GDExtension won't load | official demo on user's Windows build | confirm matched plugin binaries; stop before copying unknown nightly |
| Road/terrain connector distorts grade | 3 curves, slopes, road collisions tested | author road manually and grade terrain by hand in limited prototype |
| GEVP demo incompatible at 4.7.2 | run `demo_simcade` on collision plane | minimally patch adapter or test approved alternative; report not silently swap |
| Too much asset memory | baseline GPU measurements with content | lower texture resolution, LOD, MultiMesh and presets |
| Traffic CPU too high | scaling 0/5/10/20 agents | pooled simplified distant agents, density preset |
| Generated code sprawls | small functional milestones and concise docs | remove scaffolding, use composition and bounded interfaces |