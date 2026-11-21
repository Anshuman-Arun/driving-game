# Asset selection and quality gate — Needle Pass

**Checked 2026-11-21.** The selection is intentionally CC0-only. It is an authentic source package, not a claim of portfolio-level visual completion.

| Candidate | Access | Decision | Assessment |
|---|---|---|---|
| Poly Haven Asphalt 02, Rob Tuytel | **Actually copied** albedo and roughness from a public source mirror, full 1K JPEGs | Selected | Credible asphalt surface response; source normal could not be transferred; too little macro breakup by itself |
| ambientCG Ground093C | **Actually copied** 1K albedo/roughness, verified against upstream mirror | Selected | Natural gravel/soil base, still needs vegetation debris and variation masks |
| ambientCG Rock063 | **Actually copied** color, OpenGL normal, roughness at 1K | Selected | Detailed photographic rock microrelief for cliff material; geometry silhouettes still authored, not photogrammetry |
| Existing Aster Valley PR #7 curated conifers, shrubs, rocks and guardrail | **Actually present and copied in this folder** | Functional distance fallback | Very low-polygon prototypes; too weak for hero closeups |
| New Needle Pass fir, fractured cliff and fern glTF | **Authored and committed** with deterministic source | Foreground / middle-ground art experiment | Higher geometry complexity, but artist review and nonprocedural model refinement still required |
| PR #23 stone arch and terrain-safe placements | **Read and reused** without modifying the PR | Reference landmark/composition | Existing blockout, not a photorealistic asset |
| Poly Haven 3D scanned boulders and forest props | Public CC0 catalogue confirmed, **not downloaded** | Future upgrade | Would be better close-up rock forms than authored fractured sheets |
| Fab/Megascans | Public catalogue, **not account-acquired** | Not included | Acquisition-specific terms, license/account uncertainty, and no confirmed local asset |
| Premium tree libraries / commercial vegetation | **Not acquired** | Excluded | Cannot assert permitted redistribution or legal source availability |

## Specific current shortcomings
The photographic maps are **1K**, not 2K–8K. Asphalt and ground normals are absent (not fabricated). Foliage silhouette is branch-rich but generated from parametric triangles; bark/needle cards lack fully scanned maps, wind, and high-end leaf-translucency tuning. Cliff silhouettes are generated rather than manually sculpted. Forest interior needs hand-authored species variation, deadwood, fallen leaves, macro material blending, decal art, and actual near-ground photography. The available shader applies steep-slope texture blending but does not replace authored soil layers. No physically-based material has yet been inspected in Godot/Blender.

Reference visual design: temperate Cedar Woods shade, banded North Ridge rock, controlled warm sunlight at low angle, readable sunlit openings, shaded foreground, cool far background; emphasis on natural photographic hierarchy and realistic reflective response. **Do not directly copy game screenshots or proprietary assets.**

License sources: [Poly Haven](https://polyhaven.com/license), [ambientCG](https://docs.ambientcg.com/license/), [Fab acquisition and downloads](https://dev.epicgames.com/documentation/en-us/fab/purchasing-and-downloading-assets-in-fab). Exact mirrored file origins and project provenance are in `ASSET_MANIFEST.json`.
