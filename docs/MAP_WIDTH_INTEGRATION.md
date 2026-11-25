# Current-main road width integration pass

## Provenance and scope

Base: `ffb791f60afbbf9e8ef98af4c26038d7350bbc89` (PR #41 merged; includes PRs #35 and #36). Source of the earlier geometry experiment: PR #38, `5ff54f0bcfe8632690dc02d17d3a7f577ea5812b`. New branch `feat/map-width-current-main`. Main is the sole integration baseline. Do not merge or cherry-pick the old branch wholesale.

- The canonical 104 directed lanes, 16 physical corridors, heightfields, region data, race definitions, six-car roster, professional audio sources/installers, premium textures, foliage and current scene data stay unchanged.
- Port the 8.4–11.2 m corridor targets, 2.0/1.6 m shoulders, 1 m junction buffer, legacy deck tapers, and existing 105 m depression support from #38.
- Preserve main's triangle-based clearance index (including height checks and true transformed mesh/collider footprints), premium vegetation filtering, normalized marking UV and signed metric UV2, concrete bridge shader and North Ridge guardrail alignment. Do not import the old clearance raster or old shader. Existing premium vegetation cache stays intact and runtime filtering is authoritative; future verge bake uses the wider profile.
- Main's traffic implementation and canonical test are unchanged. The old branch's repeated priority and spawning experiments are explicitly excluded: run 45560513027 retained safety but worsened queue waits to 1,319/1,167 ticks. Traffic queue throughput is an inherited issue, not solved by map widening. Run the original test, never relax its 30-second gate or claim it is green when it is not.

## Validation plan (one coherent first pass)

1. Pinned Godot 4.7.2 import; static data/regeneration tests; original traffic and deterministic canonical fixture with pinned controls from #22. Record baseline failure distinctly; no disabled assertions.
2. Full-network width collision sweep (at least 1,782 rays, adjacent-edge seam checks); actual triangle index coverage, four bridges and rails, original five widened approaches; vehicle-world grass route moved to dry ground with 9.2 m offset, exact collider accounting.
3. Main's world_visual_qa: zero vegetation/scenery overlaps, both tree LODs, accepted colliders, materials and alpha masks, 2,450 lane rays, six cars, every corridor, quality presets. Main's garage, core, controller simulation and showcase checks retained. Standalone world/racing/shell/scenery tests.
4. Main's strict audio QA runner plus pinned bank installer unit tests. No audio source modification or licensed bank redistribution. Live local professional-bank driving requires the already documented installer and its licensed downloads; rerun the existing professional-source-native workflow on the combined revision before release if available.
5. Review headless results before editing further. For actual visual/GPU/Windows acceptance, use the new main-based branch on the owner's machine with real controller; compare against docs/WORLD_VISUAL_QA.md and docs/SCENIC_SUPERCARS_QA.md, inspect widened curves, shoulder transitions, guardrail continuity and dropped/rejected scenery; rebake accepted vegetation only after inspection. No FPS, visual or controller hardware claims from headless CI.

## Known limitations and next pass

Main's clearance filter may reject additional roadside guardrails or furniture as the pavement expands. Measure the actual rejection report and inspect guardrail continuity; relocate only confirmed displaced hazards using actual triangle geometry and existing authoring orientation, not guessed offsets. Do not replace premium assets or change road topology to address traffic. If original traffic queues fail, establish main's unchanged baseline and profile arrivals, conflict occupancy and connector geometry in a dedicated traffic pass with independently verified collision/throughput requirements. No repeated speculative CI fixes. Update this document with observed run IDs and failures; keep draft until the combined acceptance gates are met.
