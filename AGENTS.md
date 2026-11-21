# Shared instructions for coding agents (ChatGPT / Codex / Gemini Antigravity)

This repository is the source of truth. Do not rely on old chat messages when a relevant file in GitHub differs.

## Read before editing
1. README.md
2. docs/PROJECT_STATUS.md
3. docs/GAME_DESIGN.md
4. docs/TECHNICAL_ARCHITECTURE.md
5. docs/IMPLEMENTATION_PLAN.md
6. docs/ASSET_LICENSES.md
7. docs/PROJECT_WORKFLOW.md

For first implementation, use prompts/FIRST_EXECUTION_PROMPT.md. Permanent design context: prompts/MASTER_CONTEXT.md.

## Product constraints
Original fictional single-player, open-world racing game, Windows offline. Godot 4.7.2 GDScript/Forward+; candidates Terrain3D 1.1.0, Godot Road Generator 0.9.5, Easy Vehicle Physics pinned to an actual tested SHA. The three plugins have not yet been jointly tested. 2x2 km eventual world, 500x500 m first playable prototype. Simcade driving, 3 fictional cars, AI races and traffic later. Keyboard + Xbox-style controller. Free and explicitly licensed assets only. No multiplayer, no copied Forza assets or unlicensed models.

## Git collaboration policy
- The GitHub repository Anshuman-Arun/driving-game is canonical.
- Before coding, fetch/pull and inspect the current branch and git status. Never assume a separate local checkout is up to date.
- Work in a short-lived branch such as feat/p0-driving or fix/terrain-collision; keep main stable. For changes made via GitHub connector, create a branch and PR for substantive work.
- Do not force-push, reset, delete branches, overwrite user work, or change license/visibility without explicit permission.
- Commit small coherent units with descriptive messages. Don't build in two agents simultaneously on the same branch. Do not claim a commit is on GitHub until push/API confirms it.
- Antigravity uses a local clone; commit AND push changes to share them. ChatGPT can read the remote via the GitHub connection; it cannot see unpushed local changes automatically.
- For ChatGPT cloud tasks/Codex, use the same repository (but a separate branch/worktree) rather than a second game copy.
- A ChatGPT Project is a place for conversations and references; it is not the live local git working directory. Keep authoritative code and docs in this repository.

## Implementation discipline
- First goal is a genuinely drivable 500x500 m prototype, not the full world.
- Test plugin compatibility individually, then together. Keep third-party copyright notices and exact versions/hashes.
- Make the smallest working change. Preserve functional systems; don't generate placeholder managers or rewrite whole add-ons.
- Execute practical Godot import/parser checks when available; report test results honestly. Visual/gamepad/manual tests must be marked unverified when not performed.
- Update docs/PROJECT_STATUS.md with observed progress, blockers, tested commands, and next step. Update docs/DEPENDENCIES.md once dependencies actually land.
- Stop at the assigned milestone. Do not invent screenshots, performance numbers or working executables.

## End-of-session report
Branch; commit/PR URL if published; changed files; actual functionality; tests executed; what remains unverified; known blockers; next small step.
