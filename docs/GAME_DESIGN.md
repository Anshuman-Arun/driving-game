# Aster Valley — Game Design Document v1.0

Date: 2026-11-21. Working game name: **Horizon Racer**. Setting: **Aster Valley**, a fictional temperate mountainous lakeside region with a compact town, forests, farmland and a ridge route. A hybrid fictional geography, not a copy of any existing racing-game map.

## Player fantasy
Step into a beautiful, compact open world, choose a believable fictional sports car, cruise in any direction, discover a roadside race, compete against competent AI, and return to exploring. The game must feel responsive with keyboard or gamepad and run **entirely offline** as a Windows desktop build.

## Experience pillars, in order
1. **Driving feel:** stable, fun simcade handling, speed sensation, controllable slides, predictable recovery.
2. **Scenic density:** distinct terrain silhouettes and route character within 2 × 2 km rather than an empty procedural expanse.
3. **Seamless free roam to racing:** race markers and events on roads; no jarring context switches.
4. **Competent simple systems:** believable traffic, checkpoint logic, readable HUD, consistent input, saving.
5. **Reliable performance and workflows:** no dependency on internet; readable project structure and reproducible builds.

## World coordinates and roads
- Playable world **2,000 × 2,000 m**; a meter in content design corresponds to 1 Godot unit.
- Coordinate convention: **x increases east, z increases south**, y is height; north is negative z in Godot view. Map coordinates are in [0, 2000] × [0, 2000].
- Map border is naturalized using forest, steep mountains, water, and blocked trails. Distant decorative mountain silhouettes can lie beyond playable borders but need no collision.
- World section plan:

| Region | Anchor (x,z) | Height design | Driving character |
|---|---:|---|---|
| Alder Town and garage | (380, 1570) | 20–45 m | tight street bends, 2–3 intersections, civic square |
| Cedar Woods | (330, 650) | 65–135 m | enclosed winding asphalt, shaded bends |
| North Ridge | (1250, 350) | 170–300 m | switchbacks, crest, overlook, hill-climb sprint |
| Green Valley | (1030, 1120) | 45–85 m | fast, flowing connector and fields |
| Eastwater Lake | (1690, 1430) | 20–35 m | waterside road, gravel layby, scenery |

- **8–12 km road centerlines** total, approximately 65–80% asphalt, remainder short gravel tracks/optional connectors. Roads usually have two lanes ~3.2–3.5 m each, center line, shoulders and guardrails at dangerous drops. Final values should be adjusted after hands-on test.
- A main touring loop connects Alder Town → Cedar Woods → North Ridge → Green Valley → Eastwater Lake → Alder Town. A central connector and short town/forest routes permit alternate race layouts. A beautiful ridge descent is a signature road.
- Road pieces should have named IDs, explicit lane direction metadata, event waypoint graphs and pedestrian-free intersections. Avoid procedural intersections that cannot be reliably traversed by AI.
- Terrain and roads: terrain is authorable with Terrain3D; roads via Godot Road Generator; terrain connector cuts/grades the shoulder. Keep scene data in source control; do **not** rely on live procedural generation at runtime for the complete map.

### First 500×500 m prototype (independent of final coordinates)
A manageable flat-to-rolling hill; a paved S-bend of roughly 600–900 m across the small region, a short open flat for acceleration, one hairpin, solid road collision, simple terrain materials and a safe respawn point. No full town or lake, no 2×2 km data yet. This validates terrain/road/vehicle interaction.

## Cars
Final content budget **3 drivable fictional sports cars**, distinct handling rather than only visual skins:
1. **Vela GT** — balanced rear-wheel-drive coupe, starting car, approachable.
2. **Orion RS** — light and nimble, slower straight-line speed, best in switchbacks.
3. **Kestrel XR** — high-powered, tougher traction management, unlocked later.

**All cars are fictional.** Do not reproduce trademark badges or borrowed interiors. Free/CC0 generic base meshes can be modified into a coherent fictional family. Initial prototype may use a primitive chassis or licensed placeholder. Rigging must include wheel pivots and accurate collider dimensions.

## Handling specification
- **Simcade**, not hardcore vehicle simulation; grounded suspension and tire response but with optional stability assists and forgiving behavior.
- Start with Easy Vehicle Physics `demo_simcade` characteristics; do not replace its controller with a hand-coded pseudo-physics system without evidence.
- Tunable response parameters: mass, center of mass, grip, longitudinal/lateral force, brake torque, max steering angle vs. speed, handbrake traction, suspension, assists, engine/gearing. Store per-car data in Godot Resources or data files, not hard-coded branches.
- Keyboard steering ramps in/out over time to avoid binary twitching; controller steering remains analog and has an adjustable deadzone. Throttle and brake gamepad triggers are analog.
- Ground contact, curb contact, slopes and recover/reset behavior must be tested. Vehicle must not sink through roads, launch on seams, or get stuck if it can be recovered.
- Audio, camera lag, speed-dependent FOV and optional mild camera shake should reinforce speed without obscuring the view.
- No mandatory nitro, weapons, drift scoring, destruction, or gear shifting in v1.

