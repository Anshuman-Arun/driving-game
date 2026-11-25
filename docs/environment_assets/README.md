# Environment asset library — acquisition and approval

Status: **acquisition tooling and shortlist, not installed assets.** This is an intentionally broad candidate library for Aster Valley. Poly Haven's official asset license is CC0; download service uses its own [API terms](https://github.com/Poly-Haven/Public-API/blob/master/ToS.md). Powered by Poly Haven. Source [license](https://polyhaven.com/license). Existing repo has Git LFS and substantial binary history. Do not commit the entire raw catalog, or cause LFS charges without checking the owner's available storage. Preserve originals externally and version approved derivatives with Git LFS as applicable. No paid sources, ripped commercial assets, or unauthorized brands.

## Start here (Windows PowerShell from repository root)

```powershell
py -3 tools/environment_assets/acquire.py --scope expanded --catalog-only
py -3 tools/environment_assets/acquire.py --scope core --resolution 4k --plan-only --budget-mib 8192
py -3 tools/environment_assets/acquire.py --scope expanded --resolution 4k --budget-mib 16384
```

Default output is a sibling folder named aster-valley-asset-source, outside Godot's import tree. Use --output D:\AsterValleyAssetSource if desired. Do not copy raw glTFs into the live Godot project without approval. First use 4k for master textures, keep original full mesh geometry; selectively use 8k for hero assets or 2k when hardware/storage demands it. No silent resolution fallback. If 4k is unavailable, inspect report and rerun --only ID --resolution 2k. --scope core is the fastest pass. --budget-mib is a cap per run, not a hard cap across all past runs. Use --max-assets and --only to stage additional batches. Re-running validates cached files instead of overwriting. Report statuses must be checked even if exit code is zero (partial completion is allowed); failed or skipped entries are not downloaded assets. Never label shortlist candidates approved.

## Quality and license audit
- [ ] Verify provider, source URL, author, actual CC0 notice and upstream file list; keep PROVENANCE.json with SHA-256/MD5 where supplied.
- [ ] Inspect raw asset in Blender: silhouette, real dimensions, material channels, UVs, alpha coverage, normals, topology, brands, missing textures, baked lighting, LOD suitability.
- [ ] Reject tropical/desert/ornamental species inconsistent with the valley, decorative indoor assets, duplicate meshes, trademarks or questionable third-party rights. Automated keyword selection is triage, not visual audit.
- [ ] Preserve source files unchanged. Export approved derivatives with exact source hash, author, license, modifications and intended region. Update docs/ASSET_LICENSES.md; CC0 source may be redistributed.
- [ ] Check Git LFS status and quota; add only approved production assets, not high-poly masters, cache, temp files, API catalog dumps or duplicate textures. Prefer a local external master library; ask owner before exceeding available storage.
- [ ] Use `git lfs ls-files` and inspect committed pointers; verify actual binaries with a clean pull. No broken pointers or external web requests at game runtime.

## Additional acquisition targets (manual review, not automatically approved)
- ambientCG (https://ambientcg.com/, https://docs.ambientcg.com/license/): CC0 road, grass, forest soil, gravel, stone, facade, painted metal, rubber, concrete materials; choose complementary 4k PBR maps. Verify asset page and archive contents.
- Kenney (https://kenney.nl/assets/racing-kit): CC0 traffic furniture as prototype only; replace stylized parts in hero areas.
- Fictional sports cars: audit existing three first. Use the Khronos CarConcept license/provenance where suitable; see current ledger. Do not assume MIT repo license covers a Porsche mesh or manufacturer badge. Avoid licensed-brand replacements and ripped models. If rights remain unclear, use original Blender edits or author a new fictional car.
- Where realistic houses, guardrails, poles, drainage and road signs are not available under clear free redistribution terms, make modular original models from CC0 materials. Do not buy assets or bypass access controls.

See [implementation mission](../../prompts/ANTIGRAVITY_ENVIRONMENT_ART_PASS.md) for work allocation, checklist and QA. The library is staged separately so existing driving logic and scene are unchanged.

## Initial GitHub acquisition evidence

[Run 45509977508](https://github.com/Anshuman-Arun/driving-game/actions/runs/45509977508) passed Python compilation and downloaded seven full 4K source candidates, but the artifact service refused publication because storage quota was exhausted. Its raw files are not accessible. The revised workflow stages only four small 4K foliage candidates under `asset_library/environment_sources/`, with a 60 MiB aggregate cap and 25 MiB per-file cap, excluding LFS-tracked extensions. `.gdignore` prevents Godot importing the staging library. Do not merge raw candidates into main indiscriminately; use them for local Blender evaluation and publish approved derivatives. A clean local clone can retrieve staged sources directly if that workflow succeeds. The full 4K library remains local acquisition only.

**Confirmed:** [Run 45510119939](https://github.com/Anshuman-Arun/driving-game/actions/runs/45510119939) succeeded. Run 45510119939 succeeded: four complete original 4K glTF source assets (grass_medium_01, grass_medium_02, fern_02, celandine_01), 53,173,790 staged bytes including provenance, were committed and pushed as 36b8095. The remote acquisition report confirms all four downloaded. They are not visually approved or integrated; the full library still needs local acquisition. See [remote source library](../../asset_library/environment_sources/) and its acquisition report. Do not rerun the staging workflow unnecessarily; it refuses to overwrite existing sources.

## Public repository and swarm handoff

Use [STORAGE.md](STORAGE.md) for the private Drive master archive and public GitHub production-asset policy. The master mission is now organized for 18 swarm specialties with explicit ownership, dependency waves and acceptance gates. The private Drive folder URL is intentionally excluded from the public repo.

## Public artifact re-test

After repository visibility changed to public, the 186-byte artifact probe (run 45511995091) succeeded. Retried acquisition run 45509977508 (attempt 2, job 138861997550) also succeeded: seven original 4K assets downloaded and published as artifact `environment-source-4k-core-trial` (277,777,929 bytes; artifact ID 14975532052, expiry 2026-11-27 23:41:36 UTC). Includes grass_medium_01/02, tree_small_02, fern_02, celandine_01, boulder_01 and rock_07; 7/9 planned candidates completed within the 300 MiB cap. This verifies artifact publication at this size, not unlimited capacity or LFS quota. The artifact is temporary; use the acquisition report and download locally, archive to private Drive, verify checksums, and do not commit the whole raw pack to Git. No visual approval or in-game integration is claimed.

## Quality-first swarm execution

The latest master prompt begins with an overriding execution policy: one approved phase at a time, five grouped implementation specialists maximum, High coordinator and High reasoning for tree, grass, runtime and shader/lighting specialists; Medium/Low for acquisition and mechanical work, High independent visual critique with Medium test execution. Start with Phase A, a 2 GiB acquisition cap and 300–500 m showcase. Use soft quota checkpoints rather than rushing implementation. Benchmark native 3440×1440 and 75% render scale, then stop at a meaningful phase checkpoint for user approval. See the master mission for exact assignments.
