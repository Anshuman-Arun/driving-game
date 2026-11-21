# Aster Valley — canonical junction inventory

Source: World PR #3, `data/world/road_graph_v1.json`, Git blob `9bba378d68879df3baed2c97a4885c0adde88406`. Generated against that source, not a redrawn graph.

The graph contains **16 physical corridors, 32 corridor travel lanes, 72 turn connector lanes, 11 junction nodes**. The 27 `roads` entries include the 11 connector collections; do not interpret 27 as 27 physical corridors.

## Intersection control design

- **8 geometrically conflicting junctions** receive `TrafficSimulation.configure_junctions()` entries: 3 all-way stops (Alder, Ridge, Valley) and 5 yields (Cedar, Lake, Pine, Overlook, Orchard).
- **3 degree-two continuations** are inventoried but deliberately do not get runtime controls (Market, Depot, Chapel). The geometrically crossing two-way turn paths at Overlook and Orchard are explicitly yield-controlled. No fabricated junction or unnecessary stop.
- Stop offsets are the simulator's **fixed 2.5 m** constant, not a per-junction feature. Signals cannot alternate conflicting streams under current v1 semantics, so **no signals** are authored.
- `clearance_m` is deliberately shorter than *every* connector in that junction; a longer value can leak a reservation forever because the simulator only releases on `entered_lane` and before transitioning off the turn connector. This is a **runtime constraint, not proof of collision safety**.
- The simulator also installs **22 implicit successor-merge zones** on turn connector lanes. The explicit entries map the 20 incoming travel lanes, disjoint from those implicit connector mappings. Two sequential zones may still be encountered on a trip; do not erase or override implicit merges. Exact spatial conflict coverage and guaranteed body collision avoidance require simulator/world integration.

| Node | Region | Control | Inbound lanes | Turn connectors | Inbound speed limits (km/h) | Connector lengths (m) |
|---|---|---|---:|---:|---|---|
| junction_alder | alder_town | stop | 5 | 20 | 70, 35, 40, 35, 90 | 12.41–65.15 |
| junction_cedar | cedar_woods | yield | 3 | 6 | 70, 55, 55 | 11.71–67.24 |
| junction_ridge | north_ridge | stop | 4 | 12 | 55, 35, 60, 45 | 13.27–68.47 |
| junction_valley | green_valley | stop | 4 | 12 | 45, 75, 45, 85 | 11.84–66.54 |
| junction_lake | eastwater_lake | yield | 3 | 6 | 90, 45, 85 | 14.99–66.55 |
| junction_pine | cedar_woods | yield | 3 | 6 | 55, 35, 75 | 11.54–64.71 |
| junction_market | alder_town | pass_through | 2 | 2 | 40, 45 | 15.22–16.57 |
| junction_overlook | north_ridge | pass_through | 2 | 2 | 40, 60 | 65.4–65.85 |
| junction_orchard | green_valley | pass_through | 2 | 2 | 45, 40 | 63.75–64.53 |
| junction_depot | alder_town | pass_through | 2 | 2 | 35, 30 | 14.94–16.53 |
| junction_chapel | alder_town | pass_through | 2 | 2 | 35, 30 | 13.29–16 |

## Live API limitations and bottlenecks

**Alder:** a five-arm / 20-turn town hub, likely highest queue demand; stop dwell is applied to all five approaches. Its short turn connectors cannot hold the sole intersection reservation across every long physical crossing.
**Valley:** four-arm / 12-turn high-speed rural join; uniform all-way stop is an interim conservative behavior, not real arterial priority.
**Ridge:** four-arm / 12-turn narrow steep/gravel approach; stoppage on gradients requires native verification.
**Lake and Pine:** T-junction yields serialize only near conflict entry, without major/minor right-of-way semantics.
**Cedar:** forest T-junction yield; blind curves and speed transitions warrant real driving review.
**Overlook/Orchard:** opposing long turn connectors cross four times geometrically despite being degree-two nodes. They now share yield reservations with late clearances (64.5 m and 63.0 m) to protect measured centerline crossings.

No per-turn conflict matrix, priority signs, phase groups, per-lane stop offsets or true collision volumes are supported by the v1 simulation. A small geometric clearance **cannot guarantee non-overlap of cars** crossing far portions of the same large junction; native tests intentionally detect and report this rather than declaring collision safety.

See `INTEGRATION_NOTES.md` and `tests/` for the native run plan.
