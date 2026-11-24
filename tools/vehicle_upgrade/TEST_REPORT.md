# Verification Report — `feat/hd-vehicle-art` (PR #25)

Date: 2026-11-21.
Environment: Windows 11, Blender 4.5.10 LTS, Godot 4.7.2-stable (Vulkan 1.4.325 / Forward+, NVIDIA GeForce RTX 4050 Laptop GPU, 1920×1080, MSAA 4×).

## Visual Acceptance Verdict: **REJECTED (DO NOT MERGE AS HERO ART)**

The engineering pipeline (CC0 download + SHA verification, Blender 4.5 preparation + 3-tier LOD generation, Godot 4.7.2 import, `VehicleVisualAdapter`, GEVP wheel/brake/suspension binding, and 1920×1080 graphical QA) is **fully verified and passing**.

However, **actual 1920×1080 Godot renders prove that the upstream CC0 Spectral GT RS source model is visually inadequate for a production hero Vela GT**. Even unmodified (`spectral_gt_rs_game_ready.glb`), it is a procedural Python primitive assembly (cubes, spheres, cylinders, tori) rather than an artist-sculpted automotive mesh. It **must not** be approved or merged as replacement hero art.

---

## Measured Metrics (1920×1080, MSAA 4×, Forward+, RTX 4050 Laptop GPU)

| Model | Triangles | Vertices | Materials | Textures | Draw Calls | VRAM (MB) | Avg FPS | 1% Low FPS | GPU ms | Bounds (W×H×L m) |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| Curated `vela_gt.glb` (old) | 2,252 | 6,756 | 8 | 0 | 145 | 265.32 | 119.9 | 115.4 | 1.60 | 2.39 × 1.39 × 4.88 |
| Raw source `spectral_gt_rs_game_ready.glb` | 151,722 | 129,484 | 23 | 0 | 576 | 271.21 | 119.9 | 113.8 | 1.70 | 2.53 × 1.68 × 5.21 |
| Prepared `vela_gt_hero.glb` (LOD0) | 73,682 | 83,584 | 23 | 0 | 122 | 268.38 | 120.0 | 114.1 | 1.58 | 2.21 × 1.54 × 4.95 |
| Prepared `vela_gt_mid.glb` (LOD1) | 11,609 | 14,462 | 23 | 0 | 121 | 265.72 | 119.8 | 108.7 | 1.46 | 2.21 × 1.57 × 4.95 |
| Prepared `vela_gt_distant.glb` (LOD2) | 2,469 | 3,207 | 20 | 0 | 105 | 265.32 | 119.8 | 106.5 | 1.42 | 2.23 × 1.56 × 4.91 |
| Live GEVP driving (`test_driving_gevp.gd`) | 73,682 | 83,584 | 23 | 0 | 130 | 267.04 | 83.2* | 95.3* | — | — |

*\*Live driving test stepped physics + screenshot capture inside the 150-frame loop.*

---

## Visual Defects Documented in Upstream Spectral GT RS

Evidence screenshots in `tools/vehicle_upgrade/qa_screenshots/`:

1. **Roof / Seat Headrest Clipping** (`spectral_01_front_quarter.png`, `spectral_02_rear_quarter.png`, `spectral_03_side_profile.png`): Two large red ellipsoid seat headrests (`Driver_Headrest`, `Passenger_Headrest`) poke completely through the cabin roof and rear window.
2. **Full 360° Torus Fender Hoops Clipping the Road** (`spectral_03_side_profile.png`, `spectral_04_wheel_brake.png`, `driving_front_steer_wheel.png`): `Front_Fender_Lip_*` and `Rear_Fender_Lip_*` are full 360° torus rings detached from the body; the lower half of each blue hoop wraps underneath the tire and clips into the asphalt.
3. **Detached Primitive Bodywork**:
   - The hood is a flat blue plank with rectangular cubes glued on top, floating detached above an open gap over the nose.
   - Side doors are flat blue rectangles sticking out from the chassis with silver slabs glued on.
   - The panoramic roof is a detached flat black slab with two floating silver rods.
   - The rear wing and front splitter are flat white rectangular blocks (because `Carbon Fiber — Directional Weave` has `baseColorFactor = None` and zero textures).
4. **Unusable Opaque Glass & Blocked Cockpit** (`spectral_05_cockpit.png`): `Smoked Smart Glass` uses `alphaMode: OPAQUE` with dark `baseColor` (`[0.012, 0.030, 0.055]`) and `KHR_materials_transmission: 0.62`, rendering opaque in Godot Forward+ and completely obstructing the cockpit camera view.
5. **Primitive Wheels, Glossy Rubber & Misaligned Calipers** (`spectral_04_wheel_brake.png`, `driving_front_steer_wheel.png`): Tires are smooth clearcoated balloon tori (`roughness = 0.36`, `KHR_materials_clearcoat` enabled on rubber) with 4 tiny sidewall bricks; rims are flat discs with 6 rectangular spoke bars; brake calipers float outboard of the brake disc.
6. **Zero PBR Textures** (`Textures: 0, Images: 0`): All 23 materials are solid-color procedural values with `KHR_materials_clearcoat` applied globally even to rubber and leather.
7. **Headlights & Taillights**: Detached black rectangular boxes bolted onto the front/rear bumpers with flat emissive strips.

