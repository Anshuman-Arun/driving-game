# Vehicle art attachment handoff

Use the existing `modules/vehicle_visuals/` adapter for LOD and visuals. The integration's `GameShell.free_roam_created` signal exposes the driver before its first spawn. Subscribe to `driver.vehicle_spawned(body, car_id)` there to cover the initial vehicle and every parked replacement. When this second signal fires, the body is in the scene and its four GEVP wheels are initialized. Attach visuals or override the chassis-local Hood marker during that signal, before the camera binds to the new body. The stable identities are `vela_gt`, `orion_rs`, and `kestrel_xr`.

## Model coordinate and wheel contract

- Use meters, **+Y up**, **−Z forward**, and **+X vehicle right**. Keep positive, unit parent scale on the prepared body and wheel hierarchies. Bake source orientation, scaling and any mirrored placement before authoring attachment pivots.
- Name the chassis assembly `Body`. The prepared model must expose `Wheel_FL_Pivot`, `Wheel_FR_Pivot`, `Wheel_RL_Pivot`, and `Wheel_RR_Pivot`. Each rotating mesh has its pivot at the axle center and its roll axis along **local X**. Use the same names, axes and scale at each LOD. Optional `Brake_FL`, `Brake_FR`, `Brake_RL`, and `Brake_RR` carriers stay under GEVP's non-rolling wheel nodes so they follow travel and steering.
- GEVP remains the sole owner of steering, wheel roll and suspension. Front steering is about local Y. Each factory wheel's `WheelVisual` is the render-frame pivot under the corresponding GEVP ray. A replacement wheel pivot attaches there with identity local transform. Bake any mesh offset beneath that pivot. Do not copy the chassis-space wheel translation again.
- Current presets share the following geometry. The contact radius is **0.35 m** and the nominal front/rear tire widths are **245/265 mm**. Wheel centers move down by spring length from the ray origin. Static nominal extension is about **0.099 m front** and **0.108 m rear** at the current 55% compression tune.

| Wheel | GEVP property | Ray origin in chassis space | Available downward travel |
| --- | --- | --- | ---: |
| FL | `front_left_wheel` | (−0.88, 0.03, −1.36) m | 0.22 m |
| FR | `front_right_wheel` | (+0.88, 0.03, −1.36) m | 0.22 m |
| RL | `rear_left_wheel` | (−0.88, 0.03, +1.35) m | 0.24 m |
| RR | `rear_right_wheel` | (+0.88, 0.03, +1.35) m | 0.24 m |

Check full bump, full droop and steering lock in the fenders before accepting the asset. If a source model cannot match this envelope, agree on a new physics envelope before changing the mesh or car preset. Keep imported collision shapes, scripts and independent wheel animation out of the presentation scene.

## Camera mounts

- The live hood anchor is `CameraMounts/Hood`, currently (0, 0.86, −0.92) m in chassis space. Forward is the marker's local −Z and local Y is up. Put it ahead of the windshield, clear of the hood and roof at the camera near plane, and verify it on bumps and while rolling. The camera uses the marker in the same interpolated chassis pose as the fallback.
- `CameraMounts/Cockpit` at (−0.34, 0.94, −0.05) m is a provisional driver-eye anchor for future cockpit art. Place the authored eye behind the windshield, centered on the driver's seat and clear of the roof, A-pillar, steering rim and dash in the expected FOV. Compare clearance with the Godot camera's 0.05 m near plane and check both 16:9 and 3440×1440. A cockpit view needs a validated interior before it becomes selectable.

## Import and fallback gate

Before opting a car into the upgraded adapter, run a clean Godot 4.7.2 import and confirm every LOD has the body and all four pivots. Then connect the existing visual adapter to the real chassis and drive with visible rebound, steering and wheel spin. Confirm the brakes do not roll, and that the hood mount and any cockpit markers are clear. `FallbackBody` and the original wheel meshes remain visible until the adapter reports a loaded visual. Hide `FallbackBody` only on that success path and restore it on detach or failure. Continue using the adapter's existing wheel fallback. Test a missing asset and an incomplete asset, a parked swap, and a fresh save reload. No upgraded asset is installed by the garage branch.
