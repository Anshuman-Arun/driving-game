# Parallel execution — five independent implementation branches

This document defines task ownership, not a replacement for AGENTS.md. Start five separate Codex/ChatGPT Work tasks or Antigravity worktrees with the same canonical GitHub repo: https://github.com/Anshuman-Arun/driving-game

**Every agent branches from the current main, never from another agent's unfinished branch.** No two agents edit the same file; no agent pushes to main or merges its own PR. Always commit and push to its assigned feature branch and report the PR URL and honest tests. If Work/Codex/local execution is unavailable, do not fake test results.

| Track | Assigned branch | Exclusive write scope | Prompt |
|---|---|---|---|
| A: Core vehicle + integration | `feat/core-driving` | `project.godot`, `addons/`, `scenes/`, `scripts/vehicle/`, `tests/core/`, `docs/DEPENDENCIES.md` | `prompts/PARALLEL_A_CORE_DRIVING.md` |
| B: World generation + road data | `feat/worldgen` | `worldgen/`, `data/world/` | `prompts/PARALLEL_B_WORLDGEN.md` |
| C: Racing AI and event framework | `feat/racing-systems` | `modules/racing/` | `prompts/PARALLEL_C_RACING.md` |
| D: Civilian traffic simulation | `feat/traffic-systems` | `modules/traffic/` | `prompts/PARALLEL_D_TRAFFIC.md` |
| E: Original/free art asset pipeline | `feat/art-pipeline` | `assets/curated/`, `tools/asset_pipeline/` | `prompts/PARALLEL_E_ART.md` |

Read `docs/INTERFACES_V1.md` before implementation. Racing/Traffic Agents should create their own self-contained fixtures/tests and must not wait for the World Agent; the World Agent owns the canonical road graph. Core Agent must not start loading worldgen/racing/traffic/art branches until integrator merges them.

### Required shared completion policy
Stay on the current task and use available tool calls to continue implementation, debugging and testing until ALL assigned acceptance criteria achievable in the available environment are satisfied, or an actual blocking dependency / tool or context quota prevents continued meaningful work. Do not hand back after producing a plan or scaffolding. Do not claim completion if tests weren't run. If blocked or nearing the tool limit, commit/push a reproducible partial state, preserve logs, and report clearly what is complete vs blocked.

### Integration after independent PRs
1. Review Track A first; confirm basic Godot runtime, addon licenses and vehicle behavior.
2. Merge World data and connect it to the Road Generator with an adapter; preserve contract or propose changes in a separate PR.
3. Merge Art pipeline/assets and perform engine imports.
4. Merge Racing and Traffic modules one at a time, replacing fixture data with canonical world graph and performing integration tests.
5. Don't expect isolated module tests to prove complete game behavior. Do a real combined playtest, performance test and controller test after integration.

If multiple agents cannot run on separate branches/worktrees in the available tool, run only one at a time. Parallelism is safe only with isolation and clear ownership.
