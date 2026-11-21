# Aster Valley — Driving Game

**Status:** Preproduction / repository initialized. No playable Godot project has been implemented yet.

A compact, original, single-player open-world racing game, inspired by the *feel* of Forza Horizon but not its proprietary map, models or branding.

- **Platform:** Offline Windows desktop; keyboard and Xbox-compatible controller.
- **World:** 2 × 2 km fictional mountain/countryside/town/lake region; 8–12 km road network.
- **Gameplay:** Free roam, three fictional realistic sports cars, civilian traffic, and four races against AI.
- **Visual direction:** Semi-realistic; only free, explicitly licensed assets.
- **Engineering target:** Godot 4.7.2 stable + Terrain3D 1.1.0 + Godot Road Generator 0.9.5 + Easy Vehicle Physics (tested pinned commit). **Integration is not yet verified.**
- **Priorities:** Good handling, functioning gameplay, attractive scenery, incremental playable milestones.

## How to work on this project

**GitHub repository:** https://github.com/Anshuman-Arun/driving-game

The Git repository is the **canonical source of truth** for code, designs, tasks and current status. ChatGPT and Antigravity must read the repository's current version rather than assume a past chat is up to date.

1. Read [AGENTS.md](AGENTS.md) for shared coding-agent instructions.
2. Read [docs/GAME_DESIGN.md](docs/GAME_DESIGN.md), [docs/TECHNICAL_ARCHITECTURE.md](docs/TECHNICAL_ARCHITECTURE.md), [docs/IMPLEMENTATION_PLAN.md](docs/IMPLEMENTATION_PLAN.md) and [docs/ASSET_LICENSES.md](docs/ASSET_LICENSES.md).
3. See [docs/PROJECT_WORKFLOW.md](docs/PROJECT_WORKFLOW.md) to use ChatGPT, Codex and Antigravity with the same GitHub repository.
4. See [docs/GITHUB_SETUP.md](docs/GITHUB_SETUP.md) for Windows clone/install instructions.
5. For the first agent run, use [prompts/FIRST_EXECUTION_PROMPT.md](prompts/FIRST_EXECUTION_PROMPT.md). Do not build the full game in the first run.

## Development status

- [x] Design direction and roadmap established
- [x] GitHub repository initialized and documents installed
- [ ] Godot version and three plugins validated together
- [ ] First drivable 500 × 500 m prototype (P0–P1)
- [ ] World technology / art proof (P2)
- [ ] Complete open world (P3)
- [ ] Game shell / garage (P4)
- [ ] Civilian traffic (P5)
- [ ] Racing AI and events (P6)
- [ ] Audio, polish and Windows build (P7)

See [docs/PROJECT_STATUS.md](docs/PROJECT_STATUS.md) for verified work and blockers.

**Please do not upload duplicate documents to the GitHub root, or commit generated `.godot/` caches.**
