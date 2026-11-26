"""Independent geometry audit of the coarse road exclusions, not a Godot raycast.

Can run without the vegetation cache. With --mask-dir, audits the actual published
grass channel; without it, audits the baker's isolated road exclusion raster.
"""
import argparse
import json
from pathlib import Path

import numpy as np
from scipy.spatial import ConvexHull

import bake_biomes as baker


def smoothstep(lo, hi, t):
    x = max(0.0, min(1.0, (t-lo)/(hi-lo)))
    return x*x*(3-2*x)


def runtime_sections(lane, opposite, profile, network):
    # Independently mirror mesh_builder.gd _road_width, _network_factor,
    # physical_half_width, physical_shoulder and _section.
    a = np.asarray(lane["points"], float)
    b = np.asarray(opposite["points"], float)[::-1]
    center = ((a+b)*0.5)[:, [0,2]]
    stations = np.r_[0, np.cumsum(np.linalg.norm(np.diff(center, axis=0), axis=1))]
    sections = []
    for i,(p,station) in enumerate(zip(center,stations)):
        edge_distance = min(station,stations[-1]-station)
        base = lane["width_m"]
        legacy = base
        if profile:
            radius = profile["wide_radius"]
            taper = (1-smoothstep(radius*.48,radius,abs(station-profile["center"])))
            taper *= smoothstep(18,37,edge_distance)
            legacy += (profile["width_m"]*.5-base)*taper
        factor = smoothstep(6,34,edge_distance)
        if "bridge_start" in profile:
            gap = max(profile["bridge_start"]-station,station-profile["bridge_end"])
            factor *= smoothstep(0,28,gap)
        target = network.get("widths_m",{}).get(lane["road_id"],base*2)*.5
        half = legacy+(max(legacy,target)-legacy)*factor
        shoulder = 1.35+(network.get(lane["surface"]+"_shoulder_m",1.35)-1.35)*factor
        tangent = center[min(i+1,len(center)-1)]-center[max(0,i-1)]
        tangent /= np.linalg.norm(tangent)
        side = np.array([-tangent[1],tangent[0]])*(half+shoulder)
        sections.append([p-side,p+side])
    return np.asarray(sections),stations


def triangle_points(tri, step=.5):
    # Barycentric lattice with max edge spacing <= step, including vertices.
    n = max(1,int(np.ceil(np.max(np.linalg.norm(tri-np.roll(tri,1,axis=0),axis=1))/step)))
    pairs = np.array([(i,j) for i in range(n+1) for j in range(n+1-i)],float)/n
    return tri[0]+pairs[:,0,None]*(tri[1]-tri[0])+pairs[:,1,None]*(tri[2]-tri[0])


def junction_points(group, network):
    raw = []
    for lane in group:
        points = np.asarray(lane["points"],float)[:,[0,2]]
        reach = lane["width_m"]*.5+3+network.get("junction_extra_m",0)
        for i,p in enumerate(points):
            d = points[min(i+1,len(points)-1)]-points[max(0,i-1)]
            d /= np.linalg.norm(d)
            normal = np.array([-d[1],d[0]])*reach
            raw.extend([p+normal,p-normal,p+[reach,0],p-[reach,0],
                        p+[0,reach],p-[0,reach]])
    raw=np.asarray(raw)
    hull=ConvexHull(raw)
    p=raw[hull.vertices]
    x,z=np.meshgrid(np.arange(np.floor(p[:,0].min()*2)/2,p[:,0].max()+.5,.5),
                    np.arange(np.floor(p[:,1].min()*2)/2,p[:,1].max()+.5,.5))
    grid=np.column_stack((x.ravel(),z.ravel()))
    interior=np.all(grid@hull.equations[:,:2].T+hull.equations[:,2]<=1e-8,axis=1)
    return np.vstack((p,grid[interior]))


def audit(graph,works,excluded):
    if excluded.shape!=(1000,1000):
        raise ValueError("Invalid exclusion raster")
    lanes={lane["id"]:lane for lane in graph["lanes"]}
    network=works.get("network_upgrade",{})
    groups={}
    counts=dict(corridors=0,junctions=0,road_samples=0,bridge_samples=0,
                junction_samples=0,misses=0,outside=0)
    def check(points,kind):
        cells=np.floor((points+1000)/2).astype(int)
        valid=np.all((cells>=0)&(cells<1000),axis=1)
        counts["outside"]+=int((~valid).sum())
        cells=cells[valid]
        counts[kind]+=len(cells)
        counts["misses"]+=int((~excluded[cells[:,1],cells[:,0]]).sum())
    for lane in lanes.values():
        lid=lane["id"]
        if lid.startswith("turn_"):
            groups.setdefault(lane["road_id"],[]).append(lane)
            continue
        if not lid.endswith("_ab"):
            continue
        counts["corridors"]+=1
        profile=works["roads"].get(lane["road_id"],{})
        sections,stations=runtime_sections(lane,lanes[lid[:-3]+"_ba"],profile,network)
        start=profile.get("support_start",profile.get("bridge_start",float("inf")))
        end=profile.get("support_end",profile.get("bridge_end",float("-inf")))
        for i in range(len(sections)-1):
            a,b=sections[i]
            c,d=sections[i+1]
            kind="bridge_samples" if stations[i]>=start-.008 and stations[i+1]<=end+.008 else "road_samples"
            for tri in (np.array([a,c,b]),np.array([b,c,d])):
                check(triangle_points(tri),kind)
    for group in groups.values():
        counts["junctions"]+=1
        check(junction_points(group,network),"junction_samples")
    return counts


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--project",type=Path,required=True)
    p.add_argument("--mask-dir",type=Path)
    args=p.parse_args()
    sources=baker.Sources(args.project)
    graph=sources.json("data/world/road_graph_v1.json")
    works=sources.json("data/world/roadworks.json")
    if args.mask_dir:
        manifest=json.loads((args.mask_dir/"manifest.json").read_text())
        for name,digest in sources.hashes.items():
            if manifest["source_hashes"].get(name)!=digest:
                raise ValueError("Mask source mismatch: "+name)
        raw=(args.mask_dir/"biome_rgba8.bin").read_bytes()
        excluded=baker.validate_mask(raw,manifest)[:,:,0]==0
    else:
        x,z=baker.coords()
        excluded=baker.road_mask(graph,works,x,z,baker.DEFAULTS["road_margin_m"])
    result=audit(graph,works,excluded)
    print(json.dumps(result,indent=2))
    if result["misses"] or result["outside"] or not result["corridors"]:
        raise SystemExit(1)


if __name__=="__main__":
    main()
