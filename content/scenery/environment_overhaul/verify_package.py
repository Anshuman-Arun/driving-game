"""Fail-closed offline acceptance gate for a generated Agent C package."""
import argparse
from collections import Counter
from pathlib import Path

import numpy as np
from scipy.spatial import cKDTree

import bake_biomes as b
import verify_road_envelope as geometry

CORE = {
    "data/world/world_metadata_v1.json", "data/world/road_graph_v1.json",
    "data/world/terrain_height_r16le.bin", "data/world/terrain_roadworks_r16le.bin",
    "data/world/roadworks.json", "data/world/vegetation.bin",
    "content/scenery/manifest.json", "content/scenery/lake/water_cells_v1.json",
    "content/scenery/avoidance/race_gate_reservations_v1.json",
}
PREMIUM = "data/world/premium_foliage.bin"


def load_package(root, directory):
    """Read all files once, check hashes, schema, provenance and exact source set."""
    directory = Path(directory)
    b.require(not (directory/".bake.lock").exists(),"Publication in progress or interrupted")
    def read(name):
        path = directory/name
        b.require(path.is_file() and not path.is_symlink(),"Missing or symlink package file: "+name)
        return path.read_bytes()
    manifest_bytes = read("manifest.json")
    m = b.strict_json(manifest_bytes)
    b.require(isinstance(m,dict),"Malformed manifest")
    raw = read("biome_rgba8.bin")
    mask = b.validate_mask(raw,m)
    u_raw, s_raw = read("understory.json"),read("statistics.json")
    b.require(b.sha(u_raw)==m.get("understory_sha256"),"Understory hash mismatch")
    b.require(b.sha(s_raw)==m.get("statistics_sha256"),"Statistics hash mismatch")
    u,s = b.strict_json(u_raw),b.strict_json(s_raw)
    b.require(isinstance(u,dict) and isinstance(s,dict),"Malformed package JSON")
    b.require(u.get("schema_version")==1 and type(m.get("seed")) is int and
              0<=m["seed"]<2**53 and type(u.get("seed")) is int and u["seed"]==m["seed"],
              "Seed or understory schema mismatch")
    b.require(u.get("source_hashes")==m.get("source_hashes"),"Package source sets disagree")
    b.require(m.get("generator_sha256")==b.sha(Path(b.__file__).read_bytes()),
              "Mask baked with a different generator revision")
    b.require(isinstance(m.get("numeric_versions"),dict) and
              all(isinstance(m["numeric_versions"].get(k),str) for k in ("numpy","scipy")),
              "Missing numerical provenance")
    src=b.Sources(root)
    scenery=src.json("content/scenery/manifest.json")
    required=CORE|{pack["path"] for pack in scenery["region_packs"]}
    if (src.root/PREMIUM).exists():
        required.add(PREMIUM)
    hashes=m.get("source_hashes")
    b.require(isinstance(hashes,dict) and set(hashes)==required,"Incomplete or stale source set")
    b.require(m.get("optional_premium_cache_used") is (PREMIUM in required),"Premium cache mismatch")
    for name in sorted(required):
        b.require(b.sha(src.read(name))==hashes[name],"Stale source: "+name)
    t=m.get("tuning")
    b.require(isinstance(t,dict) and set(t)==set(b.DEFAULTS),"Invalid tuning keys")
    for k,v in t.items():
        b.checked_number(v,k)
    b.require(4<=t["spacing_m"]<=1960 and 0<=t["max_placements"]<=12000 and
              int(t["max_placements"])==t["max_placements"] and t["density"]<=1 and
              t["rock_slope_full"]>t["rock_slope_start"] and t["alpine_full_m"]>t["alpine_start_m"] and
              t["canopy_grass_penalty"]<=1,"Invalid tuning values")
    placements=u.get("placements")
    b.require(isinstance(placements,list) and len(placements)<=t["max_placements"],"Placement cap exceeded")
    xy=[]
    for p in placements:
        b.require(isinstance(p,dict) and set(p)=={"species_id","x","z","yaw_rad","scale","seed"},
                  "Invalid placement shape")
        b.require(p["species_id"] in b.SPECIES,"Unknown species")
        for k in ("x","z","yaw_rad","scale"):
            b.checked_number(p[k],k,-1000 if k in ("x","z") else 0)
        b.require(-980<=p["x"]<=980 and -980<=p["z"]<=980 and
                  0<=p["yaw_rad"]<=2*np.pi and .75<=p["scale"]<=1.25 and
                  type(p["seed"]) is int and 0<=p["seed"]<2**31,"Invalid placement range")
        b.require(all(float(np.float32(p[k]))==p[k] for k in ("x","z")),
                  "Placement coordinates not representable at runtime precision")
        xy.append([p["x"],p["z"]])
    xy=np.asarray(xy,dtype=float).reshape(-1,2)
    if len(xy)>1:
        minimum=max(t["spacing_m"]*.65,2*b.UNDERSTORY_RADIUS_M)
        b.require(not cKDTree(xy).query_pairs(minimum-1e-9),"Duplicate or overlapping placements")
    species=Counter(p["species_id"] for p in placements)
    b.require(s.get("species")=={name:species[name] for name in b.SPECIES},"Species statistics mismatch")
    if (directory/".bake.lock").exists() or read("manifest.json")!=manifest_bytes:
        raise ValueError("Package changed while being read")
    return mask,m,u,s,src


