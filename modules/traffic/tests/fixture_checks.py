"""Executable Python 3 fixture/geometry validation; NOT a substitute for running GDScript.

Checks the published v1 schema, directed continuity, route reachability, simple
numerical spacing limits and deterministic 16-car spawn planning with no Godot.
"""
from __future__ import annotations
import copy
import heapq
import json
import math
import random
import unittest
from pathlib import Path

FILE = Path(__file__).resolve().parents[1] / "fixtures" / "intersection_v1.json"
DATA = json.loads(FILE.read_text(encoding="utf-8"))


def length(points):
    return sum(math.dist(p, q) for p, q in zip(points, points[1:]))


def sample(lane, s):
    points = lane["points"]
    s = min(max(s, 0), length(points))
    for p, q in zip(points, points[1:]):
        d = math.dist(p, q)
        if s <= d:
            t = s / d
            return tuple(a * (1 - t) + b * t for a, b in zip(p, q))
        s -= d
    return tuple(points[-1])


def lane_mapping(data):
    return {l["id"]: l for l in data["lanes"]}


def route(lanes, start, dest):
    queue = [(0, start)]
    shortest = {start: 0}
    parent = {}
    while queue:
        cost, current = heapq.heappop(queue)
        if cost != shortest[current]:
            continue
        if current == dest:
            result = [current]
            while current in parent:
                current = parent[current]
                result.append(current)
            return list(reversed(result))
        for other in lanes[current]["next_lane_ids"]:
            new_cost = cost + length(lanes[other]["points"])
            if new_cost < shortest.get(other, float("inf")):
                shortest[other] = new_cost
                parent[other] = current
                heapq.heappush(queue, (new_cost, other))
    return []


def spawn(seed, count=16):
    lanes = lane_mapping(DATA)
    ids = sorted(lanes)
    rng = random.Random(seed)
    active = []
    for _ in range(count):
        for _attempt in range(400):
            lane_id = rng.choice(ids)
            lane = lanes[lane_id]
            s = rng.uniform(0.1, 0.85) * length(lane["points"])
            p = sample(lane, s)
            if math.dist(p, (0, 1, 0)) < 24 or math.dist(p, (0, 1, 0)) > 175:
                continue
            if all(math.dist(p, other[2]) >= 12 for other in active):
                active.append((lane_id, s, p))
                break
        else:
            raise AssertionError(f"unable to spawn {count} cars at seed {seed}")
    return active


class FixtureTests(unittest.TestCase):
    def test_schema_unique_ids_and_references(self):
        d = DATA
        self.assertEqual((d["schema_version"], d["units"], d["coordinate_system"]), (1, "meters", "godot_y_up"))
        lanes = lane_mapping(d)
        self.assertEqual(len(lanes), 20)
        roads = {r["id"]: r for r in d["roads"]}
        self.assertEqual(len(roads), len(d["roads"]))
        for road in roads.values():
            self.assertTrue(road["name"])
            self.assertTrue(road["region"])
            self.assertTrue(road["lane_ids"])
            self.assertTrue(all(lanes[lid]["road_id"] == road["id"] for lid in road["lane_ids"]))
        for lane in lanes.values():
            self.assertIn(lane["road_id"], roads)
            self.assertGreater(lane["width_m"], 0)
            self.assertGreaterEqual(lane["speed_limit_kph"], 0)
            self.assertTrue(lane["surface"])
            self.assertGreaterEqual(len(lane["points"]), 2)
            self.assertTrue(all(next_lane in lanes for next_lane in lane["next_lane_ids"]))

    def test_polyline_geometry_nonzero_and_in_bounds(self):
        b = DATA["bounds"]
        for lane in DATA["lanes"]:
            p = lane["points"]
            self.assertGreater(length(p), 0.05)
            for point in p:
                self.assertEqual(len(point), 3)
                self.assertTrue(all(math.isfinite(x) for x in point))
                self.assertLessEqual(b["min_x"], point[0])
                self.assertLessEqual(point[0], b["max_x"])
                self.assertLessEqual(b["min_z"], point[2])
                self.assertLessEqual(point[2], b["max_z"])
            for start, end in zip(p, p[1:]):
                self.assertGreater(math.dist(start, end), 0.05)

    def test_connections_are_directed_continuous_and_nonreversing(self):
        lanes = lane_mapping(DATA)
        transitions = 0
        for lane in lanes.values():
            for dst in lane["next_lane_ids"]:
                target = lanes[dst]
                self.assertLess(math.dist(lane["points"][-1], target["points"][0]), 3.5)
                a = [x-y for x,y in zip(lane["points"][-1], lane["points"][-2])]
                b = [x-y for x,y in zip(target["points"][1], target["points"][0])]
                self.assertGreater(sum(x*y for x,y in zip(a,b)) / (math.dist(a, (0,0,0))*math.dist(b, (0,0,0))), -0.35)
                transitions += 1
        self.assertGreater(transitions, 20)
        self.assertNotIn("wb_in", lanes["eb_in"]["next_lane_ids"])

    def test_route_to_merge_and_no_missing_destination(self):
        lanes = lane_mapping(DATA)
        result = route(lanes, "sb_in", "east_turn")
        self.assertIn("feeder", result)
        self.assertEqual((result[0], result[-1]), ("sb_in", "east_turn"))
        self.assertTrue(all(b in lanes[a]["next_lane_ids"] for a,b in zip(result,result[1:])))
        self.assertEqual(route(lanes, "eb_in", "sb_in"), [])

    def test_spawn_16_no_overlap_multi_seed(self):
        for seed in [1, 12, 111, 20261121, 999001]:
            agents = spawn(seed, 16)
            self.assertEqual(len(agents), 16)
            self.assertGreaterEqual(min(math.dist(a[2], b[2]) for i,a in enumerate(agents) for b in agents[i+1:]), 12)
            self.assertEqual(spawn(seed,16), agents)
        self.assertNotEqual(spawn(1,16), spawn(2,16))

    def test_spacing_clamp_kinematics(self):
        # Replicate the swept distance cap used by the simulation, independently
        # of Godot's rendering. Ensure a stopped leader cannot be penetrated.
        gap = 24
        v = 10
        for i in range(600):
            desired = max(0, 0 + (gap - (5.5 + v * 1.4)) * 0.65)
            next_v = max(0, v + max(-4.8, min(2.1, (desired-v)*30)) / 30)
            travel = min((v + next_v) / 60, max(0, gap - 5.5))
            gap -= travel
            self.assertGreaterEqual(gap, 5.5 - 1e-7)
            v = next_v

    def test_fixed_timestep_partition_is_stable(self):
        # The accumulated 30 Hz schedule is frame-partition independent.
        def ticks(dt_values):
            accum = 0
            n = 0
            for dt in dt_values:
                accum += dt
                while accum + 1e-7 >= 1/30:
                    n += 1
                    accum -= 1/30
            return n
        self.assertEqual(ticks([1/30]*1800), 1800)
        self.assertEqual(ticks([1/60]*3600), 1800)


if __name__ == "__main__":
    unittest.main(verbosity=2)