---

## Engineering & Adapter Fixes Verified in This Pass

All pipeline, import, and GEVP runtime defects were fixed and verified:

- **Source verification**: Downloaded pinned CC0 GLB via `download_spectral.py` (`4,688,844` bytes, Git blob SHA-1 `f5b814848453a6c75a48f5047fdadaa7bdc78969`, SHA-256 `e7b7f0d9de0c3bc3897c8134b1ceae5631b1da2690d336df18c3ea82e7238c73`).
- **`tools/vehicle_upgrade/prepare_spectral.py`**:
  - Fixed wheel grouping bug where chassis suspension parts (`Lower_Control_Arm`, `Upper_Control_Arm`, `Toe_Link`, `Damper`, `Coil_Spring_*`, `Brake_Line`) were previously parented under `Wheel_*_Pivot` and would have spun with the tires.
  - Fixed `5.73 cm` longitudinal axle misalignment (`CHASSIS_BODY_LONGITUDINAL_OFFSET_M`) so front/rear fender centers match GEVP's `-1.36 m` / `+1.35 m` axles.
  - Placed `Wheel_*_Pivot` and `Brake_*` at GEVP resting positions in the exported GLBs so standalone showcase and garage views render assembled while `VehicleVisualAdapter` still binds them at local `Vector3.ZERO`.
  - Applied local rotation/scale after `join_material_peers()` so Godot AABBs are tight (`2.21 × 1.54 × 4.95 m` instead of `5.37 × 3.51 × 5.55 m`).
- **`modules/vehicle_visuals/vehicle_visual_adapter.gd`**:
  - Fixed Godot 4.7.2 parse error `@export_file("*.glb,*.tscn")` -> `@export_file("*.glb", "*.tscn")`.
  - Fixed `static func attach_to` compilation before class cache registration.
  - Added clean hiding/restoration of `PlayerCarFactory`'s 15 placeholder chassis `MeshInstance3D` boxes when HD visuals load (leaving `CollisionShape3D` and GEVP `Wheel` nodes untouched).
- **`tools/vehicle_upgrade/capture_views.gd`**: Upgraded viewport capture to `1920×1080` and fixed nested node lookup (`find_child`).
- **`tools/vehicle_upgrade/test_driving_gevp.gd`**: Added real GEVP driving-scale test confirming:
  - `adapter_status.loaded = true`, `physics_untouched = true`, `hidden_factory_boxes = 15`.
  - Front wheel steering (`-11.19°` front vs `-0.57°` rear), wheel spin (`97.15 rad`), stationary brake calipers (`brake_caliper_spin_x = 0.0`), exact suspension tracking (`brake_caliper_suspension_y_error = 0.0`), and live LOD switching (`[true, true, true]`).
- **Headless checks**: `inspect_glb.py --enforce-lod` passes on hero/mid/distant; `modules/vehicle_visuals/tests/smoke.gd` passes `10/10` checks in Godot 4.7.2; Godot 4.7.2 `--headless --editor --quit` imports all 3 GLBs with zero errors.

---

## Recommended Replacement Licensed Sources

Because the reusable `VehicleVisualAdapter` and Blender LOD pipeline are now verified end-to-end, replacing the rejected Spectral GT RS only requires swapping in a genuinely artist-modeled car source:

1. **Fab — Spectra V35** (`https://www.fab.com/listings/15708b2a-78f7-405d-878a-74e96fab58ef`) — *Top commercial recommendation*: ~35k triangles, artist-modeled unbranded GT coupe with sculpted interior, UV-mapped PBR textures, FBX/GLB. Fits hero budget directly.
2. **Fab — Generic Sport Car with Interior GameReady** (`https://www.fab.com/listings/8e584a96-5fce-4b3a-bb8d-f69291e78c99`) — *Secondary commercial recommendation*: Artist-modeled generic sports coupe with interior, separate wheels/doors, 9 PBR materials (run through our Blender LOD pipeline to target 76k/12k/2.5k).
3. **Sketchfab — Generic Sport Coupé** (`https://sketchfab.com/3d-models/generic-sport-coupe-car-820a13c4831c41959ce75e6c2014e882`, CC-BY) or **Innerscene — Generic Mid-Engine Supercar** (`https://www.innerscene.com/tools/library/3d-parts/generic-mid-engine-supercar-73f252c5`, CC0) — *Free alternatives to audit in Blender/Godot before purchase* (verify sculpted bodywork, translucent glass, usable interior, and 4 separate wheels).