def verify(root,directory,rebuild=True):
    mask,m,u,s,src=load_package(root,directory)
    t=m["tuning"]
    graph=src.json("data/world/road_graph_v1.json")
    works=src.json("data/world/roadworks.json")
    lake=src.json("content/scenery/lake/water_cells_v1.json")
    meta=src.json("data/world/world_metadata_v1.json")
    b.require(meta["bounds"]==graph["bounds"]==b.BOUNDS,"Unsupported world bounds")
    h=b.decode_height(src.read("data/world/terrain_roadworks_r16le.bin"),meta)
    x,z=b.coords()
    road=b.road_mask(graph,works,x,z,t["road_margin_m"])
    wet=b.water_mask(lake,works)
    protected,props,trees=b.scenery_masks(src,x,z)
    canopy_dist=b.clearance_lower_bound(trees)
    rd,wd,pd=(b.clearance_lower_bound(a) for a in (road,wet,protected|props))
    slope=b.footprint_slope(b.triangle_slope(h))
    blocked=road|wet|protected|(wd<=t["water_margin_m"])
    b.require(np.all(mask[:,:,0][blocked]==0),"Grass on excluded cells")
    b.require(np.all(mask[:,:,1][road|wet|protected]==0),"Woodland on excluded cells")
    b.require(np.all(mask[:,:,3][road|wet|protected]==0),"Rock on excluded cells")
    b.require(np.all(mask[:,:,2][wet]==255),"Wet cell moisture mismatch")
    wc=b.distance(wet)
    for p in u["placements"]:
        i,j=b.cell_index(p["x"],p["z"])
        b.require(not blocked[j,i] and rd[j,i]>=t["sightline_m"]+b.UNDERSTORY_RADIUS_M and
                  wd[j,i]>t["water_margin_m"]+b.UNDERSTORY_RADIUS_M and
                  pd[j,i]>b.UNDERSTORY_RADIUS_M and slope[j,i]<=t["max_understory_slope"],
                  "Unsafe placement: "+str(p))
        if p["species_id"]=="sapling":
            b.require(canopy_dist[j,i]>b.UNDERSTORY_RADIUS_M,"Sapling overlaps mature canopy")
        if p["species_id"]=="reed":
            b.require(wc[j,i]+b.CELL_RADIUS<=18,"Reed too far from water")
    probes=m.get("mask_probes")
    b.require(isinstance(probes,list) and len(probes)==9,"Missing mask probes")
    for p in probes:
        i,j=b.cell_index(p["x"],p["z"])
        b.require(p["x"]==-999+2*i and p["z"]==-999+2*j and
                  p["rgba"]==mask[j,i].tolist(),"Mask probe mismatch")
    surface_probes=m.get("surface_probes")
    b.require(isinstance(surface_probes,list) and len(surface_probes)==77,"Missing surface probes")
    for p in surface_probes:
        expected=float(b.surface(h,p["x"],p["z"]))
        b.require(np.isfinite(p["height_m"]) and abs(expected-p["height_m"])<=.002,
                  "Surface probe mismatch")
    audit=geometry.audit(graph,works,mask[:,:,0]==0)
    b.require(audit["corridors"]>0 and audit["misses"]==audit["outside"]==0,"Road envelope mismatch")
    if rebuild:
        # A checksum or even geometric exclusion checks cannot distinguish a
        # legitimate ecological field from an all-zero field with valid hashes.
        # Require reproducible content, including statistics and all probes.
        current=dict(numpy=np.__version__,scipy=__import__("scipy").__version__)
        b.require(m["numeric_versions"]==current,"Numerical versions differ; install recorded versions to rebake")
        raw,expected_m,expected_u,expected_s=b.bake(root,m["seed"],t)
        b.require(raw==mask.tobytes() and expected_m==m and expected_u==u and expected_s==s,
                  "Deterministic rebake mismatch")
    return dict(placements=len(u["placements"]),mask_sha256=m["sha256"],geometry=audit,
                source_files=len(src.hashes),rebake_verified=rebuild)


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--project",required=True,type=Path)
    p.add_argument("--mask-dir",required=True,type=Path)
    p.add_argument("--structural-only",action="store_true",help="Skip exact rebake; diagnostic, not acceptance")
    args=p.parse_args()
    print(b.json_bytes(verify(args.project,args.mask_dir,rebuild=not args.structural_only)).decode(),end="")


if __name__=="__main__":
    main()
