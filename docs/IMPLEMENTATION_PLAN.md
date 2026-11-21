# Aster Valley — Staged implementation and acceptance gates

**One playable vertical slice at a time.** This repository currently contains documentation only. Work on a short-lived feature branch; keep main stable.

## P0 — Plugin compatibility and Godot project foundation
Create project.godot, a minimal main scene and vendor only necessary addon files from official sources. Validate Godot 4.7.2, Terrain3D 1.1.0 Windows GDExtension, Godot Road Generator 0.9.5 and Easy Vehicle Physics at a tested commit. Record licenses, actual revisions and test results in docs/DEPENDENCIES.md.

**Exit gate:** Godot project imports and each plugin individually loads; test road/terrain connector; run simcade car demo on a collision plane. If incompatible, preserve a minimal runnable scene and state the exact blocker.

## P1 — Driving vertical slice
Build a 500×500 m rolling terrain area with one continuous asphalt S-bend / acceleration straight / hairpin. Add a rear-wheel-drive fictional sports coupe, real suspension/traction physics, third-person chase camera, steering smoothing and analog gamepad input, km/h HUD, pause/resume and reset-to-road.

**Exit gate:** Car can drive, turn, brake, recover from a rollover and drive over road/terrain seams. Test in Godot; mark controller and driving-feel manual tests pending if no gamepad/graphics access. First Antigravity prompt stops here.

## P2 — Visual prototype
PBR asphalt/ground, terrain detail, lighting, forest/rock props, guardrails, LOD and instancing. Test rendering on real hardware; avoid adding unlicensed models.

**Exit gate:** Cohesive early visual direction and baseline FPS/memory observations; no gross road/terrain gaps.

## P3 — Full 2×2 km world
Five authored regions: Alder Town, Cedar Woods, North Ridge, Green Valley, Eastwater Lake. 8–12 km of connected drivable roads, a main loop and shortcut connectors, height changes, distinct scenic landmarks, culling and sensible performance settings.

**Exit gate:** Continuous town→forest→ridge→valley→lake→town drive; no impassable collisions. Measure performance before designing streaming.

## P4 — Free-roam game shell
Title screen, garage/car selection, three configurable original cars, free-roam HUD/minimap, local save, pause and settings.

**Exit gate:** Enter game, select/switch car, restart without losing settings and selected car.

## P5 — Road traffic
Build a directed lane graph from road meshes/paths. Use pooled traffic agents, intersection behavior, path-following and obstacle braking; simulate far traffic inexpensively.

**Exit gate:** At least ten nearby NPC vehicles travel and avoid frequent collisions, spawn safely and stay on the roads; optimize toward twenty when realistic.

## P6 — Racing AI and events
Data-driven sprint/circuit routes, race checkpoint order and anti-cut behavior, countdown, timer, positions, 3–5 AI rivals, recovery, results, event rewards and clean return to free roam.

**Exit gate:** Complete town circuit and ridge sprint against AI; checkpoint skips are rejected; quitting midrace returns cleanly to free roam.

## P7 — Final content and Windows export
Four events, audio, visual and handling polish, configuration presets, settings/save migration safety, license notices and Windows x64 export.

**Exit gate:** Offline standalone build launches without Godot, with keyboard/gamepad support. FPS target 60 at 1080p on an optimized preset; record actual FPS rather than asserting.

## Every milestone report must include
- Branch, commit SHA, and PR URL when applicable
- What is implemented and actually usable
- Files changed, third-party dependencies and licensing
- Commands/tests executed, their results and untested cases
- Known blockers and smallest next step
- Update docs/PROJECT_STATUS.md

**Scope exclusions:** multiplayer, weather simulation, car damage deformation, branded commercial cars, pedestrians, police, complex customization, paid assets, enormous procedural runtime world.