## Controls (initial default bindings)
| Action | Keyboard | Xbox-style gamepad |
|---|---|---|
| Accelerate | W / Up | Right trigger |
| Brake/reverse | S / Down | Left trigger |
| Steer | A,D / Left,Right | Left stick horizontal |
| Handbrake | Space | B |
| Reset car | R (hold or press with short cooldown) | Y (hold) |
| Change camera | C | Right stick click |
| Look around | Mouse / optional numpad | Right stick |
| Interact/start race | E | A |
| Map | M | View/Back |
| Pause | Esc | Menu/Start |

Implement the Godot input action map centrally; allow rebound later. Input must gracefully ignore missing controllers and handle controller plug/unplug at runtime. Keyboard and gamepad should both access menus.

## Cameras and UI
- Chase camera default with spring smoothing and wall-avoidance camera collision; alternate close chase camera and hood camera later.
- HUD: speed (km/h), gear/drive state, small minimap, race countdown and checkpoint indicator; show assists/settings in pause screen.
- Map: static stylized 2D road overlay with player marker and race event markers. Avoid promising a full GPS solution in v1.
- Garage: 3 car slots, car switching while parked, simple color variants, no deep tuning interface initially.

## AI and races
- Four launch events (initial targets, revise after roads exist):
  1. **Alder Street Circuit** — short town loop, ~1.5 km per lap, 3 laps.
  2. **North Ridge Climb** — ~2.3 km point-to-point sprint.
  3. **Eastwater Dash** — ~2.0 km fast scenic sprint.
  4. **Aster Tour** — ~4.0 km mixed-surface circuit, 1–2 laps.
- Each event defines start line, ordered checkpoints, lap count, AI spawn positions, racing-line waypoint path, difficulty target and finish trigger. Exact course lengths require mapping and verification.
- **3–5 AI racers** per event if physics/render budget permits; difficulty is driven primarily by speed target, steering lookahead and recovery behavior rather than impossible speed boosts.
- Traffic: target **10–20 active nearby civilian vehicles** at high preset, fewer at low; lane following, speed variation, collision avoidance, yielding at basic intersections, distance-based spawn and despawn. No persistent simulation of the full world outside the player's vicinity. Never spawn traffic atop the player or inside a race grid.
- Race state machine: `IDLE → GRID → COUNTDOWN → RACING → FINISHED → RESULTS → FREE_ROAM`, with `ABORTED` exit. Checkpoints reject shortcuts, handle wrong-way and pause, and cannot be advanced through arbitrary wall jumps.

## Progression and persistence
- Launch with Vela GT. Award currency or reputation after events, use it to unlock second and third vehicles. Keep balances small and progression deterministic.
- Autosave completed events, best times, selected car, options and unlocks to a versioned JSON file under `user://`. Handle missing/corrupt files without crashing. No internet, storefront, accounts, cloud sync, or telemetry.

## Visual direction and audio
- Semi-realistic temperate mountain area: warm late-afternoon sun, neutral-toned asphalt, detailed rocks and pine trees, landmark overlook and lake reflections. Not photorealism promises.
- Godot Forward+; PBR terrain/road materials; fog sparingly; water should be a low-cost stylized reflective plane first.
- Trees/rocks use instancing, appropriate LOD and culling; no imported million-triangle showcase model as default gameplay car.
- Audio layers: engine RPM/pitch, tire squeal, impacts, wind, UI. Use properly licensed material or synthesis. No copied soundtrack, brand design, or ripped commercial game assets.

## Quality targets (initial planning targets, not measurements)
- Baseline: ~60 FPS at 1920×1080 on a midrange Windows laptop GPU at a deliberately optimized preset; provide low/medium/high scaling. Measure later; do not claim met without benchmark.
- Consistent physics at a fixed tick rate, default 60 Hz unless testing demands change.
- Initial play session should allow player to launch, drive and start an event without opening the Godot editor.
- Offline operation; functioning keyboard and gamepad; Windows export.

## Explicit exclusions from V1
Online multiplayer, split-screen, licensed real-brand vehicles, photorealistic 4K, pedestrians, destructible environment, in-depth tuning/engine swap, seasons, huge map streaming, police, weather simulation, on-foot mode, traffic law simulation, complex economy, extensive car roster.