# Aster Valley — permanent context for coding agents

You are working in **Anshuman-Arun/driving-game**, an original, small but polished, single-player open-world racing game. Read AGENTS.md, README.md, docs/PROJECT_STATUS.md and all relevant docs/ before coding. This GitHub repository, not any old chat or project-file copy, is the source of truth. Antigravity uses a local clone; push commits to share with ChatGPT.

## Experience
An offline Windows game inspired by the open-world enjoyment of Forza Horizon without copying its map, branding or assets. Fictional Aster Valley is a 2×2 km region combining a small town, mountain switchbacks, wooded roads, an open valley and lakeside scenery, with 8–12 km total roads. Semi-realistic style, fictional realistic sports cars, simcade driving, keyboard + Xbox-compatible gamepad, civilian traffic, 3–5 AI racers and four eventual race events. Only free, explicitly licensed art. Aim for good performance, targeting 60 FPS at 1080p on an optimized preset, but never claim measured FPS without testing.

## Technical baseline
Godot 4.7.2 stable standard build, GDScript, Forward+. Candidate add-ons: Terrain3D 1.1.0, Godot Road Generator 0.9.5 and DAShoe1/Godot-Easy-Vehicle-Physics at a verified pinned commit. **Their joint compatibility has not yet been proven.** Validate each plugin before integration; keep exact source URLs, commit/tag references and licenses.

## Work rules
1. Before editing, pull/inspect the current branch and docs/PROJECT_STATUS.md. Create a focused feature branch.
2. Phase P0/P1 first: genuinely playable 500×500 m drivable sports car prototype. Do not generate the full world, AI, traffic, weather or garage in this pass.
3. Driving and road/terrain collision come first. Preserve functioning code; do not rewrite third-party physics when small integration changes suffice.
4. Use real engine input actions, true suspension/traction, smooth chase camera and km/h HUD. Keyboard steering interpolation and analog gamepad input should share one mapping.
5. Keep implementation lean. Do not generate empty managers, vague scaffolding or hundreds of unrelated files.
6. Use only original/free legally reusable content; retain license notices and asset ledger. Never commit secrets.
7. Actually run any checks you claim to have run; report missing hardware/manual test coverage truthfully.
8. Document dependency versions and update docs/PROJECT_STATUS.md; commit and push to the task branch, propose a PR to main if appropriate.

## End-of-task report
What is playable, exact run instructions, files touched, actual test evidence, pending checks, blockages, branch/commit/PR URL, next milestone. Stop after the assigned phase.
