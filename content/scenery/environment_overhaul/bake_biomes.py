"""Offline v1 ecological mask baker. Run from any directory; no game writes."""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import tempfile

import numpy as np
from scipy.ndimage import distance_transform_edt, gaussian_filter, maximum_filter
from scipy.spatial import ConvexHull
from numbers import Real

N = 1000
ORIGIN = -1000
CELL = 2
CELL_RADIUS = np.sqrt(2.0)
# Provisional footprint envelope; the coordinator must still validate actual asset AABBs.
UNDERSTORY_RADIUS_M = 2.0
# Conservative planar envelopes for root runtime adopted meshes/colliders.
# These are authoring bounds, not measured runtime AABBs.
ADOPTED_RADII = {"house":7.5,"barn":9.4,"garage":8.7,"pier":9.1,"quarry":10.8,
                 "arch":4.8,"rock":3.8,"shrub":1.8,"pine":4.2,"broadleaf":5.5}
CHANNELS = ["grass_suitability", "woodland_weight", "moisture", "exposed_rock_weight"]
BOUNDS = dict(min_x=-1000, max_x=1000, min_z=-1000, max_z=1000)
SPECIES = ("fern", "shrub", "sapling", "reed", "wildflower")
DEFAULTS = dict(road_margin_m=2.0, sightline_m=12.0, water_margin_m=2.0,
                spacing_m=8.0, max_placements=12000, density=0.45,
                rock_slope_start=.28, rock_slope_full=.9, alpine_start_m=135.0,
                alpine_full_m=205.0, canopy_grass_penalty=.45, max_understory_slope=.63)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def strict_json(data):
    def pairs(items):
        result = {}
        for key,value in items:
            require(key not in result,"Duplicate JSON key: "+key)
            result[key] = value
        return result
    def constant(value):
        raise ValueError("Invalid JSON constant: "+value)
    def finite_float(value):
        number = float(value)
        require(math.isfinite(number),"Nonfinite JSON number: "+value)
        return number
    return json.loads(data,object_pairs_hook=pairs,parse_constant=constant,parse_float=finite_float)


def json_bytes(value):
    return (json.dumps(value, sort_keys=True, separators=(",", ":"), allow_nan=False) + "\n").encode()


def smooth(a, b, v):
    t = np.clip((v-a)/(b-a), 0, 1)
    return t*t*(3-2*t)


def cell_index(x, z):
    require(-1000 <= x < 1000 and -1000 <= z < 1000, "Outside mask")
    # Add the origin offset after integer floor division: adding 1000 to a
    # float first can round a point just inside the boundary onto the next cell.
    return math.floor(x)//2+500, math.floor(z)//2+500


def surface(h, x, z, triangular=True):
    u, v = (np.asarray(x)+1000)/4, (np.asarray(z)+1000)/4
    require(np.all((u >= 0) & (u <= 500) & (v >= 0) & (v <= 500)), "Outside terrain")
    i, j = np.minimum(u.astype(int), 499), np.minimum(v.astype(int), 499)
    u, v = u-i, v-j
    a,b,c,d = h[j,i],h[j,i+1],h[j+1,i],h[j+1,i+1]
    if not triangular:
        return (a*(1-u)+b*u)*(1-v)+(c*(1-u)+d*u)*v
    return np.where(u+v <= 1, a+(b-a)*u+(c-a)*v,
                    d+(c-d)*(1-u)+(b-d)*(1-v))


def decode_height(data, meta):
    h = meta["heightfield"]
    expected = dict(sample_width=501, sample_height=501, spacing_m=4,
                    origin_x=-1000, origin_z=-1000, row_order="z_ascending_x_ascending",
                    format="uint16_le")
    require(all(h.get(k)==v for k,v in expected.items()), "Unsupported heightfield geometry")
    require(h["scale_m_per_unit"] == .01 and h["offset_m"] == 0, "Unsupported quantization")
    require(len(data)==501*501*2, "Wrong raster length (missing LFS payload?)")
    return np.frombuffer(data, dtype="<u2").reshape(501,501).astype(float)*.01


