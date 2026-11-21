# Traffic module verification report — 2026-11-21

Branch: `feat/traffic-systems`; scope: `modules/traffic/` only.

## Executed in local container (Python 3.13)

Command:

```bash
python -m unittest discover -s modules/traffic/tests -p 'fixture_checks.py' -v
```

**Result: 7/7 PASS**, 0 errors, ~0.004 s. Checked road_graph_v1
metadata/IDs/references, 20 valid 3D lane polylines, directed connection
continuity and compatible headings, bounded route to the merge, lack of reverse
routing, 16 mutually separated warm spawns under 5 seeds, fixed-step tick
partition and swept rear-end bumper gap math.

Command:

```bash
python modules/traffic/tests/reference_flow_sim.py
```

**Result: PASS for 3 x 90 simulated seconds**, using 16 kinematic agents each
and two reservable junctions, with repeated same-seed replays:

| Seed | Simulated duration | Cars | Lane transitions | Released reservations | Moving agent-steps | Closest center spacing | Replay |
|---|---:|---:|---:|---:|---:|---:|---|
| 21 | 90 s | 16 | 92 | 29 | 27,418 | 4.00 m | identical |
| 20261121 | 90 s | 16 | 84 | 28 | 23,078 | 4.00 m | identical |
| 9181 | 90 s | 16 | 93 | 33 | 27,772 | 4.00 m | identical |

This is an **independent Python numerical reference**, not execution of the
GDScript scripts and not a Godot FPS benchmark. It exercises the same
high-level policy/fixture constraints but cannot prove the Godot module is bug
free. All three cases maintained at least 3.6 m inter-car center spacing and
completed repeated crossings without deadlock. Min center spacing 4 m is a
planar numeric observation, not a vehicle hitbox/collision guarantee.

## Improvements made from executed failures

1. Initial 16-car reference run failed at 85.3 s with a 2.00 m overlap between
   `east_turn` and `eb_out2`. Root cause: the fixture's east/west turnaround
   doubled back across its own approach. Both turnaround paths were reauthored.
2. Raising the conflict threshold from 2.2 to 3.6 m exposed a 3.45 m
   crossing conflict at 5.03 s between `feeder` and opposing `nb_in`. Split the
   northbound lane into `nb_in_far` + `nb_in`, added a side-junction reservation,
   and prevented spawns inside controlled connector clearance zones.
3. Re-ran all seven Python fixture assertions and all three 90-second replay
   scenarios; all passed after these corrections.

## Prepared but NOT executed

The GDScript suite `tests/run_tests.gd` contains direct tests of the **actual
module code** for loader validation/rejections, lane lengths/sampling and
curvature, route search, car-following/braking, red signal and stop sign,
obstacle braking, merge entry, dead-end recycling, player spawn exclusion,
vehicle adapter, fixed-seed determinism, 90-second 16-car crossing/overlap,
viewer-distance despawning and pool reuse.

Actual Godot command **not run**:

```bash
godot --headless --path modules/traffic --editor --quit
godot --headless --path modules/traffic --script res://tests/run_tests.gd
godot --headless --path modules/traffic --quit-after 600
godot --path modules/traffic
```

Reason: `godot` / `godot4` executables were not installed in the container,
its local package cache had no Godot binary, and direct binary retrieval was
blocked by the available runtime's network/download restrictions. **No Godot
parser, scene render, controller, physical collision or FPS tests were
performed.** Engine tests must run before this module can be declared verified
inside Godot 4.7.2; actual 10–20 vehicle visual behavior is therefore pending.

## Remaining integration gate

After Track A and Track B merge, run the GDScript suite from Godot 4.7.2 and
fix any reported parser/runtime errors, open the demo, then test world lane
export topology and supply junction controls. Near-player collision promotion
and traffic/racing spawn interaction are separate game integration tasks.
