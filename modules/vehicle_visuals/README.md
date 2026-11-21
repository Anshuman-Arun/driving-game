# Production vehicle visuals adapter

This is **not** a driving controller. The GEVP `Vehicle` RigidBody3D, four
`Wheel` RayCast3D suspension nodes, collision layers and physics tune are never
replaced or edited. Source: existing `scripts/vehicle/player_car_factory.gd` on
PR #20's prerequisite Core branch (as inspected 2026-11-21).

## Non-invasive attachment after existing factory construction

```gdscript
const VisualAdapterScript = preload("res://modules/vehicle_visuals/vehicle_visual_adapter.gd")
var car = PlayerCarFactory.create()
add_child(car)
var visuals = VisualAdapterScript.attach_to(car)
print(visuals.get_visual_status())
```

On a branch where the factory has not yet merged, do not instantiate it or
declare the visual integration working. Call `connect_chassis(car)` once after
the four factory wheels have their `wheel_node` pivots.

The full car model is an importable glTF 2.0 scene with exactly one `Body`
node and `Wheel_FL_Pivot`, `Wheel_FR_Pivot`, `Wheel_RL_Pivot`,
`Wheel_RR_Pivot`, plus `Brake_FL` / `FR` / `RL` / `RR` nodes. Geometry
in each wheel/brake pivot must be **centered around that local origin**.
The adapter takes only rendered children from the new scene and mounts rolling
geometry under existing GEVP `wheel_node`. This inherits the physics engine's
suspension travel, steer rotation (from the Wheel parent) and X-axis wheel
roll exactly once. Brake caliper carriers are parented to the `Wheel` but only
track `wheel_node.position.y`, so they do not roll.

The source vehicle is +X forward, but the preparation tool exports -Z forward.
The car body is calibrated to the **actual GEVP 2.71 m wheelbase** and the
wheels to the existing **0.35 m tire radius**, independent of physics changes.
Calibrations are initial authoring assumptions, not graphical proof.

If a file is absent or missing any required rig node, the original car's
procedural meshes remain visible. `get_visual_status()` reports fallback
truthfully. The adapter never substitutes a low-poly mesh and calls it HD.

LOD paths (expected once generation has actually been run):

| Distance | File | Geometry target |
|---|---|---:|
| Near, player/hero | `assets/vehicle_upgrade/vela_gt_hero.glb` | 35k–80k triangles |
| Mid (default 27 m) | `assets/vehicle_upgrade/vela_gt_mid.glb` | 5k–15k triangles |
| Far (default 85 m) | `assets/vehicle_upgrade/vela_gt_distant.glb` | 1k–3k triangles |

Incomplete optional LODs retain the last valid model instead of vanishing.
All distances are adjustable. Garage preview: instantiate adapter on a
non-physics Node3D, call `setup_garage_preview()`, and change angle using
`set_garage_preview_rotation(yaw_radians)`. Anchor points are available via
`get_camera_mount("RearChase" | "Hood" | "Cockpit")`; this module does
not change the existing camera code.

## Integration gate

PR #20 is not on `main` as of creation. Therefore this PR contains an
adapter, **not a patch to the existing factory**. No factory modification
is permitted by this task. When Core is on main, its owner can call the
adapter's three-line attachment hook and inspect the result.
