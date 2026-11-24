"""Bake Aster Valley's local road upgrades from the canonical corridor data."""
import argparse
import json
from pathlib import Path

import numpy as np


def smooth(edge_a, edge_b, value):
    fraction = np.clip((value - edge_a) / (edge_b - edge_a), 0, 1)
    return fraction * fraction * (3 - 2 * fraction)


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("project", type=Path)
parser.add_argument("output", type=Path)
args = parser.parse_args()
project, output = args.project, args.output
output.mkdir(parents=True, exist_ok=True)
data = project / "data/world"
original = np.fromfile(data / "terrain_height_r16le.bin", "<u2").reshape(501, 501) / 100
height = original.copy()
lake = json.loads((project / "content/scenery/lake/water_cells_v1.json").read_text())
lake_cells = {tuple(cell) for cell in lake["cells"]}
graph = json.loads((data / "road_graph_v1.json").read_text())
lanes = {lane["id"]: lane for lane in graph["lanes"]}
x, z = np.meshgrid(np.arange(-1000, 1001, 4), np.arange(-1000, 1001, 4))
grid = np.stack((x, z), axis=-1)
works = {
    "lake_alder": {"name": "Eastwater Viaduct", "center": 79, "width_m": 9.6, "wide_radius": 74,
                   "channel": [[595, 443], [701, 603]], "water_level": 5.35, "bed": 2.1, "channel_radius": 16, "bank": 42},
    "alder_cedar": {"name": "Alder Creek Bridge", "center": 519, "width_m": 9.0, "wide_radius": 74,
                    "channel": [[-870, 137], [-717, 225]], "water_level": 53.4, "bed": 49.6, "channel_radius": 11, "bank": 33},
    "ridge_valley": {"name": "Needle Pass Trestle", "center": 385, "width_m": 9.4, "wide_radius": 95,
                     "channel": [[468, -493], [559, -570]], "water_level": 139.2, "bed": 135.8, "channel_radius": 9, "bank": 31},
    "valley_lake": {"name": "Eastwater Scenic Road", "center": 408, "width_m": 10.2, "wide_radius": 230},
    "market_valley": {"name": "Market Approach", "center": 242, "width_m": 9.6, "wide_radius": 134},
}
waters = []
designed = {}
for corridor, work in works.items():
    pa = np.asarray(lanes[f"lane_{corridor}_ab"]["points"])
    pb = np.asarray(lanes[f"lane_{corridor}_ba"]["points"])[::-1]
    road = (pa + pb) / 2
    distances = np.r_[0, np.cumsum(np.linalg.norm(np.diff(road[:, [0, 2]], axis=0), axis=1))]
    record = {key: work[key] for key in ("name", "center", "width_m", "wide_radius")}
    if "channel" in work:
        a, b = map(np.asarray, work["channel"])
        axis = b - a
        segment = np.clip(np.sum((grid - a) * axis, axis=-1) / np.dot(axis, axis), 0, 1)
        channel_distance = np.linalg.norm(grid - a - segment[..., None] * axis, axis=-1)
        bank = 1 - smooth(work["channel_radius"], work["bank"], channel_distance)
        target = work["bed"] + (0.38 + 0.36 * np.sin(x * 0.083 + z * 0.091)) * segment
        lowered = np.minimum(height, height + (target - height) * bank)
        changed = height - lowered > 0.10
        height = lowered
        wet = changed & (height < work["water_level"] - 0.02)
        cells = wet[:-1, :-1] | wet[1:, :-1] | wet[:-1, 1:] | wet[1:, 1:]
        indices = np.argwhere(cells)[:, ::-1].tolist()
        if work["water_level"] == lake["water_height_m"]:
            indices = [cell for cell in indices if tuple(cell) not in lake_cells]
        waters.append({"height": work["water_level"], "cells": indices})
        ij = np.rint((road[:, [0, 2]] + 1000) / 4).astype(int)
        span = (road[:, 1] - height[ij[:, 1], ij[:, 0]] > 0.52) & (np.abs(distances - work["center"]) < 75)
        span &= (distances > 28) & (distances < distances[-1] - 28)
        if not np.any(span):
            raise ValueError(f"No raised deck on {corridor}")
        indices = np.flatnonzero(span)
        record["bridge_start"] = round(float(distances[indices[0]]), 3)
        record["bridge_end"] = round(float(distances[indices[-1]]), 3)
        record["water_level"] = work["water_level"]
        print(corridor, record["bridge_start"], record["bridge_end"], len(waters[-1]["cells"]))
    designed[corridor] = record

np.round(height * 100).astype("<u2").tofile(output / "terrain_roadworks_r16le.bin")
(output / "roadworks.json").write_text(json.dumps({"roads": designed, "waters": waters}, separators=(",", ":")) + "\n")
