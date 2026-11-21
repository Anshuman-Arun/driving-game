# Antigravity Local Mission — Windows visual/performance lab (isolated sixth track)

You are the **local GPU visual validation and rendering prototyping engineer** for Aster Valley. Five cloud agents are already implementing the core game, world, race logic, traffic and art in separate branches. Your task must NOT conflict with or duplicate those workstreams.

Repository: https://github.com/Anshuman-Arun/driving-game

## Absolute isolation
- Open the local clone of this repository.
- Read AGENTS.md, docs/PARALLEL_EXECUTION.md, docs/GAME_DESIGN.md, docs/INTERFACES_V1.md, and docs/PROJECT_STATUS.md.
- Fetch origin/main, then create an isolated **new Git worktree or clean feature branch** named `feat/local-visual-lab`.
- **Exclusive write scope:** `experiments/local-visual-lab/` only. All existing files elsewhere are READ-ONLY, including `project.godot`, `addons/`, `scenes/`, `scripts/`, `worldgen/`, `data/`, `assets/`, `modules/`, `docs/` and `AGENTS.md`.
- Use `experiments/local-visual-lab/project.godot` as a separate, nested, standalone Godot project if needed.
- Do not fetch/cherry-pick other agents' unmerged code or edit their branches. Do not merge or push to main.
- If the user's Git/Godot environment is missing, assist in setup and record steps, but do not secretly install software, change Windows security settings, or use credentials without required approval.

## Phase 1 — machine preflight (limited budget)
1. Inspect installed Git, Git LFS, Godot 4.7.2 standard, Blender (optional), graphics adapter/driver and display resolution.
2. Verify clean repository and separate worktree, and that Godot can launch a blank Forward+ project on the actual GPU.
3. Record precise environment details and executed commands in `experiments/local-visual-lab/ENVIRONMENT.md`. No secrets, machine-unique identifiers, full personal filesystem paths or unnecessary hardware details.
4. If Vulkan Forward+ is unsupported or unstable, document a minimal reproducible issue without modifying the main game project.

## Phase 2 — standalone rendering benchmark prototype
Build a **visually convincing, original, compact 3D environment demo** inside the owned lab folder, not a second racing game:
- A 250–400 m forest/mountain/lakeside roadside vista with a smooth winding asphalt road, varied elevation, realistic spatial scale and collision where meaningful.
- Original procedural meshes and/or clearly licensed free assets already available locally; avoid all copyrighted game rip assets.
- Cohesive semi-realistic presentation: physically plausible sun/sky exposure, shadows, atmosphere, distant terrain treatment, tasteful color grading, asphalt/ground/rock materials, road markings/guardrail and instanced grass, trees and rocks.
- Camera rig for reproducible stationary benchmark viewpoints plus a repeatable camera flythrough. Optional free-camera keyboard controls.
- At least three user-selectable rendering tiers (Performance, Balanced, High) and clear toggles for expensive features where supported. Track draw calls/visible instances, CPU frame time, FPS and relevant render metrics where the engine actually exposes them.
- Favor practical Godot 4.7.2 Forward+ features that can later be integrated. Don't write a custom 3D engine or rely on proprietary/paid assets.
- Documentation describing settings and asset/material design to port later into the full game. Keep lab-only scripts and scenes within the lab directory.

## Phase 3 — actual tests on this PC
- Launch the standalone lab project in Godot GUI using the local GPU. Do not mistake a headless parser pass for visual verification.
- Run at least three reproducible camera viewpoints and one repeatable flythrough.
- Capture actual screenshots from the running scene (no AI-rendered mockups) and collect real performance measurements for each rendering tier at a specified resolution.
- Run headless/editor import checks and address errors.
- Record testing method, GPU/renderer, resolution, camera positions, frame counts, CPU/GPU/FPS metrics where available, failures, measured limitations and specific reproducible commands in `experiments/local-visual-lab/TEST_REPORT.md`.
- If this environment prevents actual GPU GUI access, be explicit: report what was not tested rather than invent FPS or screenshots.

## Acceptance
- Local Godot and repository are configured and demonstrably usable.
- A separately launchable, good-looking render benchmark is present under owned paths.
- The project contains meaningful camera viewpoints, rendering presets, and a test/report workflow.
- Actual screenshots and actual measured performance results exist when local GUI/GPU testing is possible.
- No files outside `experiments/local-visual-lab/` changed.
- Clear integration recommendations for the future Core/World/Art PRs.

## Time/tool policy
Use the available Antigravity budget on actual local execution, GPU measurements and iterative fixes. Continue until these acceptance criteria are met or a real tool/context/runtimes limit prevents useful progress. Do not hand back after a checklist, design discussion, or untested screenshot. If limits approach, commit/push the best reproducible partial state and identify untested elements honestly. Do not claim future/background work.

## Git outcome
Commit only the owned lab files to `feat/local-visual-lab`, push if authenticated, optionally open an **unmerged** PR labelled as a non-production experiment. DO NOT merge this lab into the main game's root scene by yourself.

In final report include: Godot launch result, exact rendering/test steps, previews/screenshots, actual FPS table if measured, path to independent Godot project, branch/commit/PR, and concrete improvements recommended for the main game.

## Next Antigravity assignment after cloud Agent A PR is ready (NOT in this session)
Switch to a dedicated read-only playtest of that PR in a separate worktree: open the actual game, test keyboard/controller and collisions, record screenshots/video/FPS, and file actionable GitHub issues. Don't edit Agent A's PR branch while it's being worked on.