class Sources:
    def __init__(self, root):
        self.root = Path(root).resolve()
        self.hashes = {}
    def read(self, rel):
        p = (self.root / rel).resolve()
        require(p.is_relative_to(self.root), "Source outside project")
        data = p.read_bytes()
        require(data and not data.startswith(b"version https://git-lfs.github.com/spec/v1"),
                "Empty or LFS pointer: "+str(rel))
        digest = sha(data)
        require(self.hashes.get(str(rel),digest)==digest,"Source changed during bake: "+str(rel))
        self.hashes[str(rel)] = digest
        return data
    def json(self, rel):
        return strict_json(self.read(rel))


def coords():
    q = np.arange(-999, 1000, 2, dtype=float)
    return np.meshgrid(q,q)


def window(x0,z0,x1,z1):
    def clamp(v):
        return min(N,max(0,v))
    i0,j0 = clamp(int(np.floor((x0+1000)/2))),clamp(int(np.floor((z0+1000)/2)))
    i1,j1 = clamp(int(np.ceil((x1+1000)/2))+1),clamp(int(np.ceil((z1+1000)/2))+1)
    return slice(j0,max(j0,j1)),slice(i0,max(i0,i1))


def capsule(mask, x, z, a, b, radius):
    a,b = np.asarray(a),np.asarray(b)
    require(a.shape==b.shape==(2,) and np.isfinite(a).all() and np.isfinite(b).all()
            and np.isfinite(radius) and radius>=0, "Invalid capsule geometry")
    radius = float(radius)+CELL_RADIUS  # include any cell touched by the buffer
    s = window(*(np.minimum(a,b)-radius), *(np.maximum(a,b)+radius))
    xx,zz = x[s]-a[0],z[s]-a[1]
    delta = b-a
    t = np.clip((xx*delta[0]+zz*delta[1])/max(1e-12,float(delta@delta)),0,1)
    mask[s] |= (xx-t*delta[0])**2+(zz-t*delta[1])**2 <= radius**2


def checked_number(value, label, minimum=0):
    require(isinstance(value,Real) and not isinstance(value,(bool,np.bool_)), "Invalid "+label)
    try:
        number = float(value)
    except OverflowError as error:
        raise ValueError("Invalid "+label) from error
    require(math.isfinite(number) and number>=minimum, "Invalid "+label)
    return number


def road_mask(graph, works, x,z, margin):
    mask = np.zeros(x.shape,bool)
    lanes = {l["id"]: l for l in graph["lanes"]}
    require(len(lanes)==len(graph["lanes"]) and lanes,"Duplicate or empty lanes")
    network = works.get("network_upgrade",{})
    designs = works["roads"]
    groups = {}
    physical = set()
    for lane in lanes.values():
        lid = lane["id"]
        xyz = np.asarray(lane["points"],float)
        require(xyz.ndim==2 and xyz.shape[1]==3 and len(xyz)>=2 and
                np.isfinite(xyz).all() and np.all(np.abs(xyz[:,[0,2]])<=1000),"Invalid lane geometry")
        points = xyz[:,[0,2]]
        require(np.all(np.linalg.norm(np.diff(points,axis=0),axis=1)>1e-6),"Degenerate lane")
        width = checked_number(lane["width_m"],"lane width",.01)
        require(lane["surface"] in ("asphalt","gravel"),"Unknown lane surface")
        if lid.startswith("turn_"):
            # Match runtime group by junction pseudo-road, not a truncated lane ID.
            reach = width/2 + 3 + checked_number(network.get("junction_extra_m",0),"junction extra") + margin
            offsets = np.array([[a,b] for a in (-reach,reach) for b in (-reach,reach)])
            groups.setdefault(lane["road_id"],[]).extend(points[:,None,:]+offsets[None,:,:])
        else:
            require(lid == "lane_"+lane["road_id"]+"_ab" or lid == "lane_"+lane["road_id"]+"_ba",
                    "Unknown physical lane convention")
            opposite_id = lid[:-3]+("_ba" if lid.endswith("_ab") else "_ab")
            require(opposite_id in lanes,"Missing opposite lane")
            opposite = lanes[opposite_id]
            require(opposite["surface"]==lane["surface"] and opposite["road_id"]==lane["road_id"],
                    "Inconsistent lane pair")
            other = np.asarray(opposite["points"],float)
            require(other.shape==xyz.shape and np.isfinite(other).all(),"Unpaired corridor")
            if lid.endswith("_ba"):
                continue
            center = (points+other[::-1][:,[0,2]])/2
            require(np.all(np.linalg.norm(np.diff(center,axis=0),axis=1)>1e-6),"Degenerate corridor")
            design = designs.get(lane["road_id"],{})
            physical.add(lane["road_id"])
            # A capsule around each chord contains every interpolated road triangle
            # whose section vertices lie within the maximum offset of each endpoint.
            half = max(width, checked_number(opposite["width_m"],"opposite width",.01),
                       checked_number(design.get("width_m",0),"roadworks width")/2,
                       checked_number(network.get("widths_m",{}).get(lane["road_id"],0),"network width")/2)
            shoulder = max(1.35,checked_number(network.get(lane["surface"]+"_shoulder_m",1.35),"shoulder"))
            for a,b in zip(center[:-1],center[1:]):
                capsule(mask,x,z,a,b,half+shoulder+margin)
    require(physical and set(designs)<=physical and set(network.get("widths_m",{}))<=physical,
            "Roadworks references unknown physical corridor")
    if "roads" in graph:
        records = {r["id"]:r for r in graph["roads"]}
        require(len(records)==len(graph["roads"]) and set(records)==physical|set(groups),"Missing road records")
        for rid,road in records.items():
            require(set(road["lane_ids"])=={lid for lid,l in lanes.items() if l["road_id"]==rid},
                    "Road/lane membership mismatch")
    for parts in groups.values():
        points = np.asarray(parts).reshape(-1,2)
        hull = ConvexHull(points)
        s = window(*(points.min(axis=0)-2),*(points.max(axis=0)+2))
        inside = np.ones(x[s].shape,bool)
        for a,b,c in hull.equations:
            inside &= a*x[s]+b*z[s]+c <= CELL_RADIUS
        mask[s] |= inside
    return mask


