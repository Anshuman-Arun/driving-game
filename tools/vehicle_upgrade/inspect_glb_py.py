import json, struct, os
import numpy as np

def load_glb(path):
    with open(path, "rb") as f:
        magic, ver, length = struct.unpack("<III", f.read(12))
        assert magic == 0x46546C67, f"Not a GLB: {path}"
        clen, ctype = struct.unpack("<II", f.read(8))
        assert ctype == 0x4E4F534A
        gltf = json.loads(f.read(clen).decode("utf-8"))
        blen, btype = struct.unpack("<II", f.read(8))
        assert btype == 0x004E4942
        blob = f.read(blen)
    return gltf, blob

def node_local_matrix(node):
    if "matrix" in node:
        # glTF matrix is column-major
        return np.array(node["matrix"], dtype=np.float64).reshape((4, 4), order='F')
    M = np.eye(4, dtype=np.float64)
    if "translation" in node:
        t = node["translation"]
        M[0, 3], M[1, 3], M[2, 3] = t[0], t[1], t[2]
    if "rotation" in node:
        x, y, z, w = node["rotation"]
        R = np.array([
            [1 - 2*(y*y + z*z), 2*(x*y - z*w), 2*(x*z + y*w), 0],
            [2*(x*y + z*w), 1 - 2*(x*x + z*z), 2*(y*z - x*w), 0],
            [2*(x*z - y*w), 2*(y*z + x*w), 1 - 2*(x*x + y*y), 0],
            [0, 0, 0, 1]
        ], dtype=np.float64)
        M = M @ R
    if "scale" in node:
        s = node["scale"]
        S = np.diag([s[0], s[1], s[2], 1.0])
        M = M @ S
    return M

def get_world_matrices(gltf):
    nodes = gltf.get("nodes", [])
    parents = {}
    for i, n in enumerate(nodes):
        for c in n.get("children", []):
            parents[c] = i
    cache = {}
    def world(i):
        if i in cache:
            return cache[i]
        m = node_local_matrix(nodes[i])
        if i in parents:
            m = world(parents[i]) @ m
        cache[i] = m
        return m
    return [world(i) for i in range(len(nodes))]

def read_accessor(gltf, blob, acc_idx):
    acc = gltf["accessors"][acc_idx]
    bv = gltf["bufferViews"][acc["bufferView"]]
    offset = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
    stride = bv.get("byteStride", 0)
    comp_map = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
    count_map = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}
    dtype = np.dtype(comp_map[acc["componentType"]])
    ncomp = count_map[acc["type"]]
    count = acc["count"]
    elem_bytes = dtype.itemsize * ncomp
    if stride == 0 or stride == elem_bytes:
        arr = np.frombuffer(blob, dtype=dtype, count=count * ncomp, offset=offset)
        arr = arr.reshape((count, ncomp)) if ncomp > 1 else arr.copy()
    else:
        arr = np.empty((count, ncomp) if ncomp > 1 else (count,), dtype=dtype)
        for i in range(count):
            v = np.frombuffer(blob, dtype=dtype, count=ncomp, offset=offset + i * stride)
            arr[i] = v if ncomp > 1 else v[0]
    return arr

for fname in ["porsche_918.glb"]:
    p = os.path.join(r"c:\Users\anshu\Documents\Coding\Driving-Game\driving-game\assets\forza_cars", fname)
    gltf, blob = load_glb(p)
    wm = get_world_matrices(gltf)
    print(f"=== {fname}: nodes={len(gltf.get('nodes',[]))}, meshes={len(gltf.get('meshes',[]))}, mats={len(gltf.get('materials',[]))}, extReq={gltf.get('extensionsRequired')} ===")
    print("  mats:", [m.get("name") for m in gltf.get("materials", [])])
    tot_tris = 0
    for ni, node in enumerate(gltf.get("nodes", [])):
        if "mesh" not in node:
            continue
        mesh = gltf["meshes"][node["mesh"]]
        M = wm[ni]
        for pi, prim in enumerate(mesh["primitives"]):
            pos = read_accessor(gltf, blob, prim["attributes"]["POSITION"]).astype(np.float64)
            idx = read_accessor(gltf, blob, prim["indices"]) if "indices" in prim else np.arange(len(pos))
            tris = len(idx) // 3
            tot_tris += tris
            wpos = (pos @ M[:3, :3].T) + M[:3, 3]
            mn, mx = wpos.min(axis=0), wpos.max(axis=0)
            c = (mn + mx) * 0.5
            sz = mx - mn
            mname = gltf["materials"][prim["material"]].get("name", "") if "material" in prim else ""
            if tris >= 300 or any(k in node.get("name","").lower() for k in ("wheel","tire","rim","brake","caliper","light","glass","steer")):
                print(f"  node[{ni}] '{node.get('name')}' p{pi} mat='{mname}' tris={tris} c=({c[0]:.2f},{c[1]:.2f},{c[2]:.2f}) sz=({sz[0]:.2f},{sz[1]:.2f},{sz[2]:.2f})")
    print(f"  TOTAL TRIS: {tot_tris}")
