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
    heights = np.fromfile(world / "terrain_height_r16le.bin", dtype="<u2").reshape(501, 501) / 100
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

    def scatter(spacing, probability, valid, pick, size):
        q = np.arange(-982, 983, spacing)
        px, pz = (np.broadcast_to(axis, (len(q),len(q))).copy() for axis in (q[None, :], q[:,None]))
        px += rng.uniform(-0.44, 0.44, px.shape) * spacing
        pz += rng.uniform(-0.44, 0.44, pz.shape) * spacing
        ix = np.clip(np.rint((px + 1000) / 4).astype(int), 0, 500)
        iz = np.clip(np.rint((pz + 1000) / 4).astype(int), 0, 500)
        choose = valid[iz, ix] & (rng.random(ix.shape) < probability[iz, ix])
        px, pz, ix, iz = (v[choose] for v in (px, pz, ix, iz))
        u, v = (px + 1000) / 4, (pz + 1000) / 4
        a, b = u.astype(int), v.astype(int)
        fu, fv = u - a, v - b
        # Same triangle split as the canonical 4 m heightfield.
        nw, ne, sw, se = heights[b, a], heights[b, a+1], heights[b+1, a], heights[b+1, a+1]
        py = np.where(fu >= fv, nw + (ne-nw)*fu + (se-ne)*fv, nw + (se-sw)*fu + (sw-nw)*fv)
        species = pick(iz, ix, len(px))
        return np.column_stack((px, py, pz, rng.uniform(0, 2*np.pi, len(px)),
                                size(species), species, rng.random(len(px))))

    tree_prob = np.clip(0.04 + (0.79 * woods + 0.76 * orchard) * (0.43 + 0.75 * clumps), 0, 0.90)
    trees = scatter(15.0, tree_prob, tall_ok & (slope < 0.64) & (heights < 185),
                    lambda a, b, n: (rng.random(n) < orchard[a, b] / (woods[a,b] + orchard[a,b] + 0.22)).astype(int),
                    lambda kind: rng.uniform(0.95, 2.65, len(kind)) * np.where(kind == 0, 1.38, 1.04))
    verge = np.exp(-clearance / 77)
    grass_prob = np.clip(verge * (0.48 + 0.53 * clumps) + flowers * 0.12 + woods * 0.08, 0, 0.92)
    undergrowth = scatter(3.05, grass_prob, soil_ok & (clearance >= 3.9) & (slope < 0.67),
                          lambda a, b, n: 2 + (rng.random(n) < 0.095 * flowers[a, b] + 0.065 * woods[a, b]).astype(int),
                          lambda kind: rng.uniform(0.68, 1.73, len(kind)))
    rocks = scatter(22.0, (np.clip((slope - 0.33) * 1.7, 0, 0.7) + np.exp(-lake_dist / 25) * 0.32) * clumps,
                    tall_ok & (slope < 1.3), lambda a, b, n: np.full(n, 4),
                    lambda kind: rng.uniform(0.48, 1.88, len(kind)))
    all_placements = np.vstack((trees, undergrowth, rocks)).astype("<f4")
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