def water_mask(lake, works):
    require(all(lake.get(k)==v for k,v in dict(origin_x=-1000,origin_z=-1000,spacing_m=4).items()),
            "Unsupported lake coordinates")
    result = np.zeros((N,N),bool)
    for cells in [lake["cells"]]+[w["cells"] for w in works["waters"]]:
        for i,j in cells:
            require(type(i) is int and type(j) is int and 0<=i<500 and 0<=j<500,"Bad water cell")
            result[2*j:2*j+2,2*i:2*i+2] = True
    return result


def distance(mask):
    if not mask.any():
        return np.full(mask.shape,4000.0)
    return distance_transform_edt(~mask)*CELL


def clearance_lower_bound(mask):
    # EDT measures center to center, not surface distance. Both the query cell
    # and the occupied cell may extend sqrt(2) m toward each other.
    return np.maximum(0,distance(mask)-2*CELL_RADIUS)


def triangle_slope(h):
    # Four 2 m cells per 4 m terrain quad. NW and SE are fully on one
    # triangle; NE/SW cross the diagonal and take the steeper gradient.
    a,b,c,d = h[:-1,:-1],h[:-1,1:],h[1:,:-1],h[1:,1:]
    nw = np.hypot(b-a,c-a)/4
    se = np.hypot(d-c,d-b)/4
    result = np.empty((N,N),float)
    result[0::2,0::2] = nw
    result[1::2,1::2] = se
    result[0::2,1::2] = result[1::2,0::2] = np.maximum(nw,se)
    return result


def footprint_slope(slope):
    # A 2 m radius footprint from any point in a 2 m cell can reach the
    # immediately adjacent cells, and the far boundary of a second cell.
    # Include the full conservative 5 x 5 neighborhood.
    return maximum_filter(slope,size=5,mode="nearest")


