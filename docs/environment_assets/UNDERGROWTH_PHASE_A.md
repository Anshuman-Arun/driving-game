# W3 Undergrowth Phase A — Deliverable Report

**Agent:** `grass-art` (W3)  
**Branch:** `feat/environment-realism-swarm`  
**Date:** 2026-11-25  
**Status:** ✅ GLBs exported, 🔄 shrub/rock rebuild pending user Blender approval  

---

## Deliverables

### GLB Assets (`assets/environment_realism/undergrowth/`)

| GLB | Tris | Y-range (m) | Materials | Source |
|-----|------|-------------|-----------|--------|
| `grass_short_lod0.glb` | 310 | -0.035 → 0.118 | `grass_short_mat` | `grass_medium_01` 4K |
| `grass_short_lod1.glb` | 26 | -0.208 → 0.326 | `grass_short_lod1_mat` | baked cards |
| `grass_meadow_lod0.glb` | 379 | -0.040 → 0.314 | `grass_meadow_mat` | `grass_medium_02` 4K |
| `grass_meadow_lod1.glb` | 26 | -0.185 → 0.499 | `grass_meadow_lod1_mat` | baked cards |
| `grass_tall_verge_lod0.glb` | 420 | -0.045 → 0.681 | `grass_tall_verge_mat` | `grass_medium_01`+`02` 4K |
| `grass_tall_verge_lod1.glb` | 26 | -0.070 → 0.750 | `grass_tall_verge_lod1_mat` | baked cards |
| `fern_lod0.glb` | 389 | -0.040 → 0.433 | `fern_mat` | `fern_02` 4K |
| `fern_lod1.glb` | 138 | -0.040 → 0.397 | `fern_mat` | 3D frond decimation |
| `wildflower_lod0.glb` | 420 | -0.035 → 0.187 | `wildflower_mat` | `celandine_01` 4K |
| `wildflower_lod1.glb` | 26 | -0.246 → 0.433 | `wildflower_lod1_mat` | baked cards |
| `shrub_woodland_lod0.glb` | 2280 | -0.070 → 1.370 | `bark`, `foliage` | `shrub_02` 4K |
| `shrub_woodland_lod1.glb` | 626* | -0.525 → 1.895 | `bark`, `foliage.001` | simplified bark + baked foliage cards |
| `rock_moss_lod0.glb` | 899 | -0.125 → 0.484 | `rock_moss_mat` | `rock_moss_set_02` 4K (3-rock cluster) |
| `rock_moss_lod1.glb` | 715* | -0.125 → 0.484 | `rock_moss_mat` | decimated (fix pending) |

> **\*** `shrub_woodland_lod1` and `rock_moss_lod1` are pending a rebuild with bug fixes.  
> Fix committed at `13bd8ec`. Requires user Blender approval to execute.

### Shaders (`assets/environment_realism/shaders/`)

> These are authored by `lighting-shaders` (W5), **not** W3. Listed here for completeness.

| Shader | Purpose |
|--------|---------|
| `undergrowth_grass.gdshader` | Opaque early-Z, wind flex + distance sink, reads ARM `.g` = roughness |
| `undergrowth_cutout.gdshader` | MASK alpha with distance-compensated scissor threshold |

---

## Vertex Attribute Contract

All undergrowth GLBs export **vertex COLOR** (Blender `COLOR` layer, `ACTIVE`):

| Channel | Value |
|---------|-------|
| `COLOR.a` | Wind flex weight: `0.0` at ground root → `1.0` at blade tips |
| `COLOR.rgb` | Root AO gradient: darkened at root (min configurable per variant), 1.0 at tips |

Normal vectors biased upward/outward for soft sunlit/backlit shading (blend factor per variant, 0.62–0.72).

Tangents exported (`export_tangents=True`) for normal map shading.

**Y-up, meters, ground pivot at (0, 0, 0).**  
Stems sunk below ground: -0.035 to -0.14 m (by species) so roots disappear naturally into terrain.

---

## Material Slot Contract (for `veg-runtime` / W4)

### Single-surface variants (grass, fern, wildflower, rock)
- Surface 0: single PBR material (OPAQUE or MASK per species)
- Texture pack: `diff.jpg/png`, `nor.jpg`, `arm.jpg` (R=AO, G=Roughness, B=Metal)

### Two-surface variant (`shrub_woodland`)
- Surface 0 (`bark`): opaque bark — `shrub_bark_diff.jpg`, `shrub_bark_nor.jpg`, `shrub_bark_arm.jpg`
- Surface 1 (`foliage`): MASK cutout leaves — `shrub_foliage_rgba.png`, `shrub_foliage_nor.jpg`, `shrub_foliage_arm.jpg`

This matches the board contract posted at #10.

---

## LOD Distance Fade

Coordinated with W5 (`lighting-shaders`) at board #16:
- `fade_start_m = 95.0`
- `fade_end_m = 145.0`

Encoded in `undergrowth_grass.gdshader` and `undergrowth_cutout.gdshader`.

---

## Instance Custom Data Contract (for `veg-runtime` / W4)

Coordinated with W4 at board #14:
- `STRIDE = 8`, `use_custom_data = true`
- `INSTANCE_CUSTOM = [phase, stiffness, biome_warmth, root_ao]`
- `COLOR.a` in vertex = **wind flex ramp only** (not per-instance)
- Per-instance wind phase and stiffness from MultiMesh custom data

---

## Sources

All sources CC0 licensed from Poly Haven:

| Variant | Source Asset | Cache Path |
|---------|-------------|-----------|
| grass_short, grass_tall_verge | `grass_medium_01` | `asset_library/environment_sources/grass_medium_01/` |
| grass_meadow, grass_tall_verge | `grass_medium_02` | `asset_library/environment_sources/grass_medium_02/` |
| fern | `fern_02` | `asset_library/environment_sources/fern_02/` |
| wildflower | `celandine_01` | `asset_library/environment_sources/celandine_01/` |
| shrub_woodland | `shrub_02` | `C:\Users\anshu\Documents\Coding\aster-valley-asset-source\models\shrub_02\` |
| rock_moss | `rock_moss_set_02` | `C:\Users\anshu\Documents\Coding\aster-valley-asset-source\models\rock_moss_set_02\` |

Provenance verified in `asset_library/environment_sources/PROVENANCE.json` (SHA-256 for staged sources).

---

## Build Tool

`tools/environment_assets/build_undergrowth.py` — full pipeline Python/Blender script (~1196 lines):

**Usage from host Python (auto-invokes Blender internally):**
```powershell
python tools/environment_assets/build_undergrowth.py [--variants VARIANT...] [--skip-renders]
```

**Usage from Blender worker directly (texture cache must exist):**
```powershell
blender.exe --background --python tools/environment_assets/build_undergrowth.py -- --blender-worker [--variants VARIANT...] [--skip-renders]
```

---

## Open Issues

| Priority | Issue | Fix Status |
|----------|-------|-----------|
| P0 | Shrub LOD1 card artifact — bark bleeds into foliage ortho renders | ✅ Fixed in script (commit `13bd8ec`), **pending rebuild** |
| P1 | Rock LOD1 barely decimated — 715 tris vs target 260 | ✅ Fixed in script (commit `13bd8ec`), **pending rebuild** |
| P2 | Contact sheet 4 (`undergrowth_topdown.png`) not rendered | Pending rebuild run |
