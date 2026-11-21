# Track A — Core Godot project + first drivable vehicle

You are the lead Godot engineer, operating in **Anshuman-Arun/driving-game**. This is a real implementation task, not a planning assignment. Work through as much of the assignment as the actual tool/runtime budget allows, not merely a skeleton.

## Exclusive ownership / isolation
- Branch: `feat/core-driving`, from the most recent `main`; create a separate checkout/worktree if other tasks are running. If that branch already exists, inspect before changing.
- You may write only: `project.godot`, `addons/`, `scenes/`, `scripts/vehicle/`, `tests/core/`, `docs/DEPENDENCIES.md`.
- Do **not** edit root README, AGENTS.md, any other docs, assets/curated, worldgen, data/world, modules/racing or modules/traffic. Write necessary integration notes to `tests/core/INTEGRATION_NOTES.md`.
- Do not merge into main. Do not assume other parallel branches are present locally or merged.
- Read `AGENTS.md`, `docs/GAME_DESIGN.md`, `docs/TECHNICAL_ARCHITECTURE.md`, `docs/PARALLEL_EXECUTION.md`, `docs/INTERFACES_V1.md` and `prompts/FIRST_EXECUTION_PROMPT.md`. Your ownership restriction overrides any generic instruction to update shared status docs.

## Deliverable
Create a **genuinely playable standalone Godot 4.7.2 project** and a 500×500 m driving test environment, not a full open world. A keyboard-controlled fictional sports car should be fun and stable to drive with a functional chase camera. The project must also contain proper Xbox-style controller mappings even if hardware testing isn't possible.

### Engineering work
1. Check installed Godot/runtime, fetch pinned compatible upstream releases of Terrain3D 1.1.0, Godot Road Generator 0.9.5 and Easy Vehicle Physics. Preserve original licenses. Fix integration minimally rather than rewriting a large third-party plugin. Record source, hashes, GDExtension platform dependencies and commands in `docs/DEPENDENCIES.md`.
2. Initialize `project.godot` for Forward+, use a clear main scene. Build a collidable drivable test area with varied elevation, an acceleration straight, sweeping S-curves, a tight hairpin, road markings, barriers and attractive but light placeholder scenery. Test actual road/terrain collision and road-to-grass transitions.
3. Integrate the real physics controller with stable mass, suspension, tire grip, damping, braking and handbrake; tune one fictional coupe for fun simcade handling. Use physically separate visual wheels when the controller requires it; don't confuse wheel mesh with physics logic.
4. Chase camera: smooth position/rotation, steering look-ahead, FOV response to speed, collision avoidance, and optional camera switching. Keep camera motion stable over uneven terrain.
5. Keyboard: W/S, A/D, arrows, Space, C, R, Escape. Xbox controller: triggers, left stick, B, Y, Menu. Keep analog inputs analog; smooth keyboard steering. Working pause, reset upright and on-road, HUD speed in km/h.
6. Prefer clear, small functional GDScript components, minimal external dependencies and settings with documented tuning values. Do not add AI racing, town, full 2×2 km map, garage or traffic in this branch.

### Mandatory testing/evidence
- Run Godot's editor import/parser/headless check using the actual installed executable; save command and output under `tests/core/`.
- Launch/play the prototype if GUI/interactive execution is possible, record behavior and bugs with reproducible steps.
- Verify basic physics behavior: forward movement, braking, turning, collisions and reset. Document how you tested each, and mark controller, visual quality and driving *feel* unverified if no real device/display.
- Run again after final edits, and validate opening a fresh clone if feasible.
- If a plugin is incompatible with Godot 4.7.2, gather error logs, attempt a minimal safe fix and preserve the best runnable fallback rather than inventing a passing result.

### Acceptance
- Actual Godot project opens and runs the default drivable scene.
- Road and terrain have working collision; car and HUD visible.
- Player can accelerate, turn, brake, handbrake and reset.
- Chase camera, pause and keyboard/gamepad actions are wired.
- Add-on versions/licenses are recorded.
- Tests include actual results; remaining manual tests are plainly named.

### Working policy
Continue implementing, debugging, testing, tuning and documenting until the assigned deliverable is genuinely complete **or** an actual blocker or available tool/context quota stops you. Do not stop after a plan, partial scaffolding or one passing parser check. Do not ask routine intermediate confirmation. Do not promise background work. If close to the tool limit, save/commit a coherent partial state and state exactly what remains.

### Git end state
Commit to `feat/core-driving`, push to origin, open a PR titled `P0–P1: Godot driving vertical slice` if tools permit, but **do not merge**. Report link, SHA, files, actual tests, untested items, plugin issues and steps to launch. If push or PR creation is unavailable, state that and provide the local branch/commit rather than claiming remote delivery.
