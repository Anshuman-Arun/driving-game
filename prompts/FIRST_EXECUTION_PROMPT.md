# First Antigravity execution prompt — Phase 0 and playable Phase 1

You are working in the repository opened as this Antigravity workspace. Read **in full** before coding:
- `README.md`
- `docs/GAME_DESIGN.md`
- `docs/TECHNICAL_ARCHITECTURE.md`
- `docs/IMPLEMENTATION_PLAN.md`
- `docs/ASSET_LICENSES.md`
- `prompts/MASTER_CONTEXT.md`

## OBJECTIVE
Implement the **smallest convincing playable 3D driving slice** of our game using **Godot 4.7.2 stable**. Do **not** try to build the final 2×2 km world or implement race AI, traffic AI, garage, multiplayer, realistic damage, an economy, or cinematic menus.

Work autonomously on local implementation, use Git responsibly, and complete what can be actually executed and tested. If there is a blocker you cannot resolve with a small change, preserve a functional minimal scene, document the exact reason, and do **not** fake a finished integration.

## TASK A — verify the environment and dependencies
1. Inspect the workspace and detect any existing files/project; preserve them. Determine whether Git is initialized and whether Godot 4.7.2 is installed. If missing, explain the exact prerequisite rather than silently swapping engine versions. Do not force-install system software without authorization.
2. Create a clean Godot **4.7.2/GDScript/Forward+** project if absent, with `main.tscn` and a clearly named test scene. Keep standard Godot project hygiene, notably ignoring `.godot/` imported cache in Git.
3. Acquire only necessary, documented plugin files from **official sources**: Terrain3D **v1.1.0 stable**, Godot Road Generator **v0.9.5**, and Godot Easy Vehicle Physics from a specific pinned SHA. Prefer official release files and plugin folders; keep upstream copyright and LICENSE notices. Do not copy demo assets unless individually licensed. Record URL, tag/SHA, file scope and observed compatibility in `docs/DEPENDENCIES.md`.
4. Validate each plugin alone before combining. Terrain3D must load its Windows native extension if available; Road Generator must instantiate a drivable collidable curved road; the terrain connector should grade/align terrain appropriately. Inspect official connector instructions rather than inventing node names or method signatures.
5. Instantiate the Easy Vehicle Physics `demo_simcade` setup (or a direct equivalent using its own physics controller), first on a collision plane, then on the generated road. Record actual console errors/warnings and fixes. **Do not rewrite vehicle physics from scratch.**

## TASK B — make the playable test scene
Build a practical **500 m × 500 m** graybox/early-art valley prototype:
- Rolling terrain via Terrain3D where functioning, in two material regions (grass/dirt/rock as permitted or simple procedural fallback).
- One smoothly graded asphalt S-bend/mini-loop with an acceleration straight and at least one tight corner; visible shoulder/edge and collision.
- One fictional rear-wheel-drive sport coupe **placeholder** (a simple original mesh/primitive is fine) with a workable center of mass, wheel visuals, raycast suspension, collision and tuned simcade handling.
- Third-person chase camera with speed-sensitive follow smoothing; camera never tunnels through ground in ordinary driving and reset.
- HUD showing **km/h** speed, optional gear, and short keyboard/gamepad control legend.
- Actual **WASD / arrows and Xbox-compatible controller** driving input. Use analog stick and triggers with deadzones, and keyboard steering smoothing. Controls: W/Up gas, S/Down brake, A/D steer, Space handbrake, R reset, C camera, Esc pause; Xbox RT throttle, LT brake, left stick steer, B handbrake, Y reset, Menu pause. Keep input centralized, not duplicated across scattered scripts.
- Working reset-to-road behavior (upright, zero unhealthy velocity) with appropriate cooldown and pause/resume.
- Basic direction/lighting and plausible material colors; this phase should look tidy, but **driving quality and stability outrank cosmetic complexity**.

## TASK C — prove the scene works
1. Execute the available Godot editor/import/parse check, e.g. `godot --headless --path . --editor --quit`, with correct local executable if needed; capture exit status and critical errors.
2. Launch the scene in-engine if graphical testing is available. Check accelerator, steering, braking, road collision, terrain collision, camera, rollover recovery and pause. Test a connected gamepad if one is accessible. If not, mark that verification as **manual / not performed**; never claim it passed.
3. Reopen project after initial import; ensure add-on paths and generated resources survive restart. Confirm that no plugin demo content relies on missing external files.
4. Avoid lengthy QA infrastructure. If an addon fails to cooperate, stop modifying it when complexity grows; document exact error and a minimal fallback with a runnable scene. Do not report plugin integration as done when using only an unconnected placeholder plane.

## ACCEPTANCE CRITERIA (all verified or explicitly marked pending)
- [ ] Standard Godot **4.7.2** project opens/imports without blocking errors.
- [ ] `F5` launches a 3D scene with a spawnable drivable car and visible terrain/road.
- [ ] One coherent **simcade** controller, not a fake scripted translation/move-and-slide vehicle; suspension/traction physics are genuinely used.
- [ ] Keyboard accelerates, brakes, turns, handbrakes and resets; camera tracks vehicle smoothly.
- [ ] Xbox-style controller action mappings exist; actual hardware test reported as done or pending.
- [ ] Road and terrain have collision; vehicle can traverse the asphalt-to-terrain boundary without immediately falling through.
- [ ] A speedometer displays vehicle speed converted from m/s to km/h.
- [ ] Game can pause and resume; reset handles a rolled-over or immobilized car.
- [ ] Original or explicitly free/licensed assets only; exact third-party tags/commit IDs and notices retained.
- [ ] Git diff is focused, no giant generated/binary cache committed; documentation records exact run instructions.
- [ ] Any unverified visual, controller, performance or physics-feel criteria are clearly labeled unverified.

## IMPLEMENTATION PRIORITIES
Priority order: (1) stable actual car physics; (2) drivable solid road / terrain; (3) dual input; (4) camera / reset; (5) speed HUD; (6) minimal visuals. If time/tools prevent an item, keep the earlier functional items intact. **Do not proceed to the full 2×2 km map or racing systems.**

## END-OF-TASK REPORT
Deliver the repo changes and conclude with:
1. Summary of what is actually playable and how to launch (`F5` scene, Windows executable if genuinely exported).
2. Exact dependency URLs, versions and pinned commit SHA.
3. A short list of files changed.
4. Tests/commands actually executed with observed results; manual testing done vs pending.
5. Known issues and acceptance boxes that remain unchecked.
6. Last Git commit hash / branch, if committed, plus the next recommended implementation step.

If this workspace has no repository yet and remote creation requires authentication, finish the local repository and give precise GitHub commands. Never invent a remote URL or claim a push succeeded without checking.