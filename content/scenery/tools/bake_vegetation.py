"""Bake visual-only valley plants and the HUD terrain map from world data.

Requires NumPy, Pillow, and SciPy. Copy vegetation.bin to data/world and
minimap.png to assets/ui/dashboard after regenerating the world.
"""
import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import distance_transform_edt, gaussian_filter
from scipy.spatial import cKDTree


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("project", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    world = args.project / "data/world"
    scenery = args.project / "content/scenery"
    metadata = json.loads((world / "world_metadata_v1.json").read_text())
    graph = json.loads((world / "road_graph_v1.json").read_text())
    canonical = np.fromfile(world / "terrain_height_r16le.bin", dtype="<u2").reshape(501, 501) / 100
    roadworks_path = args.output / "terrain_roadworks_r16le.bin"
    if not roadworks_path.exists():
        roadworks_path = world / roadworks_path.name
    heights = np.fromfile(roadworks_path, dtype="<u2").reshape(501, 501) / 100 if roadworks_path.exists() else canonical
    rng = np.random.default_rng(metadata["seed"])
    coords = np.linspace(-1000, 1000, 501)
    x, z = np.meshgrid(coords, coords)

    def grid_pos(px, pz):
        return ((px + 1000) / 4, (pz + 1000) / 4)

    def grove(px, pz, wide, deep):
        return np.exp(-((x - px) / wide)**2 - ((z - pz) / deep)**2)

    road = Image.new("L", (501, 501))
    road_draw = ImageDraw.Draw(road)
    for lane in graph["lanes"]:
        points = [grid_pos(px, pz) for px, _, pz in lane["points"]]
        road_draw.line(points, fill=255, width=3, joint="curve")
    clearance = distance_transform_edt(np.asarray(road) == 0) * 4
    protected = Image.new("L", road.size)
    canopy = Image.new("L", road.size)
    fern_clearance = Image.new("L", road.size)

    def block(image, px, pz, width):
        cx, cz = grid_pos(px, pz)
        radius = width / 4
        ImageDraw.Draw(image).ellipse((cx-radius, cz-radius, cx+radius, cz+radius), fill=255)

    reservations = json.loads((scenery / "avoidance/race_gate_reservations_v1.json").read_text())
    for zone in reservations["zones"]:
        block(protected, zone["x"], zone["z"], zone["radius_m"] + 3)
    manifest = json.loads((scenery / "manifest.json").read_text())
    buildings = {"house", "barn", "garage", "windmill", "arch", "overlook", "pier", "quarry"}
    for pack_path in (scenery / "packs").glob("*.json"):
        for item in json.loads(pack_path.read_text())["placements"]:
            px, _, pz = item["position"]
            asset = item["asset"]
            radius = float(manifest["assets"][asset]["r"]) * item.get("scale", 1)
            if asset in buildings:
                block(protected, px, pz, max(11, radius + 4))
                block(fern_clearance, px, pz, max(8, radius))
            elif asset in {"pine", "broadleaf", "boulder", "hay"}:
                block(canopy, px, pz, max(6, radius + 3))
    lake = json.loads((scenery / "lake/water_cells_v1.json").read_text())
    wet = np.zeros(heights.shape, dtype=bool)
    for px, pz in lake["cells"]:
        wet[pz:pz + 2, px:px + 2] = True
    works_path = args.output / "roadworks.json"
    if not works_path.exists():
        works_path = world / works_path.name
    roadworks = json.loads(works_path.read_text()) if works_path.exists() else {}
    if roadworks:
        for pool in roadworks["waters"]:
            for px, pz in pool["cells"]:
                wet[pz:pz + 2, px:px + 2] = True
    lake_dist = distance_transform_edt(~wet) * 4
    soil, side = np.gradient(heights, 4)
    slope = np.hypot(soil, side)
    clumps = gaussian_filter(rng.random(heights.shape), 3.0)
    clumps = np.clip((clumps - 0.455) * 10, 0, 1)

    woods = np.clip(0.98 * grove(-735, -300, 445, 535) +
                    0.85 * grove(-365, -650, 300, 265) +
                    0.95 * grove(640, -670, 295, 265) +
                    0.60 * grove(820, 535, 340, 415) +
                    0.62 * grove(-465, 365, 265, 170), 0, 1)
    orchard = np.clip(0.90 * grove(-630, 530, 225, 300) +
                      0.76 * grove(20, 315, 380, 230) +
                      0.82 * grove(488, 450, 220, 300) +
                      0.75 * grove(350, -120, 230, 185), 0, 1)
    flowers = np.maximum(grove(-470, 470, 365, 350), grove(150, 215, 450, 375))
    margin = (np.abs(x) < 980) & (np.abs(z) < 980)
    soil_ok = margin & (heights > 6.0) & (lake_dist >= 4) & (np.asarray(fern_clearance) == 0)
    tall_ok = soil_ok & (np.asarray(protected) == 0) & (clearance >= 7.9) & (np.asarray(canopy) == 0)

    def sample_terrain(px, pz):
        u, v = (px + 1000) / 4, (pz + 1000) / 4
        a, b = u.astype(int), v.astype(int)
        fu, fv = u - a, v - b
        # Same triangle split as the canonical 4 m heightfield.
        nw, ne, sw, se = heights[b, a], heights[b, a+1], heights[b+1, a], heights[b+1, a+1]
        return np.where(fu + fv <= 1, nw + (ne-nw)*fu + (sw-nw)*fv, se + (sw-se)*(1-fu) + (ne-se)*(1-fv))

    def scatter(spacing, probability, valid, pick, size):
        q = np.arange(-982, 983, spacing)
        px, pz = (np.broadcast_to(axis, (len(q),len(q))).copy() for axis in (q[None, :], q[:,None]))
        px += rng.uniform(-0.44, 0.44, px.shape) * spacing
        pz += rng.uniform(-0.44, 0.44, pz.shape) * spacing
        ix = np.clip(np.rint((px + 1000) / 4).astype(int), 0, 500)
        iz = np.clip(np.rint((pz + 1000) / 4).astype(int), 0, 500)
        choose = valid[iz, ix] & (rng.random(ix.shape) < probability[iz, ix])
        px, pz, ix, iz = (v[choose] for v in (px, pz, ix, iz))
        species = pick(iz, ix, len(px))
        return np.column_stack((px, sample_terrain(px, pz), pz, rng.uniform(0, 2*np.pi, len(px)),
                                size(species), species, rng.random(len(px))))

    tree_prob = np.clip(0.045 + (0.93 * woods + 0.76 * orchard) * (0.44 + 0.79 * clumps), 0, 0.90)
    trees = scatter(14.0, tree_prob, tall_ok & (slope < 0.64) & (heights < 185),
                    lambda a, b, n: (rng.random(n) < orchard[a, b] / (woods[a,b] + orchard[a,b] + 0.22)).astype(int),
                    lambda kind: rng.uniform(0.95, 2.65, len(kind)) * np.where(kind == 0, 1.38, 1.04))
    understory = scatter(8.8, woods * (0.32 + 0.34 * clumps),
                         tall_ok & (woods > 0.52) & (slope < 0.67) & (heights < 167) & (clearance < 205),
                         lambda a, b, n: np.zeros(n), lambda kind: rng.uniform(0.74, 1.82, len(kind)))
    tree_distance, _ = cKDTree(trees[:, [0, 2]]).query(understory[:, [0, 2]])
    trees = np.vstack((trees, understory[tree_distance > 6.4]))
    verge = np.exp(-clearance / 77)
    grass_prob = np.clip(verge * (0.87 + 0.19 * clumps) + flowers * 0.13 + woods * 0.10, 0, 0.97)
    undergrowth = scatter(2.35, grass_prob, soil_ok & (clearance >= 4.3) & (slope < 0.67),
                          lambda a, b, n: 2 + (rng.random(n) < 0.095 * flowers[a, b] + 0.065 * woods[a, b]).astype(int),
                          lambda kind: rng.uniform(0.72, 1.38, len(kind)))
    rocks = scatter(22.0, (np.clip((slope - 0.33) * 1.7, 0, 0.7) + np.exp(-lake_dist / 25) * 0.32) * clumps,
                    tall_ok & (slope < 1.3), lambda a, b, n: np.full(n, 4),
                    lambda kind: rng.uniform(0.48, 1.88, len(kind)))
    lanes = {lane["id"]: lane for lane in graph["lanes"]}
    road_verges = []
    for lane_id, lane in lanes.items():
        opposite = lanes.get(lane_id.removesuffix("_ab") + "_ba")
        if not lane_id.endswith("_ab") or opposite is None:
            continue
        center = (np.asarray(lane["points"]) + np.asarray(opposite["points"])[::-1])[:, [0, 2]] * 0.5
        distances = np.r_[0, np.cumsum(np.linalg.norm(np.diff(center, axis=0), axis=1))]
        length = distances[-1]
        along = np.arange(33, length - 33, 1.55)
        along += rng.uniform(-0.65, 0.65, len(along))
        east = np.interp(along, distances, center[:, 0])
        north = np.interp(along, distances, center[:, 1])
        move = np.column_stack((np.gradient(east), np.gradient(north))) if len(along) > 1 else None
        if move is None:
            continue
        across = np.column_stack((-move[:, 1], move[:, 0])) / np.linalg.norm(move, axis=1)[:, None]
        width = np.full(len(along), float(lane["width_m"]))
        design = roadworks.get("roads", {}).get(lane["road_id"], {})
        eligible = np.ones(len(along), dtype=bool)
        if design:
            radius = design["wide_radius"]
            factor = np.clip((radius - np.abs(along - design["center"])) / (radius * 0.52), 0, 1)
            end_factor = np.clip((np.minimum(along, length - along) - 18) / 19, 0, 1)
            width += (design["width_m"] * 0.5 - width) * factor**2 * (3 - 2 * factor) * end_factor**2 * (3 - 2 * end_factor)
            if "bridge_start" in design:
                eligible &= (along < design["bridge_start"] - 5) | (along > design["bridge_end"] + 5)
            if "support_start" in design:
                eligible &= (along < design["support_start"] - 5) | (along > design["support_end"] + 5)
        network = roadworks.get("network_upgrade", {})
        target = network.get("widths_m", {}).get(lane["road_id"], float(lane["width_m"]) * 2) * 0.5
        factor = np.clip((np.minimum(along, length - along) - 6) / 28, 0, 1)
        factor = factor**2 * (3 - 2 * factor)
        if "bridge_start" in design:
            gap = np.maximum(design["bridge_start"] - along, along - design["bridge_end"])
            taper = np.clip(gap / 28, 0, 1)
            factor *= taper**2 * (3 - 2 * taper)
        width += (np.maximum(width, target) - width) * factor
        shoulder = 1.35 + (network.get(lane["surface"] + "_shoulder_m", 1.35) - 1.35) * factor
        for side in [-1, 1]:
            offset = (width + shoulder + rng.uniform(2.0, 4.1, len(along))) * side
            px, pz = east + across[:, 0] * offset, north + across[:, 1] * offset
            ix = np.clip(np.rint((px + 1000) / 4).astype(int), 0, 500)
            iz = np.clip(np.rint((pz + 1000) / 4).astype(int), 0, 500)
            visible = eligible & soil_ok[iz, ix] & (np.asarray(protected)[iz, ix] == 0) & (slope[iz, ix] < 0.62)
            px, pz = px[visible], pz[visible]
            count = len(px)
            road_verges.append(np.column_stack((px, sample_terrain(px, pz), pz, rng.uniform(0, 2*np.pi, count),
                                               rng.uniform(0.68, 0.99, count), np.full(count, 2), rng.random(count))))
    all_placements = np.vstack((trees, undergrowth, rocks, *road_verges)).astype("<f4")
    all_placements.tofile(args.output / "vegetation.bin")
    print(f"Plants by class [pine, broadleaf, grass, flowers/fern, rock] {np.bincount(all_placements[:, 5].astype(int))}")

    road_map(args.output, graph, metadata, heights, wet)


def road_map(out, graph, metadata, heights, wet):
    size = 2048
    masks = [Image.new("L", (size, size)) for _ in range(2)]
    pen = [ImageDraw.Draw(mask) for mask in masks]
    main_loop = metadata["main_touring_loop"]
    for lane in graph["lanes"]:
        points = [((x + 1000) * size / 2000, (z + 1000) * size / 2000) for x, _, z in lane["points"]]
        index = int(lane["road_id"] in main_loop)
        pen[index].line(points, fill=255, width=9 if index else 6, joint="curve")
    # The alpha channel stores height. Data is sampled directly and never used as transparency.
    relief = Image.fromarray(np.uint8(21 + np.clip(heights / 235, 0, 1) * 234))
    water = Image.fromarray(np.uint8(wet) * 255)
    channels = masks + [water.resize((size, size), Image.Resampling.BILINEAR),
                        relief.resize((size, size), Image.Resampling.BILINEAR)]
    Image.merge("RGBA", channels).save(out / "minimap.png", optimize=True)


if __name__ == "__main__":
    main()
