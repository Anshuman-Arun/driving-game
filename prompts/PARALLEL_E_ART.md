# Track E — Free-licensed art, vehicle meshes, environment assets and import pipeline

You're the technical artist and asset engineer for **Aster Valley**, a semi-realistic offline Windows racing game. Your task is to deliver a usable, legally clean, performance-conscious collection of assets, import tooling, and previews—not a list of websites or mood boards.

## Isolation
- Repo: `Anshuman-Arun/driving-game`; create `feat/art-pipeline` from current main in an isolated checkout/worktree.
- **Exclusive write scope:** `assets/curated/` and `tools/asset_pipeline/` only. No changes to project.godot, scenes/, addons/, worldgen/, data/world/, modules/, root README, shared docs or main.
- Read AGENTS.md, docs/GAME_DESIGN.md, docs/ASSET_LICENSES.md, docs/PARALLEL_EXECUTION.md and docs/INTERFACES_V1.md. Do not modify the shared global license ledger; write asset manifests in your owned path instead.
- Only import content with explicit free redistribution rights, favoring CC0/original. No ripped Forza/commercial-game files, trademarked branded racing cars, unlicensed Sketchfab models or commercial music.

## Deliverable
An actual source-controlled **starter art library** that the core Godot game can import after your PR merges:
- At least one good-looking fictional road sports car with physically separate wheel meshes, materials and an easy-to-read scene/mesh hierarchy, plus one distinct alternative if feasible.
- At least two low-poly/LOD-friendly civilian traffic cars with separated wheels or documented wheel animation and reusable neutral materials.
- A compact collection of realistic environment assets/materials for asphalt, gravel, grass, soil, rock, tree/bush and roadside barriers/props. Aim for convincing visual cohesion and license simplicity.
- Preview images/render contact sheets and an import/normalization pipeline. All listed files must actually exist and be inspectable.

## Execution approach
1. Check tools: Blender CLI, Godot 4.7.2, Python, glTF tooling and source download access. Generate original low/medium-poly models procedurally if external asset download rights are unclear; this is preferable to unlicensed scraping. Reuse reliable CC0 materials from Poly Haven/ambientCG and specific explicitly permitted packs (Kenney etc.) only with real license evidence.
2. Produce/normalize GLB/glTF meshes to meter units, +Y up, forward direction consistent with Godot. Put wheel pivots and named mesh nodes in distinct transform hierarchies, make collision proxy dimensions clear, and give reasonable approximate dimensions for actual vehicle controller attachment later.
3. Ensure consistent PBR materials, reasonable polygon/texture budgets, and LOD/proxy options where possible; avoid 8K textures or hundreds of MB of unnecessary demo materials. Use 1K–2K texture sources selectively.
4. Put source files, curated binaries and derived optimized variants under `assets/curated/` with deterministic conversion scripts and validation in `tools/asset_pipeline/`. Verify no broken links/missing external texture references. Do not blindly commit large source archives.
5. Create `assets/curated/MANIFEST.json` with for each asset: path, category, source URL, exact author and applicable license, license evidence URL/file, modifications, expected scale/orientation, triangle count if measured, texture resolution, intended usage and attribution requirement. Preserve original MIT/CC BY license text as needed. For original procedurally authored items, record provenance as original created for project.
6. Provide `assets/curated/INTEGRATION_NOTES.md` giving exact car wheel node names, axis conventions, scale, suggested collision dimensions, and how to place road/vegetation assets into Godot. Create reproducible preview/contact sheet outputs and verify they correspond to actual assets.
7. Run mesh/file validation and engine import checks if Blender/Godot available. Record executed commands and outputs in `tools/asset_pipeline/TEST_REPORT.md`.

## Scope & limits
Total committed art should be compact; aim for < 150 MB combined raw repo/LFS payload unless a carefully documented asset justifies more. Do not sacrifice source licensing or usable wheel hierarchies for a flashy but broken car model. Do not attempt to integrate into the root game project; it is owned by another agent.

## Acceptance
- Actual car and environment assets exist and are importable/inspectable.
- Clear license and provenance exists for every third-party file; no unknown-license asset remains.
- Car scale and separate wheel geometry documented, with preview rendered from the actual mesh when tooling permits.
- Conversion/import validation has been run where possible; tests and limits are honestly reported.
- Only owned paths changed.

## Do not hand back early
Keep doing meaningful creation, asset improvement, licensing checks and import verification until the owned starter library is complete and tested, or real download/runtime/tool/context limitations stop progress. A research list alone is failure. If blocked, generate legal original fallback content and document it. Commit and push reproducible partial work if tool limits approach. Don't claim that visual quality or imports were verified without actually inspecting/rendering them.

## Git deliverable
Commit/push only owned paths to `feat/art-pipeline`, open PR `Art: licensed sports cars and environment asset pipeline` if possible, **do not merge**. Report files/assets count, approximate repository impact, original versus licensed sources, validation outputs, remaining TODOs and PR URL/SHA.
