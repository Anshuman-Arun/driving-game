# Phase A Trees & Forest Art Deliverable (`trees-art`)

Date: 2026-11-24 / 2026-11-25
Branch: `feat/environment-realism-swarm`
Scope: Aster Valley Phase A Realistic Tree Species & Forest Canopy Pass

## 1. Overview & Objectives

Replaced repetitive procedural umbrella trees with 5 genuinely realistic temperate tree species and variants inspired by Forza Horizon's lush layered woodland:
1. `conifer_tall`: Tall alpine fir / spruce (15.0m height, 2.7m radius), sweeping whorls, natural spire leader, 5 buttress root flares extending down to `-0.16m`.
2. `conifer_medium`: Mountain / Scots pine (10.5m height, 4.4m radius), sinuous trunk, warm cinnamon upper bark grading from dark craggy base, open crown gaps with cupped 3D needle pads.
3. `broadleaf_oak`: Mature temperate oak / beech (10.3m height, 6.5m crown spread), 5 crooked primary boughs, forked secondary limbs, sky gaps, zero umbrella dome, scanned `LeafSet016` foliage cards.
4. `broadleaf_birch`: Slender silver birch / alder (10.6m height, 2.4m radius), forked ascending limbs, chalky silver-white lenticel bark with dark basal collar, delicate dappled `LeafSet024` leaf sprays.
5. `sapling_conifer`: Young understory fir / pine (3.5m height, 1.2m radius), feathery lower boughs starting near ground level (`0.4m`) to clothe hillsides and forest floors.

---

## 2. Model & Geometry Contract

All models exported in glTF 2.0 Binary (`.glb`) format to `assets/environment_realism/trees/`:
- Coordinate space: Metric, Y-up, ground pivot `(0, 0, 0)` with buttress root flares extending down to `-0.15m .. -0.17m` so hillside placement never exposes floating bases.
- Material / Surface split:
  - **Surface 0 (`bark`)**: Opaque PBR with embedded Albedo, Roughness, and Normal maps (`StandardMaterial3D` compatibility).
  - **Surface 1 (`foliage`)**: Alpha-scissor foliage cards with embedded Albedo, Alpha, Roughness, and Normal maps.
- Vertex Attributes:
  - `COLOR.rgb`: Baked inner-crown / trunk root ambient occlusion (`0.46 .. 1.0`).
  - `COLOR.a`: Wind flex weight (`0.0` at root / trunk anchor, ramping smoothly through branches to `1.0` at outer tips and needle sprays).
  - Normal smoothing: Surface 1 foliage card normals blended ~72% outward / upward from species crown centers for soft sunlit / backlit canopy illumination.

### Verified Mesh & LOD Statistics (`tree_stats.json`)

| Species / GLB File | LOD | Triangles (Total) | Bark Tris | Foliage Tris | Height (m) | Crown Radius (m) | File Size (KB) |
|---|---|---|---|---|---|---|---|
| `conifer_tall_lod0.glb` | LOD0 | 4,164 | 1,800 | 2,364 | 15.05 m | 2.74 m | 7,906 KB |
| `conifer_tall_lod1.glb` | LOD1 | 1,734 | 656 | 1,078 | 15.06 m | 2.38 m | 2,161 KB |
| `conifer_tall_lod2.glb` | LOD2 | 144 | 60 | 84 | 15.06 m | 2.44 m | 2,089 KB |
| `conifer_medium_lod0.glb` | LOD0 | 1,334 | 566 | 768 | 10.48 m | 4.37 m | 7,964 KB |
| `conifer_medium_lod1.glb` | LOD1 | 576 | 256 | 320 | 10.12 m | 4.20 m | 2,197 KB |
| `conifer_medium_lod2.glb` | LOD2 | 84 | 60 | 24 | 10.08 m | 3.40 m | 2,175 KB |
| `broadleaf_oak_lod0.glb` | LOD0 | 2,072 | 1,112 | 960 | 10.29 m | 6.51 m | 8,836 KB |
| `broadleaf_oak_lod1.glb` | LOD1 | 1,124 | 404 | 720 | 10.17 m | 6.13 m | 2,428 KB |
| `broadleaf_oak_lod2.glb` | LOD2 | 208 | 128 | 80 | 9.90 m | 6.16 m | 2,387 KB |
| `broadleaf_birch_lod0.glb` | LOD0 | 768 | 480 | 288 | 10.59 m | 2.42 m | 6,730 KB |
| `broadleaf_birch_lod1.glb` | LOD1 | 508 | 316 | 192 | 10.73 m | 2.46 m | 1,952 KB |
| `broadleaf_birch_lod2.glb` | LOD2 | 128 | 96 | 32 | 10.49 m | 2.78 m | 1,936 KB |
| `sapling_conifer_lod0.glb` | LOD0 | 946 | 368 | 578 | 3.54 m | 1.20 m | 7,765 KB |
| `sapling_conifer_lod1.glb` | LOD1 | 122 | 60 | 62 | 3.54 m | 1.20 m | 2,087 KB |

Total: **14 GLBs** fully built, checked, and exported.

---

## 3. Texture Atlases & PBR Maps

Authoring pipeline script: `tools/environment_assets/build_trees.py`.
Textures stored in `assets/environment_realism/trees/textures/`:

1. **Botanical Foliage Atlases (1024×1024 + 512×512 mip-optimized)**:
   - `fir_bough`: Deep fir / spruce needles with 3D diamond-beveled needles and micro-shadowing.
   - `pine_bough`: Longer radiating pine needle fascicles with warm-tip gradients.
   - `oak_spray`: Multi-lobed oak foliage cards with scanned `LeafSet016` (ambientCG CC0) color, opacity, normal, and roughness maps.
   - `birch_spray`: Sunlit silver birch leaves with scanned `LeafSet024` (ambientCG CC0) color, opacity, normal, and roughness maps.
   - Alpha processing: All foliage atlases use un-premultiplied color with **Jump-Flood algorithm RGB dilation** extending valid foliage colors into transparent texels to eliminate dark black edge fringes across mipmaps.

2. **Bark PBR Sets (1024×1024 + 512×512 seamless)**:
   - `pine_bark`: Coarse reddish-brown fissured plates (Poly Haven CC0).
   - `oak_bark`: Cool neutral weathered gray-brown deep vertical furrows (ambientCG `Bark012` CC0).
   - `birch_bark`: Chalky silver-white papery bark with horizontal dark lenticels and diamond branch scars (ambientCG `Bark004` CC0 + procedural lenticels).

---

## 4. Integration Guide for Runtime (`veg-runtime`) & Shaders (`lighting-shaders`)

- Paths:
  - Tall Alpine Conifer: `res://assets/environment_realism/trees/conifer_tall_lod{0,1,2}.glb`
  - Medium Pine: `res://assets/environment_realism/trees/conifer_medium_lod{0,1,2}.glb`
  - Broadleaf Oak: `res://assets/environment_realism/trees/broadleaf_oak_lod{0,1,2}.glb`
  - Broadleaf Birch: `res://assets/environment_realism/trees/broadleaf_birch_lod{0,1,2}.glb`
  - Understory Sapling: `res://assets/environment_realism/trees/sapling_conifer_lod{0,1}.glb`
- Suggested LOD Transition Distances:
  - LOD0: `0 .. 70 m`
  - LOD1: `60 .. 220 m`
  - LOD2: `200 .. 700 m` (culled beyond visibility range)
- Shaders: Surface 0 binds `tree_bark.gdshader`; Surface 1 binds `tree_foliage.gdshader`.