def scenery_masks(src,x,z):
    protected, props, trees = (np.zeros(x.shape,bool) for _ in range(3))
    manifest = src.json("content/scenery/manifest.json")
    zones = src.json("content/scenery/avoidance/race_gate_reservations_v1.json")["zones"]
    for zone in zones:
        p = [zone["x"],zone["z"]]
        capsule(protected,x,z,p,p,checked_number(zone["radius_m"],"reservation radius")+3)
    for pack in manifest["region_packs"]:
        placements = src.json(pack["path"])["placements"]
        require(pack.get("count",len(placements))==len(placements),"Scenery pack count mismatch")
        for item in placements:
            p = np.asarray(item["position"])[[0,2]]
            asset = manifest["assets"][item["asset"]]
            kind = item["asset"]
            scale = checked_number(item.get("scale",1),"scenery scale",.0001)
            radius = max(checked_number(asset["r"],"scenery radius",.0001),
                         ADOPTED_RADII.get(kind,0))*scale
            require(np.isfinite(p).all() and np.isfinite(radius) and radius>0,"Invalid scenery footprint")
            if kind in ("pine","broadleaf"):
                # Canopy and physical trunk are different habitats. Allow low
                # understory beneath crowns but not saplings or trunk overlaps.
                capsule(trees,x,z,p,p,radius)
                capsule(props,x,z,p,p,.85*scale)
                capsule(protected,x,z,p,p,.45*scale)
            else:
                # Roadworks may relocate guardrails by up to 3 m.
                capsule(props,x,z,p,p,radius+(3 if kind=="guardrail" else 0))
                capsule(protected,x,z,p,p,radius)
                if asset["kind"] in ("architecture","landmark"):
                    capsule(protected,x,z,p,p,max(11,radius+4))
    # Existing live vegetation and optional legacy premium cache are read-only.
    for filename in ("vegetation.bin","premium_foliage.bin"):
        rel = "data/world/"+filename
        try:
            raw = src.read(rel)
        except FileNotFoundError:
            if filename=="premium_foliage.bin":
                continue  # optional, non-live legacy cache; recorded by absent source hash
            raise
        require(len(raw)%28==0,"Invalid vegetation stride")
        rows = np.frombuffer(raw,dtype="<f4").reshape(-1,7)
        require(np.isfinite(rows).all() and (rows[:,4]>0).all(),"Invalid vegetation record")
        kinds = rows[:,5]
        require(np.all((kinds==np.floor(kinds)) & (kinds>=0) & (kinds<=5)),"Invalid vegetation kind")
        require(np.all(np.abs(rows[:,[0,2]])<=1000) and np.all((rows[:,6]>=0)&(rows[:,6]<=1)),
                "Invalid vegetation bounds or seed")
        for row in rows[kinds!=(2 if filename=="vegetation.bin" else 5)]:
            px,_,pz,_,scale,kind,_ = row
            p = [px,pz]
            # Skip dense grass in both formats (live class 2, premium class 5).
            if kind in (0,1) and filename=="vegetation.bin":
                radius = float(scale)*(4.2 if kind==0 else 5.5)
                capsule(trees,x,z,p,p,radius)
                capsule(props,x,z,p,p,.85*float(scale))
                capsule(protected,x,z,p,p,.45*float(scale))
            else:
                # Non-live premium cache remains a conservative duplicate guard.
                radius = max(1.5,float(scale)*(3.5 if kind in (0,1) else 1.5))
                capsule(props,x,z,p,p,radius)
                if filename=="vegetation.bin" and kind==4:
                    capsule(protected,x,z,p,p,radius)
    return protected,props,trees


