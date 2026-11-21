# Track A dependencies — pinned sources and validation state

Date: 2026-11-21. Repository branch: `feat/core-driving`. Ownership-limited report: shared `docs/PROJECT_STATUS.md` is intentionally untouched.

| Component | Upstream / pinned revision | License | Present on branch | Actual engine validation |
| --- | --- | --- | --- | --- |
| **Godot** | [Godot 4.7.2 stable](https://godotengine.org/download/archive/4.7.2-stable/) standard GDScript / Forward+ | MIT | `project.godot` targets 4.7.2 | **Blocked** — no Godot binary available in execution container |
| **Easy Vehicle Physics** | [DAShoe1/Godot-Easy-Vehicle-Physics](https://github.com/DAShoe1/Godot-Easy-Vehicle-Physics/tree/c392257f54f6ca537dc10bc5badad0c060f18982), exact commit `c392257f54f6ca537dc10bc5badad0c060f18982` (2025-08-17) | MIT, David Shoemaker, Dechode, Baron Wittman | `addons/gevp/scripts/vehicle.gd`, `wheel.gd`, original LICENSE + README; four source blobs confirmed SHA-identical | **Unverified** in Godot 4.7.2; custom Vela GT instantiates the actual RigidBody3D + raycast Wheel classes, not a hand-written pseudo-physics substitute |
| **Godot Road Generator** | [TheDuckCow/godot-road-generator release 0.9.5](https://github.com/TheDuckCow/godot-road-generator/releases/tag/0.9.5), published 2026-10-13; tag commit `7cbefde04e57a84499c5d8ba636c9cb4fd7d22c0` | MIT; original `addons/road-generator/LICENSE` retained | Official release-tag `addons/road-generator` code, UI, shaders, resource/prefab dependencies, icons. Removed upstream blend source and generated import cache | **Unverified** in Godot 4.7.2. Editor plugin is not automatically enabled; the demo scene currently uses a collision-capable generated-ribbon fallback, not native Road Generator instances |
| **Terrain3D** | [TokisanGames/Terrain3D v1.1.0-stable](https://github.com/TokisanGames/Terrain3D/releases/tag/v1.1.0-stable), release ZIP [Terrain3D_v1.1.0-stable.zip](https://github.com/TokisanGames/Terrain3D/releases/download/v1.1.0-stable/Terrain3D_v1.1.0-stable.zip). Published 2026-10-30 | MIT | **Not vendored**: upstream's official ~45.7MB release package contains required native binaries; GitHub text-only connector does not make the release ZIP/GDExtension binaries available | **Blocked**: no native DLL/SO and no Godot binary; main scene uses hand-graded mesh heightfield and triangle collision |

For issue #14, `addons/gevp/scripts/vehicle.gd` carries a local patch that bounds low-speed steering and blends in travel-direction assist. The upstream revision and MIT license above identify the vendored source. See the [4.7.2 validation results](../tests/core/STEERING_CAMERA_QA.md).

## Native requirements and hashes

Terrain3D official v1.1.0 release ZIP has SHA-256 `51b78bc758f5759cbc8eaaab14e5cf4e8661717e265fdd760f5abf945f15b243` (published release digest); do not confuse the GitHub source tree with a working plugin installation. To activate Terrain3D in a real clone, download and verify **that exact release ZIP**, copy its `addons/terrain_3d/` folder, including native `.gdextension` and the matching **Windows x64 .dll** for the Windows target (or Linux x86_64 .so for Linux testing), and inspect the official [installation notes](https://terrain3d.readthedocs.io/en/1.1/docs/installation.html). Its native dynamic-library loader must be validated in the Godot editor and an actual Windows export. Do not ship source-only Terrain3D as if it works.

Road Generator is copied from official 0.9.5 tag without source modifications. The upstream repository may contain generated `.import` files and non-runtime Blender design files; these were omitted. Review/enable it via Project > Project Settings > Plugins **only after** successful editor import. The Terrain3D connector source `addons/road-generator/connectors/terrain3d_road_connector.gd` is retained for the integrator, but its connection to a native Terrain3D instance is **not yet implemented/tested**; see [official connector wiki](https://github.com/TheDuckCow/godot-road-generator/wiki/Using-the-Terrain3D-Connector).

The GEVP implementation recommends >=120Hz; `project.godot` uses a fixed 120 physics ticks/s. Vela GT's nominal parameters include mass **1390 kg**, RWD torque split **0.0**, engine max **480 Nm**, wheel radius **0.35 m**, front/rear travel **0.22/0.24 m**, wheel grip by groups **Road/Dirt/Grass**, ABS/traction/stability from GEVP. These are code values, not verified tuning measurements.

## Repro commands (to run on a machine with Godot 4.7.2)

```bash
# Verify Godot version first; do not substitute untested 4.8 beta:
godot --version
godot --headless --path . --editor --quit
godot --headless --path . --script res://tests/core/smoke.gd
godot --path .  # play main scene; F5 in editor
```

The commands above are **instructions**, not completed tests. Runtime/smoke/GUI/gamepad verification is pending. This execution container returned **`bash: godot: command not found` (exit 127)**; a direct `git ls-remote` could not resolve `github.com`. GitHub writes here were performed through the connected GitHub app, with confirmed remote commit/ref updates.

Assets: Vela GT geometry, barriers, trees, road, road marking and sky use original procedural meshes/material colors, no external audio/textures/models. Retain the GEVP/Road Generator MIT files in builds when distributing substantial copies.
