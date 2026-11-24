# Premium visual source pack — Aster Valley

**Status:** acquisition tooling and curated catalog; the payload is not considered installed until the downloader completes and offline verification passes.

This is an additive handoff for the graphics swarm, not a scene, renderer, vehicle or physics rewrite. No new third-party car models: main already contains three detailed hero meshes; the two Porsche-derived models have unresolved independent model-rights questions (repository-level MIT is not proof of rights to a car mesh). Preserve current game behavior while the owner reviews that issue separately.

## Automated acquisition

From the repository, run `python tools/premium_assets/acquire.py`. Python 3.10+ standard library only; no manual asset shopping, extraction or API key. It downloads official Poly Haven glTF packages including all texture/buffer dependencies, and PBR map sets. It rejects missing dependencies, invalid source hashes, oversized files and incomplete packs; installs only after verifying the full staged payload. Maximum 85 MiB/file and 450 MiB total. Three attempts maximum per request. Existing verified payload is left unchanged.

`python tools/premium_assets/acquire.py --verify` checks local SHA-256 hashes and glTF references, offline. `--plan` prints the selected catalog. The resulting `assets/premium_world/payload/LICENSES_AND_HASHES.json` lists exact files, authors, upstream URLs and hashes.

Source: [Poly Haven](https://polyhaven.com/) — [CC0 license](https://polyhaven.com/license), [API documentation](https://polyhaven.com/our-api). Every entry in catalog.json points to https://polyhaven.com/a/<id>. No API is used in the game.

## Graphics swarm integration contract (not performed here)

- Worker 1: reuse existing `assets/forza_env/hdri/outdoor_sky.hdr` and `garage_studio.hdr`; align the sun with the actual panorama before tuning. Avoid a second competing environment.
- Worker 2: reuse `assets/curated/models/vehicles/` rig contract; preserve wheel pivots and surface mappings. Do not treat existing license ledger as a clearance for branded vehicle geometry.
- Worker 4: existing asphalt, gravel, shoulders and all PBR maps are already in `assets/forza_env/textures/`. Use the new clean/worn 4K map sets as optional material variants; maintain proper UV scale, mipmaps, normal map import and road collision.
- Worker 5: new model entrypoints are listed in the payload lock; use actual mesh geometry, not a primitive approximation. Split multi-object packs and preserve alpha cutout textures; create simplified meshes and impostors before instancing. Import source glTFs as candidates, not as 235,686 full-resolution instances.
- Integrator only: use isolated assets, preserve current scene and collision, choose via visual comparison. No automatic replacement of existing working assets.

## Acceptance gates

Source triangle counts in the lock are not gameplay budgets. Start near-road tree LOD0 around 8–20k triangles, LOD1 2–5k, LOD2 billboard/impostor; hero cliff 10–40k, distant cliff simplified; grass use shared atlases and low-cost cards. These are starting budgets, not measured limits. Set model pivots to ground and normalize scale against the existing meter convention; check alpha edges, normal direction, UVs, texture filtering and silhouette. Keep high-detail assets local to the road and use distance/quality culling.

Compare fixed chase, low rear, wide mountain, and forest views on the existing RTX 4050 baseline. Measure 1080p frame time, peak VRAM, and popping. Target 60 FPS, not maximum texture resolution everywhere. Do not report AAA parity or imported/usable assets without actual Godot QA.

The old assets remain usable if acquisition or integration fails.
