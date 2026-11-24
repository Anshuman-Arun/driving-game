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
