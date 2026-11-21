# Art asset verification report — 2026-11-21

## Actual executed checks

- Tool availability: Python and Node.js 22.16.0 present. **Blender and Godot editor/CLI absent** from this environment.
- Generated six original primary GLBs; checked 12,088 triangles, GLB 2.0 headers, accessors, scene hierarchy, four independent wheel pivot nodes and separate tire/rim visual geometry.
- Generated 18 environment embedded glTF 2.0 files (4,127 triangles) and model-derived SVG projections. Pine tree LOD1: 49 triangles.
- Generated fourteen 256×256 original albedo/normal PNG files. Normal PNG chunk CRCs were checked on creation; generated albedo signatures and dimensions were checked.
- **Re-read actual GitHub branch assets:** Kestrel XR GLB validated at 2,340 triangles / 65 meshes / 70 nodes with four wheel hierarchies; deciduous tree glTF 1,448 triangles / 15 meshes / 16 nodes; rock normal PNG 256×256 with valid CRCs.
- Downloaded all six primary vehicle GLBs from GitHub and transformed to embedded glTF source and back to GLB in memory while preserving scene hierarchy. Source .gltf files committed to `sources/vehicles/`.
- Re-rendered directly from committed GLB/glTF mesh triangles: Vela GT = 2,252 triangles; pine tree LOD0 = 120 triangles.
- Inspected supplementary GLBs committed to this branch by a concurrent writer. Additional model triangle counts: alternative Vela 1,864, Orion 1,864, Kestrel 1,948, hatch/sedan/wagon 1,360 each; three traffic LODs 952 each; alternate pines 108 and 57 triangles.
- Queried the repository tree for asset inventory, content bytes and owned file paths.

## Not executed

- **No headless Godot 4.7.2 import or Blender render/test** was available. The committed standalone Node.js CLI wrappers were constructed from functions executed in Code Mode, but have not been invoked end-to-end from a local checkout; repository-level full validation is therefore still pending.
- No combined-world Forward+ screenshot, accurate normal/tangent visual inspection, collision drive-test, gamepad test or FPS/draw-call benchmark. Visual previews are SVG triangle projections, **not Godot screenshots**.
- Alternative `generate.js` was added concurrently. Its output GLB structures/triangle counts were inspected, but its complete generator CLI was not run in this task.

## Commands for next integration gate

```sh
node tools/asset_pipeline/validate.mjs
node tools/asset_pipeline/render_previews.mjs
node tools/asset_pipeline/generate_environment.mjs
node tools/asset_pipeline/generate_textures.mjs
node tools/asset_pipeline/convert.mjs --all
# After merging art into an actual Godot project:
godot --headless --path . --editor --quit
```

There are no third-party downloaded art assets; exact license and provenance for primary resources are recorded in `assets/curated/MANIFEST.json`.
