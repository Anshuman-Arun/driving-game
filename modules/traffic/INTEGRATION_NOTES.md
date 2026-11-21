# Integrator handoff — traffic workstream D

**Ownership:** this PR deliberately edits only `modules/traffic/`. It does not
modify `docs/INTERFACES_V1.md` or the canonical world graph, root Godot project,
Core vehicle controller or Racing module.

## Import and hookups

1. After merging the world data, load `res://data/world/road_graph_v1.json` as a
   `Dictionary`; call `traffic.load_road_graph(parsed)` and log
   `traffic.graph.errors` on failure. The fixture uses the identical v1 schema.
   Noncontinuously joined world links will be rejected (3.5 m max gap and no
   near-reversal of heading); correct world export geometry rather than silently
   teleport NPCs.
2. Create any explicit `configure_junctions()` entries for world cross streets:
   approach lane IDs must end **before** the conflict point, next lanes must
   carry cars through it, and `clearance_m` should pass the whole crossing.
   Mere crossing polylines with no split/connector and no junction policy are
   not controlled. The world contract intentionally has no traffic-light keys.
3. Supply camera/viewer position to `traffic.step()` and actual hero position,
   radius and enabled state to `set_player_state()`. Pass moving/static obstacles
   as `[{"position": Vector3, "radius_m": float}]`. Suppress spawn in race
   grids by lowering density/disable player-specific areas at the caller.
4. Render lightweight far agents with pooled visuals. If a close vehicle needs
   contact physics with the player, spawn an actual colliding body and apply
   `VehicleAdapter.compute_drive_input()` from a lookahead command; arrange a
   one-way kinematic-to-dynamic handoff. This module itself intentionally does
   not create collision shapes or attach to the main vehicle physics plugin.
5. Use `get_stats()` and profiler to benchmark 0, 5, 10, 20 cars on the real
   terrain/road world. 30 Hz internal fixed updates and a hard 20-agent cap
   bound traffic CPU work; no real-world FPS can be claimed from isolated tests.

## Proposed future contract (do not modify v1 automatically)

For complex world junctions, a separate authored traffic control file (outside
`road_graph_v1.json`) could provide intersection IDs, connector conflicts,
priority, signal phase groups, stop line offsets and reserved-clear distances.
The existing `configure_junctions()` call already accepts a minimal subset.
No shared v2 migration is required for this PR.

## Known limitations

- Godot 4.7.2 binary was unavailable for direct engine parser, scene or
  GDScript test execution in the authoring environment; see TEST_REPORT.md.
- Cars are point-following kinematic approximations, not colliding physics
  bodies; an eventual rigid-body promotion layer is required for player contact.
- No lane changing/overtaking, four-way priority signage hierarchy or complex
  multi-phase turn-arrow signals. Stop/yield reservation is intentionally
  conservative. No off-screen persistent world simulation.
- No runtime automatic detection of arbitrary *geometric* intersections; the
  graph must split approaches and explicit junction controls must be supplied.
- A future scene importer should recreate the demo's resource paths under the
  root project; the demo is a separate Godot project, intentionally.
