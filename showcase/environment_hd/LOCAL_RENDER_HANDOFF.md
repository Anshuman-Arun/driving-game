# Needle Pass — local rendering and artistic review handoff

**Status, 2026-11-21: RENDERING BLOCKED in this authoring environment.**
Neither Blender, Godot 4.7.2 nor a real GPU renderer is available.
No beauty PNG, saved Blender scene, screenshot, or art acceptance is claimed.
The next requested deliverable is six genuine unretouched renders, not this report.

## Local setup from the existing feature branch (no rebase)

Use a Windows/Linux machine with working GPU, Blender 4.x, Godot 4.7.2
stable, Node 22+, Python 3.10+, and Git. Do not reset or overwrite local edits.

    git fetch origin
    git switch feat/environment-hd-showcase
    git pull --ff-only origin feat/environment-hd-showcase
    node tools/environment_hd/generate_models.mjs --check
    node tools/environment_hd/validate.mjs
    node tools/environment_hd/stage.mjs
    node tools/environment_hd/stage.mjs --check
    python -m py_compile tools/environment_hd/build_blender.py tools/environment_hd/verify_raw_renders.py

## Obtain actual raw Blender Cycles images

    blender -b --python tools/environment_hd/build_blender.py -- --render
    python tools/environment_hd/verify_raw_renders.py blender --write-manifest

Expected: showcase/environment_hd/NeedlePass_Portfolio.blend, and
showcase/environment_hd/renders/view_01.png ... view_06.png
plus renders/capture_manifest.json. The scene is created from canonical data
and six shared fixed camera poses. Direct raw 1600×900 renderer output only:
do not retouch or substitute images. Save logs and Blender version. The
optional --legacy-cliffs switch is for BEFORE comparisons only; omit in beauty.

## Obtain actual raw Godot 4.7.2 Forward+ captures

    godot --headless --path showcase/environment_hd --editor --quit
    godot --path showcase/environment_hd --script res://capture_views.gd
    python tools/environment_hd/verify_raw_renders.py godot --write-manifest

Do NOT use --headless for the capture command. Its onscreen viewport requires a
real rendering device. Expected files: showcase/environment_hd/renders_godot/
view_01.png ... view_06.png and capture_manifest.json. No HUD is displayed.
The verifier checks PNG header, resolution and SHA-256, but cannot establish
art quality or the truth of external provenance by itself.

## Visual acceptance gates, currently ALL OPEN

Review each paired frame at full resolution: natural cliff silhouette, bark
and foliage quality, fine debris density, shoulders/paint, ground and road
microrelief, occluded intersections, repeated meshes, air perspective,
highlight roughness, tree lighting and distant edge/seam artifacts.
Especially reject ground views 02/03 if low-fidelity props dominate.
Correct the scene and recapture before signing off; source code checks are
not artistic acceptance.

Flat procedural cliff slabs are disabled in both default beauty passes.
Their removal is NOT acquisition of a sculpted or scanned replacement.
Fallen branches, true pine-needle/grass tufts, nonprocedural near-firs, and
source-complete asphalt/ground normal maps remain artist tasks.

A vetted asset candidate is Poly Haven Boulder 01:
https://polyhaven.com/a/boulder_01 (Rico Cilliers, CC0:
https://polyhaven.com/license). It is a small 1.8 m boulder, NOT a whole
cliff. Download legally on the local workstation, record author/license,
URL, hash, import paths, triangle count and LOD; use multiple hand-composed
pieces only if the real render passes scale and silhouette review. This
candidate has NOT been acquired or inserted. Never use unverified Megascans.
The current shader reconstructs subtle bump from CC0 roughness maps, which
must not be mislabeled as missing source normal maps.

## Clean integration after visual and licensing review

Main has advanced separately. Do not rebase the art branch while it is
being edited and do not merge it directly into main. Once six real captures,
license checks and visual review pass, create a distinct integration branch:

    git fetch origin
    git switch -c feat/environment-hd-integration origin/main
    git merge --no-ff --no-commit origin/feat/environment-hd-showcase
    git status

Resolve conflicts manually, preserving newer main runtime, colliders,
vehicle/input systems, and world data. Run the root Godot import and both
standalone/integrated visual inspections; only then commit/push/open a PR
for review. The overlay must not own physics or steal the gameplay camera.
Profile 72 m spatial MultiMesh clusters on target hardware. No FPS, draw
calls or VRAM numbers are yet observed.
