# World traffic control pack — integrator handoff

## Dependency order and ownership

- Only content/traffic/ is edited on this feature branch.
- Source graph: World PR #3 feat/worldgen, data/world/road_graph_v1.json, Git blob 9bba378d68879df3baed2c97a4885c0adde88406.
- Simulator: Traffic PR #4 feat/traffic-systems, modules/traffic/src/traffic_simulation.gd. The v1 configure_junctions API accepts id, incoming_lane_ids, mode (stop / yield / signal), clearance_m, stop_s, period_s, green_s and phase_s.
- All 11 junctions and 72 turn connectors are inventoried. Eight are controlled; three are genuinely non-crossing pass-throughs.
- Do not merge this PR automatically or silently edit World, Traffic, root game, or shared interface contracts. Both dependency PRs remain unmerged.

## Godot integration (after the two dependencies are available)

~~~gdscript
const TrafficSimulation = preload("res://modules/traffic/src/traffic_simulation.gd")
const TrafficContentLoader = preload("res://content/traffic/traffic_content_loader.gd")

var simulation = TrafficSimulation.new()
var graph_value = JSON.parse_string(
    FileAccess.get_file_as_string("res://data/world/road_graph_v1.json"))
assert(graph_value is Dictionary)
assert(simulation.load_road_graph(graph_value))

var loader = TrafficContentLoader.new()
if not loader.apply_file(simulation):
    push_error("Traffic pack rejected: %s" % str(loader.errors))
    # Reject startup; reload the graph if retrying, to avoid partial control state.
else:
    print("Traffic content ready: ", loader.report)
    simulation.reset(20261121)
    simulation.set_density(10)
    # In game tick: simulation.set_player_state(player_position, player_radius, true)
    # In game tick: simulation.step(delta, camera_position, obstacle_circles)
~~~

Apply **once after load_road_graph** and before spawning or stepping. The loader checks the simulator's existing implicit merge mapping, all real turn reachability and lane ownership, release geometry, and duplication, before calling configure_junctions. The simulator's reset method keeps the authored junctions while clearing transient agents. A second application is rejected. The recorded Git blob is provenance; the GDScript loader compares **live topology**, not raw Git object bytes.

In the original Traffic PR #4 simulator, per-approach major/minor priorities, lane-specific signal phases, per-turn conflict reservations, per-approach stop offsets, signed traffic signs and physical collision shapes **are not implemented**. The separate fix/traffic-junction-safety branch is owned by the simulator agent and is not vendored into this PR. We intentionally do not author a signal: v1 controls all inbound lanes with one shared green/red phase, which does not create conflict-free crossing movements. Its stop line offset is globally fixed at 2.5 m and approach window is 16 m. Stop and yield are coarse all-approach policies; Valley's all-way stop is provisional and not real highway priority.

## Implicit merges and known safety blocker

TrafficSimulation.load_road_graph installs **22 implicit successor-merge zones** onto **62 connector lanes** (the five-arm Alder alone accounts for 5 outgoing merge zones and 20 incoming connector mappings). Eight explicit definitions then map **26 travel approach lanes**. The two namespaces of incoming lanes are disjoint, and no implicit definition is deleted or overwritten. An agent may hold an explicit entry reservation before reaching an implicit exit merge zone, because the simulator models them as separate zones.

The simulator only clears its explicit intersection reservation if its entered lane (the *turn connector*) reaches the configured clearance before transitioning to the next lane. Every authored clearance is therefore strictly less than the **shortest** connector in its junction. This avoids permanent reservation leaks, but at Alder/Cedar/Ridge/Valley/Lake/Pine there are genuine graph-centerline crossings as late as approximately 54–66 m along long connectors. Their shortest turn lengths range from 11.5 to 15 m, so a single small common clearance cannot cover all crossings. **Full no-overlap/no-deadlock claims cannot be made by this content pack alone.** The conflict audit quantifies these late intersections.

Overlook and Orchard have 2 opposing turn connectors each and no implicit merge; at both, the paths cross four times. Long explicit yield reservation clearances (64.5 m / 63.0 m) exceed their last measured centerline crossings while remaining shorter than both turns. Market, Depot and Chapel have no geometric crossing pair, so they are unimpeded. Test actual vehicle collision volumes and road pads later, not just centerline intersections.

Known bottlenecks: Alder's five-arm stop queue (20 turns, downtown), Valley's four-arm high-speed all-stop (12 turns), Ridge's steep/gravel four-way stop (12 turns), and the 64 m yield occupancy at Overlook/Orchard. Pine, Lake and Cedar are 3-arm yields without major/minor right-of-way. A future upstream simulator implementation should support *one atomic reservation over a union of conflicting turn paths*, with release based on the physical last conflict of each individual movement, and fair queues. That is outside this directory's ownership.

## Reproducible validation plan

The graph file does not exist on this branch's main base until World PR #3 is merged. For static validation, pass a separately exported graph path from the World PR, or run once both dependencies are integrated:

~~~bash
node content/traffic/tests/validate_content.js data/world/road_graph_v1.json
godot --headless --path . --editor --quit
godot --headless --path . --script res://content/traffic/tests/run_world_scenarios.gd -- --smoke
godot --headless --path . --script res://content/traffic/tests/run_world_scenarios.gd -- --full
~~~

Smoke is 15 seconds per case (24 cases; one seed). Full is 90 seconds per case (72 cases; three seeds). All cases replay twice with state, error, and conflict determinism checks. The measured minimum Euclidean **point** gap is diagnostic only: the 3.4 m opposite-direction lane-center spacing invalidates any blanket 3.6 m collision threshold. The current test uses four-axis oriented 4.5 m x 1.85 m body proxies, a 1.7 m vertical occupancy check, and strict 5.0 m same-lane following clearance. It classifies turning, merge, same-lane and other body conflicts and reports harmless near-center samples separately. Queues or held reservations above 30 s still fail. These proxies are not physical rigid-body collisions or FPS tests. Record realized density peaks, not just requested population.

**Native evidence:** GitHub Actions expanded CI run 44955678724, attempt 2, staged the canonical World graph and original Traffic PR #4 simulator (without modifying either dependency). Node 22.16.0 topology/14 negative mutations, Godot 4.7.2 import and all 24 native smoke cases passed. The 90 s full soak detected 33 failing cases of 72; see VALIDATION_REPORT.md for each site and false-positive separation. The CI workflow checks out feat/traffic-systems by a hardcoded ref, so it does **not** stage the newer fix/traffic-junction-safety branch. A read-only rerun against that fix requires CI ownership assistance or a disposable integration checkout; never rewrite the simulator or CI from this content-owned branch. Root game/manual driving/physical chassis tests remain unverified. Updating docs/PROJECT_STATUS.md is intentionally deferred due the exclusive content/traffic/ write scope.
