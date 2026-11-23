# Project status — single current-state log

Last updated: 2026-11-22

## Curated vehicle and scenery integration

The root game enters the garage and menu, and launches canonical free roam with the selected Vela GT, Orion RS or Kestrel XR. Curated GLBs follow the existing chassis and wheel mounts. The five-region scenery layer can be disabled independently of the world collision. Godot 4.7.2 import, the full-world road sweep, the graphical garage and driving flows, and selection recovery after restart passed. The [build validation report](../tests/integration/CURATED_BUILD_QA.md) records commands, performance, screenshots and visual limitations. Physical controller checks and production vehicle-art integration remain open.

## Menu, garage and car-preview refresh

The Home and Garage screens now use a consistent navigation row, clearer vehicle hierarchy, and a larger live 3D presentation built from the selected curated GLB. The preview now renders at native resolution with 4× MSAA on the normal preset and a studio-lit turntable; the high preset adds modest supersampling. No generated still-image backdrop was added.

This work is on `feat/aster-garage-home-refresh`, based on the open playable-build branch. Godot 4.7.2 import, parser and graphical verification have not been run for these UI changes yet. The #28 QA report remains the last verified build record.

## Vehicle and world integration

The free-roam integration branch boots the full canonical Aster Valley terrain and roads with the corrected Vela GT. Import, the full-world collision sweep, Core regressions, and three integrated headless and Forward+ routes passed on Godot 4.7.2. See the [vehicle/world validation report](../tests/integration/VEHICLE_WORLD_QA.md) for performance, screenshots, and remaining handling checks.

## Confirmed
- GitHub repository Anshuman-Arun/driving-game exists and is private.
- Design documents, initial prompt, and shared agent workflow are committed on main.
- Target software stack and scope have been selected for a compatibility proof.

## Remaining verification
- Physical controller checks and production vehicle-art integration remain open.
- Run a Godot 4.7.2 import/parser check and capture the refreshed Home and Garage screens before treating the UI work as visually verified.
- Do not replace the earlier gameplay and performance evidence with assumptions about this unverified UI branch.

## Next
Review the refreshed screens on the playable build, then merge the UI work after graphical and controller checks.

## Report template for future agent updates
Date and branch:
Commit or PR:
What now works:
Tests and measured results:
Not tested:
Dependencies and asset licenses:
Known blockers:
Next task:

Do not mark a phase complete on the basis of code generation alone.
