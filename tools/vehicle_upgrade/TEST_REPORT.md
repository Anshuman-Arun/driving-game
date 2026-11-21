# Verification report — feat/hd-vehicle-art

Date: 2026-11-21 (UTC). Scope: vehicle visuals only.

## Actual checks

- **PASS** GitHub connector created `feat/hd-vehicle-art` from `main` and
  committed adapter, exact third-party CC0 license notice, source acquisition,
  Blender preparation/LOD script, GLB inspector, graphical capture harness and
  research/handoff notes, each within owned paths.
- **PASS** Fetched the real upstream `spectral_gt_car.py`, `README.md`,
  `REALTIME.md` and `LICENSE`, plus the model's GitHub tree blob size and SHA.
  The actual binary was not accessible for download in this environment.
- **PASS** Cross-checked real factory API from PR #20 Core:
  `PlayerCarFactory.create()` provides four GEVP Wheel nodes with
  `wheel_node`, front (-0.88/+0.88, -1.36) and rear (-0.88/+0.88, +1.35).
  GEVP wheel_node already applies suspension offset and X roll; Wheel applies
  steering. Source prep therefore does not add a second wheel-spin controller.
- **PASS** Independent numeric coordinate transform from +X Blender source
  to -Z Godot: body wheelbase 2.85*(2.71/2.85)=2.71 m;
  (0.405+0.135)*(0.35/0.540)=0.35 m **outside** tire radius; original source negative-side
  wheel maps to positive Godot X, so label side reversal is necessary.
  Body wheel-center vertical estimate 0.53*(2.71/2.85)-0.57=-0.066 m,
  near expected initial GEVP visual pivot height. After correct torus scaling,
  source fender-lip inner radius (0.438-0.045)*2.71/2.85=0.374 m,
  giving ~0.024 m theoretical tire clearance. The Blender script also
  boolean-cuts the continuous body loft at 0.385 m, but neither operation
  is visually/mesh-validated without Blender.
- **PASS** Source license is explicit CC0 at pinned revision, model is not gated.
  No Fab/Sketchfab/Blendkit paid or unknown-entitlement content was copied.
- **PASS** Tooling is additive: no shared `project.godot`, GEVP files,
  factory, camera, colliders, wheel physics or other agents' work changed.

## Not executed / cannot claim

| Gate | Actual result |
|---|---|
| Retrieve upstream GLB bytes | **BLOCKED:** GitHub connector returns empty for this binary; no container outbound connection |
| Blender 4.3+ import/retarget / tri counts | **NOT RUN:** Blender executable absent |
| Export actual Vela GT hero/mid/distant files | **NOT RUN:** source bytes and Blender unavailable |
| Inspect source normals, UVs, mats, cockpit, wheel grouping | **NOT RUN:** binary inaccessible |
| Source-level Python syntax/unit tests | **NOT RUN:** no source checkout in local runtime; connector edits only |
| Godot 4.7.2 import/parser | **NOT RUN:** Godot executable absent; `main` does not yet contain the PR #20 root game |
| Physically mounted steering/suspension / camera mounts | **NOT RUN** |
| Graphical screenshot matrix + old/new same-angle | **NOT RUN:** neither Godot renderer nor prepared GLB accessible |
| Real draw calls/GPU texture memory/VRAM/FPS | **NOT MEASURED** |
| Additional distinct car model | **NOT ATTEMPTED:** prioritize true hero acceptance first |

## Required acceptance sequence

1. Obtain and verify the actual source binary via
   `python tools/vehicle_upgrade/download_spectral.py`.
2. Run Blender preparation and all three `inspect_glb.py --enforce-lod` checks.
   Review materials/mesh splits after consolidation and repair topology defects.
3. Layer this branch on a game branch containing Core PR #20; attach the
   adapter without touching GEVP. Run Godot 4.7.2 headless editor import.
4. Run `capture_views.gd` graphically with old/new at matched angles. Inspect
   glass and interior, rolling wheel orientation, stationary brakes, forward
   direction and native road-scale proportions. Do a real-driving FPS/VRAM pass.
5. Only call the Vela GT production-ready after art and performance review.
   Do not merge this PR under a false 'complete HD art' description.
