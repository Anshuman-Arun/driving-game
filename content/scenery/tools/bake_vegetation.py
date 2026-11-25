"""Bake deterministic multi-species valley vegetation and HUD terrain map.

Requires NumPy, Pillow, and SciPy. Writes vegetation.bin (STRIDE=8 float32) and
minimap.png to the output directory.
"""
import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import distance_transform_edt, gaussian_filter
from scipy.spatial import cKDTree

# Species IDs shared with scripts/integration/valley_vegetation.gd
KIND_CONIFER_TALL = 0
KIND_BROADLEAF_OAK = 1
KIND_GRASS_MEADOW = 2
KIND_WILDFLOWER = 3
KIND_ROCK = 4
KIND_CONIFER_MEDIUM = 5
KIND_BROADLEAF_BIRCH = 6
KIND_SAPLING_CONIFER = 7
KIND_GRASS_SHORT = 8
KIND_GRASS_TALL_VERGE = 9
KIND_FERN = 10
KIND_SHRUB_WOODLAND = 11

SHOULDER_M = 1.35
SHOWCASE_CORRIDORS = {
    "alder_cedar": (590.0, 1200.0),
    "cedar_ridge": (0.0, 230.0),
    "cedar_pine": (0.0, 210.0),
}


def _smoothstep(edge0: float, edge1: float, x: np.ndarray) -> np.ndarray:
    t = np.clip((x - edge0) / max(edge1 - edge0, 1e-6), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def _road_half_width(base: float, design: dict, station: np.ndarray, full_len: float) -> np.ndarray:
    w = np.full_like(station, float(base), dtype=np.float64)
    if not design:
        return w
    radius = float(design["wide_radius"])
    taper = 1.0 - _smoothstep(radius * 0.48, radius, np.abs(station - float(design["center"])))
    taper *= _smoothstep(18.0, 37.0, np.minimum(station, full_len - station))
    return w + (float(design["width_m"]) * 0.5 - w) * taper


def _convex_hull_2d(pts: np.ndarray) -> np.ndarray:
    """Andrew's monotone chain convex hull in 2D, matching mesh_builder.gd."""
    if len(pts) < 3:
        return pts
    order = np.lexsort((pts[:, 1], pts[:, 0]))
    pts = pts[order]
    unique = [pts[0]]
    for p in pts[1:]:
        if p[0] != unique[-1][0] or p[1] != unique[-1][1]:
            unique.append(p)
    if len(unique) < 3:
        return np.asarray(unique)

    def cross(a, b, o):
        return (b[0] - a[0]) * (o[1] - a[1]) - (b[1] - a[1]) * (o[0] - a[0])

    lower = []
    for p in unique:
        while len(lower) > 1 and cross(lower[-2], lower[-1], p) <= 0.0:
            lower.pop()
        lower.append(p)
    upper = []
    for p in reversed(unique):
        while len(upper) > 1 and cross(upper[-2], upper[-1], p) <= 0.0:
            upper.pop()
        upper.append(p)
    return np.asarray(lower[:-1] + upper[:-1])


def _pad_points_for_turn(lane: dict) -> np.ndarray:
    pts = np.asarray(lane["points"], dtype=np.float64)[:, [0, 2]]
    reach = float(lane["width_m"]) * 0.5 + 3.0
    out = []
    n = len(pts)
    for i in range(n):
        before = pts[max(i - 1, 0)]
        after = pts[min(i + 1, n - 1)]
        d = after - before
        norm = np.hypot(d[0], d[1])
        if norm > 1e-6:
            d /= norm
        normal = np.array([-d[1], d[0]]) * reach
        c = pts[i]
        out.extend([
            c + normal,
            c - normal,
            c + np.array([reach, 0.0]),
            c - np.array([reach, 0.0]),
            c + np.array([0.0, reach]),
            c - np.array([0.0, reach]),
        ])
    return np.asarray(out)


def _hull_signed_distance(hull: np.ndarray, pts: np.ndarray) -> np.ndarray:
    """Exact signed distance to a CCW convex polygon (<0 inside, >0 outside)."""
    n = len(hull)
    v0 = hull
    v1 = np.roll(hull, -1, axis=0)
    edges = v1 - v0
    edge_len_sq = np.sum(edges * edges, axis=1)
    # Vectorized over points (M, 2) against edges (N, 2)
    diff = pts[:, None, :] - v0[None, :, :]
    t = np.clip(np.sum(diff * edges[None, :, :], axis=2) / np.maximum(edge_len_sq[None, :], 1e-9), 0.0, 1.0)
    proj = v0[None, :, :] + t[:, :, None] * edges[None, :, :]
    dist = np.linalg.norm(pts[:, None, :] - proj, axis=2).min(axis=1)
    # Inside check via cross products (Andrew's hull is CCW in standard XY, check sign)
    cross = edges[None, :, 0] * diff[:, :, 1] - edges[None, :, 1] * diff[:, :, 0]
    inside = np.all(cross >= -1e-6, axis=1) | np.all(cross <= 1e-6, axis=1)
    return np.where(inside, -dist, dist)


class RoadClearanceModel:
    """Exact vector road + shoulder + junction pad + bridge + showcase distance evaluator."""

    def __init__(self, graph: dict, roadworks: dict):
        lanes = {lane["id"]: lane for lane in graph["lanes"]}
        sample_pts = []
        sample_edge_r = []
        sample_bridge = []
        showcase_pts = []

        self.corridors = []
        for lane_id, lane in lanes.items():
            if not lane_id.endswith("_ab"):
                continue
            opp = lanes.get(lane_id.removesuffix("_ab") + "_ba")
            if opp is None:
                continue
            road_id = lane["road_id"]
            center = (np.asarray(lane["points"], dtype=np.float64) + np.asarray(opp["points"], dtype=np.float64)[::-1])[:, [0, 2]] * 0.5
            seg_lens = np.linalg.norm(np.diff(center, axis=0), axis=1)
            cum_s = np.r_[0.0, np.cumsum(seg_lens)]
            full_len = float(cum_s[-1])
            design = roadworks.get("roads", {}).get(road_id, {})
            base_hw = float(lane["width_m"])

            # Dense 0.8 m resampling for exact sub-meter distance queries
            n_dense = max(int(np.ceil(full_len / 0.8)) + 1, 2)
            s_dense = np.linspace(0.0, full_len, n_dense)
            px = np.interp(s_dense, cum_s, center[:, 0])
            pz = np.interp(s_dense, cum_s, center[:, 1])
            pts_dense = np.column_stack((px, pz))
            hw = _road_half_width(base_hw, design, s_dense, full_len)
            edge_r = hw + SHOULDER_M
            is_bridge = np.zeros(n_dense, dtype=bool)
            if "bridge_start" in design:
                b0 = float(design["bridge_start"]) - 7.5
                b1 = float(design["bridge_end"]) + 7.5
                is_bridge = (s_dense >= b0) & (s_dense <= b1)

            sample_pts.append(pts_dense)
            sample_edge_r.append(edge_r)
            sample_bridge.append(is_bridge)

            if road_id in SHOWCASE_CORRIDORS:
                s0, s1 = SHOWCASE_CORRIDORS[road_id]
                mask = (s_dense >= s0) & (s_dense <= s1)
                if np.any(mask):
                    showcase_pts.append(pts_dense[mask])

            self.corridors.append({
                "road_id": road_id,
                "center": center,
                "cum_s": cum_s,
                "full_len": full_len,
                "base_hw": base_hw,
                "design": design,
            })

        self.road_pts = np.vstack(sample_pts)
        self.road_edge_r = np.concatenate(sample_edge_r)
        self.road_bridge = np.concatenate(sample_bridge)
        self.road_tree = cKDTree(self.road_pts)

        bridge_pts = self.road_pts[self.road_bridge]
        self.bridge_tree = cKDTree(bridge_pts) if len(bridge_pts) else None

        sc_pts = np.vstack(showcase_pts) if showcase_pts else np.array([[-870.0, -154.0]])
        self.showcase_tree = cKDTree(sc_pts)

        # Build exact junction convex hulls matching mesh_builder.gd
        turn_groups: dict[str, list[np.ndarray]] = {}
        for lid, lane in lanes.items():
            if not lid.startswith("turn_"):
                continue
            parts = lid.split("_")
            if len(parts) < 3:
                continue
            turn_groups.setdefault(parts[1], []).append(_pad_points_for_turn(lane))
        self.hulls = []
        for pts_list in turn_groups.values():
            hull = _convex_hull_2d(np.vstack(pts_list))
            bmin = hull.min(axis=0)
            bmax = hull.max(axis=0)
            self.hulls.append((hull, bmin, bmax))

    def evaluate(self, px: np.ndarray, pz: np.ndarray):
        """Return (road_edge_dist, centerline_dist, bridge_dist, showcase_dist)."""
        pts = np.column_stack((px, pz))
        center_dist, idx = self.road_tree.query(pts)
        edge_dist = center_dist - self.road_edge_r[idx]

        # Refine against convex junction pads for points near any junction bbox
        for hull, bmin, bmax in self.hulls:
            near = (
                (px >= bmin[0] - 20.0) & (px <= bmax[0] + 20.0) &
                (pz >= bmin[1] - 20.0) & (pz <= bmax[1] + 20.0)
            )
            if np.any(near):
                h_dist = _hull_signed_distance(hull, pts[near])
                edge_dist[near] = np.minimum(edge_dist[near], h_dist)

        if self.bridge_tree is not None:
            bridge_dist, _ = self.bridge_tree.query(pts)
        else:
            bridge_dist = np.full(len(pts), 1e6)

        showcase_dist, _ = self.showcase_tree.query(pts)
        return edge_dist, center_dist, bridge_dist, showcase_dist


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
    canonical = np.fromfile(world / "terrain_height_r16le.bin", dtype="<u2").reshape(501, 501) / 100.0
    roadworks_path = args.output / "terrain_roadworks_r16le.bin"
    if not roadworks_path.exists():
        roadworks_path = world / roadworks_path.name
    heights = np.fromfile(roadworks_path, dtype="<u2").reshape(501, 501) / 100.0 if roadworks_path.exists() else canonical

    works_path = args.output / "roadworks.json"
    if not works_path.exists():
        works_path = world / works_path.name
    roadworks = json.loads(works_path.read_text()) if works_path.exists() else {}

    rng = np.random.default_rng(metadata["seed"])
    coords = np.linspace(-1000.0, 1000.0, 501)
    gx, gz = np.meshgrid(coords, coords)

    def grove(px: float, pz: float, wide: float, deep: float) -> np.ndarray:
        return np.exp(-((gx - px) / wide) ** 2 - ((gz - pz) / deep) ** 2)

    # Water mask (Eastwater lake + roadworks creeks)
    lake = json.loads((scenery / "lake/water_cells_v1.json").read_text())
    wet = np.zeros(heights.shape, dtype=bool)
    for px, pz in lake["cells"]:
        wet[pz:pz + 2, px:px + 2] = True
    if roadworks:
        for pool in roadworks.get("waters", []):
            for px, pz in pool["cells"]:
                wet[pz:pz + 2, px:px + 2] = True
    lake_dist = distance_transform_edt(~wet) * 4.0

    # Building, race-gate & SceneryRuntime prop exclusion trees/masks
    reservations = json.loads((scenery / "avoidance/race_gate_reservations_v1.json").read_text())
    manifest = json.loads((scenery / "manifest.json").read_text())
    buildings = {"house", "barn", "garage", "windmill", "arch", "overlook", "pier", "quarry"}

    build_pts = []
    build_rad = []
    for zone in reservations["zones"]:
        build_pts.append([zone["x"], zone["z"]])
        build_rad.append(float(zone["radius_m"]) + 3.5)

    scenery_prop_pts = []
    scenery_prop_rad = []
    for pack_path in sorted((scenery / "packs").glob("*.json")):
        for item in json.loads(pack_path.read_text())["placements"]:
            px, _, pz = item["position"]
            asset = item["asset"]
            rad = float(manifest["assets"][asset]["r"]) * float(item.get("scale", 1.0))
            if asset in buildings:
                build_pts.append([px, pz])
                build_rad.append(max(10.0, rad + 4.0))
            elif asset in {"pine", "broadleaf", "boulder", "hay", "shrub", "rock"}:
                scenery_prop_pts.append([px, pz])
                scenery_prop_rad.append(max(3.5, rad + 1.8))

    build_pts_arr = np.asarray(build_pts, dtype=np.float64)
    build_rad_arr = np.asarray(build_rad, dtype=np.float64)
    build_tree = cKDTree(build_pts_arr)
    max_build_rad = float(build_rad_arr.max()) if len(build_rad_arr) else 0.0

    prop_pts_arr = np.asarray(scenery_prop_pts, dtype=np.float64)
    prop_rad_arr = np.asarray(scenery_prop_rad, dtype=np.float64)
    prop_tree = cKDTree(prop_pts_arr) if len(prop_pts_arr) else None
    max_prop_rad = float(prop_rad_arr.max()) if len(prop_rad_arr) else 0.0

    # Terrain slope & multi-scale organic noise fields
    dz, dx = np.gradient(heights, 4.0)
    slope_grid = np.hypot(dx, dz)

    noise_macro = gaussian_filter(rng.random(heights.shape), 6.5)
    noise_macro = (noise_macro - noise_macro.min()) / max(noise_macro.max() - noise_macro.min(), 1e-6)
    noise_clump = gaussian_filter(rng.random(heights.shape), 2.4)
    noise_clump = (noise_clump - noise_clump.min()) / max(noise_clump.max() - noise_clump.min(), 1e-6)
    clumps = np.clip(0.55 * noise_clump + 0.45 * noise_macro, 0.0, 1.0)
    clearings = np.clip((noise_clump - 0.34) * 2.2, 0.0, 1.0)

    # Biome envelopes: strong Cedar Woods hillside coverage on BOTH sides of (-870, -154)
    woods = np.clip(
        0.95 * grove(-885, -165, 290, 320) +
        0.95 * grove(-720, -310, 420, 480) +
        0.85 * grove(-365, -650, 320, 275) +
        0.95 * grove(640, -670, 305, 275) +
        0.62 * grove(820, 535, 340, 415) +
        0.65 * grove(-465, 365, 275, 180),
        0.0, 1.0,
    )
    orchard = np.clip(
        0.92 * grove(-630, 530, 230, 305) +
        0.78 * grove(20, 315, 390, 240) +
        0.84 * grove(488, 450, 230, 305) +
        0.76 * grove(350, -120, 240, 195),
        0.0, 1.0,
    )
    flowers = np.maximum(grove(-470, 470, 365, 350), grove(150, 215, 450, 375))

    road_model = RoadClearanceModel(graph, roadworks)

    def sample_grid(field: np.ndarray, px: np.ndarray, pz: np.ndarray) -> np.ndarray:
        u = np.clip((px + 1000.0) / 4.0, 0.0, 499.999)
        v = np.clip((pz + 1000.0) / 4.0, 0.0, 499.999)
        a = u.astype(int)
        b = v.astype(int)
        fu = u - a
        fv = v - b
        nw, ne, sw, se = field[b, a], field[b, a + 1], field[b + 1, a], field[b + 1, a + 1]
        return np.where(fu + fv <= 1.0, nw + (ne - nw) * fu + (sw - nw) * fv, se + (sw - se) * (1.0 - fu) + (ne - se) * (1.0 - fv))

    def building_blocked(px: np.ndarray, pz: np.ndarray, extra_pad: float = 0.0) -> np.ndarray:
        pts = np.column_stack((px, pz))
        d, idx = build_tree.query(pts)
        return d < (build_rad_arr[idx] + extra_pad)

    def prop_blocked(px: np.ndarray, pz: np.ndarray, extra_pad: float = 0.0) -> np.ndarray:
        if prop_tree is None:
            return np.zeros(len(px), dtype=bool)
        pts = np.column_stack((px, pz))
        d, idx = prop_tree.query(pts)
        return d < (prop_rad_arr[idx] + extra_pad)

    def grid_candidates(spacing: float, xmin=-980.0, xmax=980.0, zmin=-980.0, zmax=980.0):
        qx = np.arange(xmin, xmax + 0.01, spacing)
        qz = np.arange(zmin, zmax + 0.01, spacing)
        px, pz = np.meshgrid(qx, qz)
        px = px.ravel() + rng.uniform(-0.43, 0.43, px.size) * spacing
        pz = pz.ravel() + rng.uniform(-0.43, 0.43, pz.size) * spacing
        in_bounds = (np.abs(px) < 980.0) & (np.abs(pz) < 980.0)
        return px[in_bounds], pz[in_bounds]

    def build_rows(px, pz, y, yaw, scale, kind, warmth):
        n = len(px)
        if n == 0:
            return np.empty((0, 8), dtype="<f4")
        return np.column_stack((
            px, y, pz, yaw, scale, kind, rng.random(n), np.clip(warmth, 0.0, 1.0)
        )).astype("<f4")

    all_batches = []

    # =========================================================================
    # 1. CANOPY TREES — Cedar Woods Showcase (dense multi-species) + Valley
    # =========================================================================
    # 1a. Showcase canopy ([-1000, -440] x [-520, 100], filtered to showcase_dist <= 165m)
    sx, sz = grid_candidates(6.8, -980.0, -440.0, -520.0, 110.0)
    s_edge, s_center, s_bridge, s_show = road_model.evaluate(sx, sz)
    s_h = sample_grid(heights, sx, sz)
    s_slope = sample_grid(slope_grid, sx, sz)
    s_lake = sample_grid(lake_dist, sx, sz)
    s_clump = sample_grid(clumps, sx, sz)
    s_clear = sample_grid(clearings, sx, sz)

    valid_sc_tree = (
        (s_show <= 165.0)
        & (s_edge >= 4.4)
        & (s_center >= 8.2)
        & (s_bridge >= 10.0)
        & (s_h > 6.0) & (s_h < 185.0)
        & (s_lake >= 5.0)
        & (s_slope < 0.70)
        & ~building_blocked(sx, sz, 1.5)
        & ~prop_blocked(sx, sz, 1.8)
    )
    # Organic grove clustering with small sunlit clearings
    sc_tree_prob = np.clip(0.32 + 0.60 * s_clear + 0.14 * np.exp(-s_edge / 24.0), 0.0, 0.88)
    keep_sc_tree = valid_sc_tree & (rng.random(len(sx)) < sc_tree_prob)
    tx, tz = sx[keep_sc_tree], sz[keep_sc_tree]
    th = s_h[keep_sc_tree]
    tslope = s_slope[keep_sc_tree]
    tedge = s_edge[keep_sc_tree]
    tclump = s_clump[keep_sc_tree]

    # Enforce minimum trunk separation (~4.6 m) so crowns overlap without trunks clipping
    if len(tx) > 1:
        t_pts = np.column_stack((tx, tz))
        t_keep = np.ones(len(tx), dtype=bool)
        t_tree = cKDTree(t_pts)
        pairs = t_tree.query_pairs(4.7)
        for i, j in pairs:
            if t_keep[i] and t_keep[j]:
                t_keep[j] = False
        tx, tz, th, tslope, tedge, tclump = (
            tx[t_keep], tz[t_keep], th[t_keep], tslope[t_keep], tedge[t_keep], tclump[t_keep]
        )

    n_sc = len(tx)
    r_sp = rng.random(n_sc)
    # Roadside/lower edges have slightly more birch/oak; deeper/steeper slopes have tall/medium conifers
    edge_mix = np.exp(-tedge / 28.0)
    p_oak = 0.08 + 0.09 * edge_mix * (1.0 - tslope)
    p_birch = 0.11 + 0.11 * edge_mix
    p_med = 0.30
    sc_kind = np.where(
        r_sp < p_oak, KIND_BROADLEAF_OAK,
        np.where(r_sp < p_oak + p_birch, KIND_BROADLEAF_BIRCH,
                 np.where(r_sp < p_oak + p_birch + p_med, KIND_CONIFER_MEDIUM, KIND_CONIFER_TALL))
    )
    sc_scale = rng.uniform(0.84, 1.20, n_sc)
    sc_ty = th - (0.08 + tslope * 0.24)
    sc_warmth = np.clip(0.15 + 0.35 * tclump + (th - 60.0) * 0.002, 0.0, 1.0)
    all_batches.append(build_rows(tx, tz, sc_ty, rng.uniform(0.0, 2.0 * np.pi, n_sc), sc_scale, sc_kind, sc_warmth))

    # 1b. World-wide canopy trees outside showcase (showcase_dist > 165 m)
    wx, wz = grid_candidates(11.5)
    w_edge, w_center, w_bridge, w_show = road_model.evaluate(wx, wz)
    w_h = sample_grid(heights, wx, wz)
    w_slope = sample_grid(slope_grid, wx, wz)
    w_lake = sample_grid(lake_dist, wx, wz)
    w_woods = sample_grid(woods, wx, wz)
    w_orchard = sample_grid(orchard, wx, wz)
    w_clump = sample_grid(clumps, wx, wz)

    valid_w_tree = (
        (w_show > 165.0)
        & (w_edge >= 4.8)
        & (w_center >= 8.5)
        & (w_bridge >= 10.0)
        & (w_h > 6.2) & (w_h < 185.0)
        & (w_lake >= 5.0)
        & (w_slope < 0.66)
        & ~building_blocked(wx, wz, 1.5)
        & ~prop_blocked(wx, wz, 1.8)
    )
    w_prob = np.clip(0.05 + (0.85 * w_woods + 0.72 * w_orchard) * (0.38 + 0.65 * w_clump), 0.0, 0.86)
    keep_w = valid_w_tree & (rng.random(len(wx)) < w_prob)
    wtx, wtz = wx[keep_w], wz[keep_w]
    wth = w_h[keep_w]
    wtslope = w_slope[keep_w]
    wtwoods = w_woods[keep_w]
    wtorch = w_orchard[keep_w]
    wtclump = w_clump[keep_w]
    n_wt = len(wtx)
    rw = rng.random(n_wt)
    broad_ratio = wtorch / (wtwoods + wtorch + 0.25)
    is_broad = rw < broad_ratio
    rw2 = rng.random(n_wt)
    wt_kind = np.where(
        is_broad,
        np.where(rw2 < 0.62, KIND_BROADLEAF_OAK, KIND_BROADLEAF_BIRCH),
        np.where(rw2 < 0.62, KIND_CONIFER_TALL, KIND_CONIFER_MEDIUM),
    )
    wt_scale = rng.uniform(0.84, 1.20, n_wt)
    wt_y = wth - (0.08 + wtslope * 0.24)
    wt_warmth = np.clip(0.18 + 0.40 * wtclump + 0.25 * broad_ratio, 0.0, 1.0)
    all_batches.append(build_rows(wtx, wtz, wt_y, rng.uniform(0.0, 2.0 * np.pi, n_wt), wt_scale, wt_kind, wt_warmth))

    # Build combined tree trunk KDTree for sapling / shrub / fern spacing
    all_tree_xy = np.vstack((np.column_stack((tx, tz)), np.column_stack((wtx, wtz))))
    all_tree_tree = cKDTree(all_tree_xy) if len(all_tree_xy) else None

    def dist_to_canopy(px: np.ndarray, pz: np.ndarray) -> np.ndarray:
        if all_tree_tree is None:
            return np.full(len(px), 999.0)
        d, _ = all_tree_tree.query(np.column_stack((px, pz)))
        return d

    # =========================================================================
    # 2. SAPLINGS & WOODLAND SHRUBS (Multi-tier understory)
    # =========================================================================
    # 2a. Conifer saplings (showcase dense + forest edges worldwide)
    apx, apz = grid_candidates(4.4, -980.0, -440.0, -520.0, 110.0)
    a_edge, _, a_bridge, a_show = road_model.evaluate(apx, apz)
    a_h = sample_grid(heights, apx, apz)
    a_slope = sample_grid(slope_grid, apx, apz)
    a_lake = sample_grid(lake_dist, apx, apz)
    a_clump = sample_grid(clumps, apx, apz)
    a_canopy = dist_to_canopy(apx, apz)
    valid_sap = (
        (a_show <= 145.0)
        & (a_edge >= 3.3)
        & (a_bridge >= 8.0)
        & (a_h > 6.0) & (a_h < 180.0)
        & (a_lake >= 4.0)
        & (a_slope < 0.72)
        & (a_canopy >= 2.6)
        & ~building_blocked(apx, apz, 1.0)
        & ~prop_blocked(apx, apz, 1.2)
    )
    sap_prob = np.clip(0.18 + 0.34 * a_clump + 0.18 * np.exp(-a_edge / 22.0), 0.0, 0.65)
    keep_sap = valid_sap & (rng.random(len(apx)) < sap_prob)
    n_sap = int(keep_sap.sum())
    sap_scale = rng.uniform(0.76, 1.22, n_sap)
    sap_y = a_h[keep_sap] - (0.04 + a_slope[keep_sap] * 0.14)
    all_batches.append(build_rows(
        apx[keep_sap], apz[keep_sap], sap_y,
        rng.uniform(0.0, 2.0 * np.pi, n_sap), sap_scale,
        np.full(n_sap, KIND_SAPLING_CONIFER), a_clump[keep_sap] * 0.6
    ))

    # 2b. Woodland shrubs (showcase dense + valley forest edges)
    shx, shz = grid_candidates(2.7, -980.0, -440.0, -520.0, 110.0)
    sh_edge, _, sh_bridge, sh_show = road_model.evaluate(shx, shz)
    sh_h = sample_grid(heights, shx, shz)
    sh_slope = sample_grid(slope_grid, shx, shz)
    sh_lake = sample_grid(lake_dist, shx, shz)
    sh_clump = sample_grid(clumps, shx, shz)
    sh_canopy = dist_to_canopy(shx, shz)
    valid_sh = (
        (sh_show <= 125.0)
        & (sh_edge >= 2.1)
        & (sh_bridge >= 7.0)
        & (sh_h > 6.0) & (sh_h < 175.0)
        & (sh_lake >= 3.5)
        & (sh_slope < 0.74)
        & (sh_canopy >= 1.7)
        & ~building_blocked(shx, shz, 0.5)
        & ~prop_blocked(shx, shz, 0.8)
    )
    sh_prob = np.clip(0.16 + 0.42 * sh_clump + 0.18 * np.exp(-sh_edge / 18.0), 0.0, 0.72)
    keep_sh = valid_sh & (rng.random(len(shx)) < sh_prob)
    n_sh = int(keep_sh.sum())
    sh_scale = rng.uniform(0.76, 1.24, n_sh)
    sh_y = sh_h[keep_sh] - (0.03 + sh_slope[keep_sh] * 0.10)
    all_batches.append(build_rows(
        shx[keep_sh], shz[keep_sh], sh_y,
        rng.uniform(0.0, 2.0 * np.pi, n_sh), sh_scale,
        np.full(n_sh, KIND_SHRUB_WOODLAND), 0.15 + 0.5 * sh_clump[keep_sh]
    ))

    # Valley-wide shrubs & saplings outside showcase
    vshx, vshz = grid_candidates(8.5)
    vs_edge, _, vs_bridge, vs_show = road_model.evaluate(vshx, vshz)
    vs_h = sample_grid(heights, vshx, vshz)
    vs_slope = sample_grid(slope_grid, vshx, vshz)
    vs_lake = sample_grid(lake_dist, vshx, vshz)
    vs_woods = sample_grid(woods, vshx, vshz)
    vs_orch = sample_grid(orchard, vshx, vshz)
    vs_clump = sample_grid(clumps, vshx, vshz)
    vs_canopy = dist_to_canopy(vshx, vshz)
    valid_vs = (
        (vs_show > 125.0)
        & (vs_edge >= 2.8)
        & (vs_bridge >= 7.0)
        & (vs_h > 6.0) & (vs_h < 175.0)
        & (vs_lake >= 3.5)
        & (vs_slope < 0.70)
        & (vs_canopy >= 2.2)
        & ~building_blocked(vshx, vshz, 0.5)
        & ~prop_blocked(vshx, vshz, 1.0)
    )
    vs_prob = np.clip((0.45 * vs_woods + 0.30 * vs_orch + 0.25 * np.exp(-vs_edge / 26.0)) * (0.4 + 0.7 * vs_clump), 0.0, 0.72)
    keep_vs = valid_vs & (rng.random(len(vshx)) < vs_prob)
    n_vs = int(keep_vs.sum())
    vs_is_sap = (rng.random(n_vs) < 0.35 * vs_woods[keep_vs])
    vs_kind = np.where(vs_is_sap, KIND_SAPLING_CONIFER, KIND_SHRUB_WOODLAND)
    vs_scale = rng.uniform(0.78, 1.20, n_vs)
    vs_y = vs_h[keep_vs] - (0.04 + vs_slope[keep_vs] * 0.11)
    all_batches.append(build_rows(
        vshx[keep_vs], vshz[keep_vs], vs_y,
        rng.uniform(0.0, 2.0 * np.pi, n_vs), vs_scale,
        vs_kind, 0.2 + 0.5 * vs_clump[keep_vs]
    ))

    # =========================================================================
    # 3. ROCKS / BOULDERS (Slope-grounded, never perched on cliffs)
    # =========================================================================
    rx, rz = grid_candidates(13.5)
    r_edge, _, r_bridge, r_show = road_model.evaluate(rx, rz)
    r_h = sample_grid(heights, rx, rz)
    r_slope = sample_grid(slope_grid, rx, rz)
    r_lake = sample_grid(lake_dist, rx, rz)
    r_clump = sample_grid(clumps, rx, rz)
    valid_rk = (
        (r_edge >= 3.2)
        & (r_bridge >= 8.0)
        & (r_h > 6.2)
        & (r_lake >= 3.5)
        & (r_slope < 0.68)
        & ~building_blocked(rx, rz, 1.2)
        & ~prop_blocked(rx, rz, 1.5)
    )
    rk_prob = np.clip(
        (np.clip((r_slope - 0.18) * 1.4, 0.0, 0.55) + np.exp(-r_lake / 22.0) * 0.35 + np.where(r_show <= 130.0, 0.18, 0.0)) * r_clump,
        0.0, 0.65
    )
    keep_rk = valid_rk & (rng.random(len(rx)) < rk_prob)
    n_rk = int(keep_rk.sum())
    rk_scale = rng.uniform(0.45, 1.38, n_rk)
    # Sink boulders firmly into slope so downhill side never floats
    rk_y = r_h[keep_rk] - (0.20 * rk_scale + r_slope[keep_rk] * 0.18)
    all_batches.append(build_rows(
        rx[keep_rk], rz[keep_rk], rk_y,
        rng.uniform(0.0, 2.0 * np.pi, n_rk), rk_scale,
        np.full(n_rk, KIND_ROCK), r_clump[keep_rk] * 0.5
    ))

    # =========================================================================
    # 4. DENSE ROADSIDE VERGE GRASS STRIPS (0.35–0.6 m spacing in Showcase!)
    # =========================================================================
    for corr in road_model.corridors:
        road_id = corr["road_id"]
        center = corr["center"]
        cum_s = corr["cum_s"]
        full_len = corr["full_len"]
        base_hw = corr["base_hw"]
        design = corr["design"]
        is_showcase = road_id in SHOWCASE_CORRIDORS
        sc_s0, sc_s1 = SHOWCASE_CORRIDORS.get(road_id, (1e9, -1e9))

        # Dense 0.42 m along-road spacing in showcase, 1.05 m elsewhere
        s_step = 0.42 if is_showcase else 1.05
        along = np.arange(26.0, max(full_len - 26.0, 27.0), s_step)
        if len(along) < 2:
            continue
        along += rng.uniform(-0.42, 0.42, len(along)) * s_step
        px_c = np.interp(along, cum_s, center[:, 0])
        pz_c = np.interp(along, cum_s, center[:, 1])
        move = np.column_stack((np.gradient(px_c), np.gradient(pz_c)))
        norm = np.maximum(np.linalg.norm(move, axis=1), 1e-6)
        across = np.column_stack((-move[:, 1] / norm, move[:, 0] / norm))
        hw = _road_half_width(base_hw, design, along, full_len)

        in_sc = (along >= sc_s0) & (along <= sc_s1)
        # Showcase gets 4 dense verge bands (0.20..3.6 m outside shoulder); non-showcase gets 2 clean bands
        band_specs = (
            [(0.18, 0.85, True), (0.75, 1.55, False), (1.45, 2.45, False), (2.30, 3.55, False)]
            if is_showcase else
            [(0.22, 1.15, True), (1.10, 2.65, False)]
        )
        for band_min, band_max, inner_band in band_specs:
            for side in (-1.0, 1.0):
                # Subsample non-showcase segment of showcase corridors to keep non-showcase light
                if is_showcase:
                    keep_band = in_sc | (rng.random(len(along)) < (0.42 if inner_band else 0.30))
                else:
                    keep_band = np.ones(len(along), dtype=bool)
                if not np.any(keep_band):
                    continue
                al = along[keep_band]
                hw_k = hw[keep_band]
                ac_k = across[keep_band]
                off = (hw_k + SHOULDER_M + rng.uniform(band_min, band_max, len(al))) * side
                vx = px_c[keep_band] + ac_k[:, 0] * off
                vz = pz_c[keep_band] + ac_k[:, 1] * off

                v_edge, _, v_bridge, _ = road_model.evaluate(vx, vz)
                vh = sample_grid(heights, vx, vz)
                vslope = sample_grid(slope_grid, vx, vz)
                vlake = sample_grid(lake_dist, vx, vz)
                vclump = sample_grid(clumps, vx, vz)
                vflowers = sample_grid(flowers, vx, vz)

                ok = (
                    (np.abs(vx) < 980.0) & (np.abs(vz) < 980.0)
                    & (v_edge >= 0.14)
                    & (v_bridge >= 6.0)
                    & (vh > 6.0)
                    & (vlake >= 3.0)
                    & (vslope < 0.78)
                    & ~building_blocked(vx, vz, 0.2)
                )
                if not np.any(ok):
                    continue
                vx, vz, vh, vslope, vclump, vflowers = (
                    vx[ok], vz[ok], vh[ok], vslope[ok], vclump[ok], vflowers[ok]
                )
                nv = len(vx)
                rv = rng.random(nv)
                if inner_band:
                    vkind = np.where(rv < 0.58, KIND_GRASS_SHORT, np.where(rv < 0.90, KIND_GRASS_MEADOW, KIND_WILDFLOWER))
                    vscale = rng.uniform(0.82, 1.15, nv)
                else:
                    p_tall = 0.36
                    p_meadow = 0.38
                    p_fern = 0.16 if is_showcase else 0.08
                    vkind = np.where(
                        rv < p_tall, KIND_GRASS_TALL_VERGE,
                        np.where(rv < p_tall + p_meadow, KIND_GRASS_MEADOW,
                                 np.where(rv < p_tall + p_meadow + p_fern, KIND_FERN, KIND_WILDFLOWER))
                    )
                    vscale = rng.uniform(0.82, 1.24, nv)
                vy = vh - (0.01 + vslope * 0.05)
                vwarmth = np.clip(0.14 + 0.35 * vclump + 0.22 * vflowers, 0.0, 1.0)
                all_batches.append(build_rows(vx, vz, vy, rng.uniform(0.0, 2.0 * np.pi, nv), vscale, vkind, vwarmth))

    # =========================================================================
    # 5. SHOWCASE DISTANCE-BANDED FOREST FLOOR (0–35m, 35–90m, 90–150m)
    # =========================================================================
    # 5a. Near band: 0.74 m grid for 3.2..35 m from road edge along showcase
    nx, nz = grid_candidates(0.74, -980.0, -460.0, -510.0, 95.0)
    n_edge, _, n_bridge, n_show = road_model.evaluate(nx, nz)
    near_mask = (n_show <= 65.0) & (n_edge > 2.8) & (n_edge <= 36.0) & (n_bridge >= 6.0)
    nx, nz, n_edge, n_show = nx[near_mask], nz[near_mask], n_edge[near_mask], n_show[near_mask]
    nh = sample_grid(heights, nx, nz)
    nslope = sample_grid(slope_grid, nx, nz)
    nlake = sample_grid(lake_dist, nx, nz)
    nclump = sample_grid(clumps, nx, nz)
    ncanopy = dist_to_canopy(nx, nz)

    valid_near = (
        (nh > 6.0) & (nlake >= 3.0) & (nslope < 0.78)
        & (ncanopy >= 0.45)
        & ~building_blocked(nx, nz, 0.2)
    )
    near_prob = np.clip(0.68 + 0.28 * nclump - 0.14 * _smoothstep(18.0, 36.0, n_edge), 0.0, 0.94)
    keep_near = valid_near & (rng.random(len(nx)) < near_prob)
    nx, nz, nh, nslope, nclump, ncanopy = (
        nx[keep_near], nz[keep_near], nh[keep_near], nslope[keep_near], nclump[keep_near], ncanopy[keep_near]
    )
    nn = len(nx)
    rn = rng.random(nn)
    # Ferns cluster more heavily under tree canopies (< 6 m from trunks)
    under_tree = ncanopy < 6.5
    p_fern = np.where(under_tree, 0.22, 0.07)
    p_short = 0.20
    p_tall = 0.14
    p_flower = 0.06
    n_kind = np.where(
        rn < p_fern, KIND_FERN,
        np.where(rn < p_fern + p_short, KIND_GRASS_SHORT,
                 np.where(rn < p_fern + p_short + p_tall, KIND_GRASS_TALL_VERGE,
                          np.where(rn < p_fern + p_short + p_tall + p_flower, KIND_WILDFLOWER, KIND_GRASS_MEADOW)))
    )
    n_scale = rng.uniform(0.84, 1.28, nn)
    n_y = nh - (0.015 + nslope * 0.06)
    all_batches.append(build_rows(nx, nz, n_y, rng.uniform(0.0, 2.0 * np.pi, nn), n_scale, n_kind, 0.12 + 0.40 * nclump))

    # 5b. Mid band (35–90 m) + Far band (90–150 m) in showcase
    mx, mz = grid_candidates(1.65, -980.0, -420.0, -540.0, 125.0)
    m_edge, _, m_bridge, m_show = road_model.evaluate(mx, mz)
    mid_mask = (m_show <= 155.0) & (m_edge > 34.0) & (m_edge <= 150.0) & (m_bridge >= 6.0)
    mx, mz, m_edge = mx[mid_mask], mz[mid_mask], m_edge[mid_mask]
    mh = sample_grid(heights, mx, mz)
    mslope = sample_grid(slope_grid, mx, mz)
    mlake = sample_grid(lake_dist, mx, mz)
    mclump = sample_grid(clumps, mx, mz)
    mcanopy = dist_to_canopy(mx, mz)

    valid_mid = (
        (mh > 6.0) & (mlake >= 3.0) & (mslope < 0.76)
        & (mcanopy >= 0.50)
        & ~building_blocked(mx, mz, 0.2)
    )
    # Smooth density falloff from 35 m -> 90 m -> 150 m
    mid_prob = np.clip((1.0 - _smoothstep(35.0, 148.0, m_edge)) * (0.55 + 0.45 * mclump), 0.0, 0.90)
    keep_mid = valid_mid & (rng.random(len(mx)) < mid_prob)
    mx, mz, mh, mslope, mclump, mcanopy = (
        mx[keep_mid], mz[keep_mid], mh[keep_mid], mslope[keep_mid], mclump[keep_mid], mcanopy[keep_mid]
    )
    nm = len(mx)
    rm = rng.random(nm)
    m_fern_p = np.where(mcanopy < 6.5, 0.30, 0.12)
    m_kind = np.where(
        rm < m_fern_p, KIND_FERN,
        np.where(rm < m_fern_p + 0.14, KIND_GRASS_TALL_VERGE,
                 np.where(rm < m_fern_p + 0.21, KIND_WILDFLOWER, KIND_GRASS_MEADOW))
    )
    m_scale = rng.uniform(0.95, 1.38, nm)
    m_y = mh - (0.015 + mslope * 0.06)
    all_batches.append(build_rows(mx, mz, m_y, rng.uniform(0.0, 2.0 * np.pi, nm), m_scale, m_kind, 0.15 + 0.42 * mclump))

    # =========================================================================
    # 6. REST OF VALLEY UNDERGROWTH (Sparse meadow/woods outside showcase)
    # =========================================================================
    ux, uz = grid_candidates(2.9)
    u_edge, _, u_bridge, u_show = road_model.evaluate(ux, uz)
    u_mask = (u_show > 150.0) & (u_edge >= 2.2) & (u_edge <= 125.0) & (u_bridge >= 6.0)
    ux, uz, u_edge = ux[u_mask], uz[u_mask], u_edge[u_mask]
    uh = sample_grid(heights, ux, uz)
    uslope = sample_grid(slope_grid, ux, uz)
    ulake = sample_grid(lake_dist, ux, uz)
    uclump = sample_grid(clumps, ux, uz)
    uwoods = sample_grid(woods, ux, uz)
    uflowers = sample_grid(flowers, ux, uz)

    valid_u = (uh > 6.0) & (ulake >= 3.0) & (uslope < 0.72) & ~building_blocked(ux, uz, 0.2)
    u_prob = np.clip((np.exp(-u_edge / 55.0) * (0.65 + 0.35 * uclump) + 0.18 * uflowers + 0.12 * uwoods), 0.0, 0.88)
    keep_u = valid_u & (rng.random(len(ux)) < u_prob)
    ux, uz, uh, uslope, uclump, uwoods, uflowers = (
        ux[keep_u], uz[keep_u], uh[keep_u], uslope[keep_u], uclump[keep_u], uwoods[keep_u], uflowers[keep_u]
    )
    nu = len(ux)
    ru = rng.random(nu)
    u_fern_p = 0.14 * uwoods
    u_flower_p = 0.12 * uflowers
    u_kind = np.where(
        ru < u_fern_p, KIND_FERN,
        np.where(ru < u_fern_p + u_flower_p, KIND_WILDFLOWER,
                 np.where(ru < u_fern_p + u_flower_p + 0.16, KIND_GRASS_SHORT, KIND_GRASS_MEADOW))
    )
    u_scale = rng.uniform(0.84, 1.30, nu)
    u_y = uh - (0.015 + uslope * 0.06)
    u_warmth = np.clip(0.15 + 0.35 * uclump + 0.25 * uflowers, 0.0, 1.0)
    all_batches.append(build_rows(ux, uz, u_y, rng.uniform(0.0, 2.0 * np.pi, nu), u_scale, u_kind, u_warmth))

    all_placements = np.vstack(all_batches).astype("<f4")
    all_placements.tofile(args.output / "vegetation.bin")
    counts = np.bincount(all_placements[:, 5].astype(int), minlength=12)
    names = [
        "conifer_tall", "broadleaf_oak", "grass_meadow", "wildflower",
        "rock", "conifer_medium", "broadleaf_birch", "sapling_conifer",
        "grass_short", "grass_tall_verge", "fern", "shrub_woodland",
    ]
    summary = {names[i]: int(counts[i]) for i in range(len(names))}
    print(f"Total placements: {len(all_placements)} | {summary}")

    road_map(args.output, graph, metadata, heights, wet)


def road_map(out: Path, graph: dict, metadata: dict, heights: np.ndarray, wet: np.ndarray):
    size = 2048
    masks = [Image.new("L", (size, size)) for _ in range(2)]
    pen = [ImageDraw.Draw(mask) for mask in masks]
    main_loop = metadata["main_touring_loop"]
    for lane in graph["lanes"]:
        points = [((x + 1000) * size / 2000, (z + 1000) * size / 2000) for x, _, z in lane["points"]]
        index = int(lane["road_id"] in main_loop)
        pen[index].line(points, fill=255, width=9 if index else 6, joint="curve")
    # The alpha channel stores height. Data is sampled directly and never used as transparency.
    relief = Image.fromarray(np.uint8(21 + np.clip(heights / 235.0, 0, 1) * 234))
    water = Image.fromarray(np.uint8(wet) * 255)
    channels = masks + [
        water.resize((size, size), Image.Resampling.BILINEAR),
        relief.resize((size, size), Image.Resampling.BILINEAR),
    ]
    Image.merge("RGBA", channels).save(out / "minimap.png", optimize=True)


if __name__ == "__main__":
    main()