def bake(root, seed, tuning=None):
    require(tuning is None or isinstance(tuning,dict),"Tuning must be a JSON object")
    t = dict(DEFAULTS,**(tuning or {}))
    require(set(t)==set(DEFAULTS),"Unknown tuning key")
    for k,v in t.items():
        checked_number(v,k)
    require(isinstance(seed,int) and not isinstance(seed,bool) and 0<=seed<2**53,"Invalid seed")
    require(4<=t["spacing_m"]<=1960 and t["density"]<=1 and 0<=t["max_placements"]<=12000 and int(t["max_placements"])==t["max_placements"],"Invalid placement budget")
    require(t["rock_slope_full"]>t["rock_slope_start"] and t["alpine_full_m"]>t["alpine_start_m"]
            and t["canopy_grass_penalty"]<=1, "Invalid ecology thresholds")
    src = Sources(root)
    meta = src.json("data/world/world_metadata_v1.json")
    graph = src.json("data/world/road_graph_v1.json")
    require(meta["schema_version"]==graph["schema_version"]==1 and
            meta["bounds"]==graph["bounds"]==BOUNDS and
            meta["coordinate_system"]==graph["coordinate_system"]=="godot_y_up" and graph["units"]=="meters",
            "World bounds/coordinate contract changed")
    canonical = decode_height(src.read("data/world/terrain_height_r16le.bin"),meta)
    h = decode_height(src.read("data/world/terrain_roadworks_r16le.bin"),meta)
    works = src.json("data/world/roadworks.json")
    lake = src.json("content/scenery/lake/water_cells_v1.json")
    x,z = coords()
    heights = surface(h,x,z)
    # Independent canonical lane elevation comparison uses exporter bilinear sampling.
    points = np.concatenate([np.asarray(l["points"],float) for l in graph["lanes"]])
    lane_error = float(np.max(np.abs(surface(canonical,points[:,0],points[:,2],False)-points[:,1])))
    require(lane_error < .015,"Canonical lane/height alignment failed")
    slope = triangle_slope(h)
    plant_slope = footprint_slope(slope)
    road = road_mask(graph,works,x,z,t["road_margin_m"])
    wet = water_mask(lake,works)
    protected,props,trees = scenery_masks(src,x,z)
    road_dist,water_dist = clearance_lower_bound(road),clearance_lower_bound(wet)
    prop_dist = clearance_lower_bound(props|protected)
    water_center_dist = distance(wet)
    canopy_dist = clearance_lower_bound(trees)
    canopy = gaussian_filter(trees.astype(float),sigma=4)
    rng = np.random.default_rng(seed)
    # Smooth multi-scale noise, deterministic with pinned NumPy/SciPy.
    def noise(sigma):
        v = gaussian_filter(rng.random(x.shape),sigma)
        return np.clip(.5+(v-v.mean())/(max(v.std(),1e-9)*6),0,1)
    n = .65*noise(12)+.35*noise(3)
    weights = {}
    for reg in meta["regions"]:
        cx,cz = reg["center"]
        require(reg["id"] not in weights and np.isfinite([cx,cz]).all(),"Invalid region")
        radius = checked_number(reg["radius_m"],"region radius",.01)
        weights[reg["id"]] = np.exp(-((x-cx)**2+(z-cz)**2)/radius**2)
    require(set(weights)=={"alder_town","cedar_woods","north_ridge","green_valley","eastwater_lake"},
            "Region contract changed")
    town,cedar,ridge,meadow,east = (weights[k] for k in
        ("alder_town","cedar_woods","north_ridge","green_valley","eastwater_lake"))
    alpine = smooth(t["alpine_start_m"],t["alpine_full_m"],heights)
    rock = np.clip(.70*smooth(t["rock_slope_start"],t["rock_slope_full"],slope)+.38*alpine+.16*ridge*n,0,1)
    woodland = np.clip((.12+.82*cedar+.24*ridge+.16*east-.25*meadow-.32*town)
                       *(1-.8*alpine)*(1-.8*rock)*(.7+.55*n)+.45*canopy,0,1)
    moisture = np.clip(.2+.55*np.exp(-water_dist/35)+.14*cedar+.10*n-.24*alpine,0,1)
    grass = np.clip((.84+.14*meadow+.12*town-.20*woodland-t["canopy_grass_penalty"]*canopy)
                    *(1-.86*rock)*(1-.5*alpine)*(.8+.3*n),0,1)
    # No exponential road proximity bias. Hard exclusions only for unsafe surfaces.
    excluded = road|protected|wet|(water_dist<=t["water_margin_m"])
    grass *= 1-smooth(.75,1.4,slope)  # cliff faces are not meadow
    grass[excluded] = 0
    woodland[road|protected|wet] = 0
    rock[wet|road|protected] = 0
    moisture[wet] = 1
    mask = np.rint(np.stack([grass,woodland,moisture,rock],axis=-1)*255).astype(np.uint8)
    # At most one jittered candidate per coarse cell; explicit nearest-neighbor
    # spacing across coarse-cell boundaries using deterministic spatial buckets.
    step = float(t["spacing_m"])
    q = -980+(np.arange(int(1960//step))+.5)*step
    placements, buckets = [], {}
    rejected = dict(exclusion=0,probability=0,spacing=0,budget=0)
    for idx in rng.permutation(len(q)**2):
        pz,px = q[idx//len(q)],q[idx%len(q)]
        a,b = np.array([px,pz])+rng.uniform(-.35,.35,2)*step
        # Quantize to the actual Godot Vector3 precision before cell and spacing
        # checks; emit exact float32 values rather than decimal rounding.
        a,b = float(np.float32(a)),float(np.float32(b))
        i,j = cell_index(a,b)
        if (excluded[j,i] or prop_dist[j,i]<=UNDERSTORY_RADIUS_M
                or water_dist[j,i]<=t["water_margin_m"]+UNDERSTORY_RADIUS_M
                or road_dist[j,i]<t["sightline_m"]+UNDERSTORY_RADIUS_M
                or plant_slope[j,i]>t["max_understory_slope"]):
            rejected["exclusion"]+=1
            continue
        g,w,m,k = grass[j,i],woodland[j,i],moisture[j,i],rock[j,i]
        probabilities = np.array([w*m*(.8+.8*canopy[j,i]), w*.65,
                                 w*.22*(1-town[j,i])*float(canopy_dist[j,i]>UNDERSTORY_RADIUS_M),
                                 float(water_dist[j,i]>=4 and water_center_dist[j,i]+CELL_RADIUS<=18)*m*(1-k),
                                 g*meadow[j,i]*(1-w)])
        total = probabilities.sum()
        if total<=0 or rng.random()>=min(1,t["density"]*min(1,total)*(.45+.8*n[j,i])):
            rejected["probability"]+=1
            continue
        key = (int(np.floor(a/step)),int(np.floor(b/step)))
        if any((a-u)**2+(b-v)**2 < max(step*.65,2*UNDERSTORY_RADIUS_M)**2
               for di in (-1,0,1) for dj in (-1,0,1)
               for u,v in buckets.get((key[0]+di,key[1]+dj),[])):
            rejected["spacing"]+=1
            continue
        if len(placements)>=t["max_placements"]:
            rejected["budget"]+=1
            continue
        kind = SPECIES[rng.choice(len(SPECIES),p=probabilities/total)]
        buckets.setdefault(key,[]).append((a,b))
        placements.append(dict(species_id=kind,x=a,z=b,
                               yaw_rad=round(float(rng.uniform(0,2*np.pi)),6),
                               scale=round(float(rng.uniform(.75,1.25)),5),
                               seed=int(rng.integers(0,2**31))))
    placements.sort(key=lambda p:(p["z"],p["x"]))
    raw = mask.tobytes(order="C")
    stats = dict(lane_alignment_max_m=lane_error, exclusions={k:int(v.sum()) for k,v in
                 dict(road=road,water=wet,protected=protected,combined=excluded,props=props,canopy=trees).items()},
                 rejection=rejected, species={s:sum(p["species_id"]==s for p in placements) for s in SPECIES},
                 regions={})
    dominant = np.argmax(np.stack(list(weights.values())),axis=0)
    for i,k in enumerate(weights):
        region = dominant==i
        valid = region & ~excluded
        stats["regions"][k] = dict(cells=int(region.sum()), eligible=int(valid.sum()),
            mean_channels=(mask[valid].mean(axis=0)/255).tolist() if valid.any() else [0]*4,
            grass_coverage=float(np.mean(grass[region]>.5)) if region.any() else 0.0,
            mean_slope=float(slope[region].mean()) if region.any() else 0.0,
            placements=sum(dominant[cell_index(p["x"],p["z"])[1],cell_index(p["x"],p["z"])[0]]==i for p in placements))
    # numpy integer from sum of numpy booleans must be converted for JSON.
    for region in stats["regions"].values():
        region["placements"] = int(region["placements"])
    manifest = dict(schema_version=1,width=N,height=N,cell_size_m=CELL,origin_x=ORIGIN,origin_z=ORIGIN,
                    channels=CHANNELS,byte_order="RGBA",sha256=sha(raw),source_hashes=src.hashes,seed=seed,
                    tuning=t, row_order="z_ascending_x_ascending")
    understory = dict(schema_version=1,source_hashes=src.hashes,seed=seed,placements=placements)
    manifest["understory_sha256"] = sha(json_bytes(understory))
    manifest["statistics_sha256"] = sha(json_bytes(stats))
    manifest["generator_sha256"] = sha(Path(__file__).read_bytes())
    manifest["numeric_versions"] = dict(numpy=np.__version__, scipy=__import__("scipy").__version__)
    manifest["optional_premium_cache_used"] = "data/world/premium_foliage.bin" in src.hashes
    # Runtime cross-check points include corners, triangle interiors, diagonals and chunk seams.
    probes = [(-1000,-1000), (1000,1000), (-1000,1000), (1000,-1000),
              (-999,-999),(-997,-997),(-998,-998),(0,0),(-872,-872),
              (-871,-873),(-700,-320),(45,170),(700,450)]
    # Independent stream: geometry probes do not change if placement density changes.
    probe_rng = np.random.default_rng(np.random.SeedSequence([seed,0xB10]))
    probes.extend((float(a),float(b)) for a,b in probe_rng.uniform(-999,999,(64,2)))
    manifest["surface_probes"] = [dict(x=a,z=b,height_m=float(surface(h,a,b))) for a,b in probes]
    cells = [(0,0),(999,0),(0,999),(999,999),(499,499),(500,500),(150,340),(522,585),(850,725)]
    manifest["mask_probes"] = [dict(x=-999+2*i,z=-999+2*j,rgba=mask[j,i].tolist()) for i,j in cells]
    # Detect input replacement between the first read and completed generation.
    for rel in tuple(src.hashes):
        src.read(rel)
    return raw,manifest,understory,stats


def validate_mask(raw,manifest):
    require(all(manifest.get(k)==v for k,v in dict(schema_version=1,width=N,height=N,cell_size_m=CELL,
            origin_x=ORIGIN,origin_z=ORIGIN,byte_order="RGBA",channels=CHANNELS,
            row_order="z_ascending_x_ascending").items()),"Invalid mask manifest")
    require(len(raw)==N*N*4 and sha(raw)==manifest.get("sha256"),"Corrupt or truncated mask")
    return np.frombuffer(raw,dtype=np.uint8).reshape(N,N,4)


def publish(output, raw, manifest, understory, stats):
    # Publish the manifest last as the commit marker. A concurrent reader must
    # verify hash and fail closed if reading a partially replaced generation.
    validate_mask(raw,manifest)
    require(sha(json_bytes(understory)) == manifest.get("understory_sha256"), "Invalid understory hash")
    require(sha(json_bytes(stats)) == manifest.get("statistics_sha256"), "Invalid statistics hash")
    output = Path(output)
    output.mkdir(parents=True,exist_ok=True)
    require(not any((output/name).is_symlink() for name in ("manifest.json","biome_rgba8.bin","understory.json","statistics.json")),
            "Refusing symlink output")
    # Serialize writers. An interrupted process leaves the lock in place;
    # remove it manually only after confirming no baker is active.
    lock = output/".bake.lock"
    lock.mkdir()
    try:
        with tempfile.TemporaryDirectory(dir=output) as temp:
            entries = (("biome_rgba8.bin",raw),("understory.json",json_bytes(understory)),
                       ("statistics.json",json_bytes(stats)),("manifest.json",json_bytes(manifest)))
            for name,data in entries:
                (Path(temp)/name).write_bytes(data)
            for name,_ in entries:
                os.replace(Path(temp)/name,output/name)
    finally:
        lock.rmdir()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project",type=Path,required=True)
    parser.add_argument("--output",type=Path,required=True)
    parser.add_argument("--seed",type=int,default=20261121)
    parser.add_argument("--tuning",type=Path)
    args = parser.parse_args()
    root = args.project.resolve()
    out = args.output.resolve()
    owned = root/"content/scenery/environment_overhaul"
    require(not out.is_relative_to(root) or out.is_relative_to(owned),"Refusing output outside owned project directory")
    tuning = strict_json(args.tuning.read_bytes()) if args.tuning else None
    result = bake(root,args.seed,tuning)
    publish(out,*result)
    print(json.dumps(result[3],indent=2))


if __name__=="__main__":
    main()
