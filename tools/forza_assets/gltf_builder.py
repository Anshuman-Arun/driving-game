"""Pure-Python glTF 2.0 (.glb & embedded .gltf) multi-material mesh builder with PBR textures."""
import base64
import json
import math
import struct
from pathlib import Path
import numpy as np

ROOT = Path(r"c:\Users\anshu\Documents\Coding\Driving-Game\driving-game")
PROP_TEX = ROOT / "tools" / "forza_assets" / "prop_textures"


class MaterialDef:
    def __init__(
        self,
        name: str,
        base_color=(0.8, 0.8, 0.8, 1.0),
        metallic: float = 0.0,
        roughness: float = 0.65,
        emissive=(0.0, 0.0, 0.0),
        tex_folder: str | None = None,
        normal_scale: float = 0.85,
        double_sided: bool = False,
    ):
        self.name = name
        self.base_color = list(base_color)
        self.metallic = float(metallic)
        self.roughness = float(roughness)
        self.emissive = list(emissive)
        self.tex_folder = tex_folder
        self.normal_scale = float(normal_scale)
        self.double_sided = double_sided


class MeshPart:
    """Geometry for a single material slot."""

    def __init__(self, mat: MaterialDef):
        self.mat = mat
        self.positions: list[np.ndarray] = []
        self.normals: list[np.ndarray] = []
        self.uvs: list[np.ndarray] = []
        self.indices: list[np.ndarray] = []
        self._vert_offset = 0

    def add_raw(self, pos: np.ndarray, norm: np.ndarray, uv: np.ndarray, idx: np.ndarray):
        pos = np.asarray(pos, dtype=np.float32)
        norm = np.asarray(norm, dtype=np.float32)
        uv = np.asarray(uv, dtype=np.float32)
        idx = np.asarray(idx, dtype=np.uint32) + self._vert_offset
        self.positions.append(pos)
        self.normals.append(norm)
        self.uvs.append(uv)
        self.indices.append(idx)
        self._vert_offset += len(pos)

    def add_triangles_flat(self, verts: np.ndarray, tris: np.ndarray, uv_scale: float = 0.35):
        """Expand indexed triangles to flat-shaded vertices with box-projected UVs."""
        v0 = verts[tris[:, 0]]
        v1 = verts[tris[:, 1]]
        v2 = verts[tris[:, 2]]
        e1 = v1 - v0
        e2 = v2 - v0
        fn = np.cross(e1, e2)
        lens = np.linalg.norm(fn, axis=1, keepdims=True)
        fn = fn / np.maximum(lens, 1e-8)

        n_tris = len(tris)
        out_pos = np.empty((n_tris * 3, 3), dtype=np.float32)
        out_pos[0::3] = v0
        out_pos[1::3] = v1
        out_pos[2::3] = v2

        out_norm = np.repeat(fn, 3, axis=0).astype(np.float32)

        # Box UV projection per triangle
        abs_n = np.abs(fn)
        out_uv = np.empty((n_tris, 3, 2), dtype=np.float32)
        for i in range(n_tris):
            ax, ay, az = abs_n[i]
            pts = np.stack([v0[i], v1[i], v2[i]], axis=0)
            if ay >= ax and ay >= az:
                out_uv[i, :, 0] = pts[:, 0] * uv_scale
                out_uv[i, :, 1] = pts[:, 2] * uv_scale
            elif ax >= ay and ax >= az:
                out_uv[i, :, 0] = pts[:, 2] * uv_scale
                out_uv[i, :, 1] = pts[:, 1] * uv_scale
            else:
                out_uv[i, :, 0] = pts[:, 0] * uv_scale
                out_uv[i, :, 1] = pts[:, 1] * uv_scale

        out_idx = np.arange(n_tris * 3, dtype=np.uint32)
        self.add_raw(out_pos, out_norm, out_uv.reshape(-1, 2), out_idx)

    def add_box(self, center, size, uv_scale: float = 0.35, rot_y: float = 0.0):
        cx, cy, cz = center
        hx, hy, hz = size[0] * 0.5, size[1] * 0.5, size[2] * 0.5
        verts = np.array([
            [-hx, -hy, -hz], [hx, -hy, -hz], [hx, hy, -hz], [-hx, hy, -hz],
            [-hx, -hy, hz], [hx, -hy, hz], [hx, hy, hz], [-hx, hy, hz],
        ], dtype=np.float32)
        if rot_y != 0.0:
            c, s = math.cos(rot_y), math.sin(rot_y)
            rx = verts[:, 0] * c - verts[:, 2] * s
            rz = verts[:, 0] * s + verts[:, 2] * c
            verts[:, 0], verts[:, 2] = rx, rz
        verts += np.array([cx, cy, cz], dtype=np.float32)
        tris = np.array([
            [0, 2, 1], [0, 3, 2],  # -Z
            [4, 5, 6], [4, 6, 7],  # +Z
            [0, 1, 5], [0, 5, 4],  # -Y
            [2, 3, 7], [2, 7, 6],  # +Y
            [0, 4, 7], [0, 7, 3],  # -X
            [1, 2, 6], [1, 6, 5],  # +X
        ], dtype=np.uint32)
        self.add_triangles_flat(verts, tris, uv_scale=uv_scale)

    def add_prism_extrude_x(self, profile_yz: list[tuple[float, float]], x0: float, x1: float, uv_scale: float = 0.4, cap: bool = True):
        """Extrude a closed 2D (y, z) polygon along X from x0 to x1."""
        n = len(profile_yz)
        verts = []
        for y, z in profile_yz:
            verts.append([x0, y, z])
        for y, z in profile_yz:
            verts.append([x1, y, z])
        verts = np.array(verts, dtype=np.float32)
        tris = []
        for i in range(n):
            ni = (i + 1) % n
            # Side quad
            tris.append([i, ni, n + ni])
            tris.append([i, n + ni, n + i])
        if cap and n >= 3:
            for i in range(1, n - 1):
                tris.append([0, i + 1, i])
                tris.append([n, n + i, n + i + 1])
        self.add_triangles_flat(verts, np.array(tris, dtype=np.uint32), uv_scale=uv_scale)

    def add_prism_extrude_z(self, profile_xy: list[tuple[float, float]], z0: float, z1: float, uv_scale: float = 0.4, cap: bool = True):
        """Extrude a closed 2D (x, y) polygon along Z from z0 to z1."""
        n = len(profile_xy)
        verts = []
        for x, y in profile_xy:
            verts.append([x, y, z0])
        for x, y in profile_xy:
            verts.append([x, y, z1])
        verts = np.array(verts, dtype=np.float32)
        tris = []
        for i in range(n):
            ni = (i + 1) % n
            tris.append([i, n + ni, ni])
            tris.append([i, n + i, n + ni])
        if cap and n >= 3:
            for i in range(1, n - 1):
                tris.append([0, i, i + 1])
                tris.append([n, n + i + 1, n + i])
        self.add_triangles_flat(verts, np.array(tris, dtype=np.uint32), uv_scale=uv_scale)

    def add_cylinder_y(self, center_base, r_bot: float, r_top: float, height: float, segs: int = 12, uv_scale: float = 0.6, smooth: bool = True):
        cx, cy, cz = center_base
        verts = []
        norms = []
        uvs = []
        # Side ring vertices (2 rings)
        for ring_idx, (y, r, v_coord) in enumerate([(cy, r_bot, 0.0), (cy + height, r_top, height * uv_scale)]):
            for s in range(segs + 1):
                ang = (s / segs) * 2.0 * math.pi
                ca, sa = math.cos(ang), math.sin(ang)
                verts.append([cx + ca * r, y, cz + sa * r])
                nx, nz = ca, sa
                ny = (r_bot - r_top) / max(height, 1e-4)
                ln = math.sqrt(nx * nx + ny * ny + nz * nz)
                norms.append([nx / ln, ny / ln, nz / ln])
                uvs.append([(s / segs) * 2.0 * math.pi * max(r_bot, r_top) * uv_scale, v_coord])
        tris = []
        stride = segs + 1
        for s in range(segs):
            a = s
            b = s + 1
            c = stride + s + 1
            d = stride + s
            tris.append([a, c, b])
            tris.append([a, d, c])
        if smooth:
            self.add_raw(np.array(verts), np.array(norms), np.array(uvs), np.array(tris).reshape(-1))
        else:
            self.add_triangles_flat(np.array(verts), np.array(tris), uv_scale=uv_scale)
        # Top cap
        if r_top > 1e-4:
            cap_v = np.array([[cx + math.cos(s / segs * 2 * math.pi) * r_top, cy + height, cz + math.sin(s / segs * 2 * math.pi) * r_top] for s in range(segs)], dtype=np.float32)
            cap_t = np.array([[0, i + 1, i] for i in range(1, segs - 1)], dtype=np.uint32)
            self.add_triangles_flat(cap_v, cap_t, uv_scale=uv_scale)

    def add_icosphere(self, center, radii, subdivs: int = 2, displace_fn=None, uv_scale: float = 0.6, smooth: bool = True):
        # Build unit icosahedron
        t = (1.0 + math.sqrt(5.0)) / 2.0
        verts = [
            [-1, t, 0], [1, t, 0], [-1, -t, 0], [1, -t, 0],
            [0, -1, t], [0, 1, t], [0, -1, -t], [0, 1, -t],
            [t, 0, -1], [t, 0, 1], [-t, 0, -1], [-t, 0, 1],
        ]
        verts = [np.array(v, dtype=np.float64) / np.linalg.norm(v) for v in verts]
        faces = [
            (0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11),
            (1, 5, 9), (5, 11, 4), (11, 10, 2), (10, 7, 6), (7, 1, 8),
            (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8), (3, 8, 9),
            (4, 9, 5), (2, 4, 11), (6, 2, 10), (8, 6, 7), (9, 8, 1),
        ]
        for _ in range(subdivs):
            mid_cache = {}
            new_faces = []
            def midpoint(i1, i2):
                key = (min(i1, i2), max(i1, i2))
                if key in mid_cache:
                    return mid_cache[key]
                m = (verts[i1] + verts[i2]) * 0.5
                m /= np.linalg.norm(m)
                idx = len(verts)
                verts.append(m)
                mid_cache[key] = idx
                return idx
            for a, b, c in faces:
                ab = midpoint(a, b)
                bc = midpoint(b, c)
                ca = midpoint(c, a)
                new_faces.extend([(a, ab, ca), (b, bc, ab), (c, ca, bc), (ab, bc, ca)])
            faces = new_faces

        v_arr = np.array(verts, dtype=np.float32)
        if displace_fn is not None:
            for i in range(len(v_arr)):
                v_arr[i] *= displace_fn(v_arr[i])
        v_arr[:, 0] = v_arr[:, 0] * radii[0] + center[0]
        v_arr[:, 1] = v_arr[:, 1] * radii[1] + center[1]
        v_arr[:, 2] = v_arr[:, 2] * radii[2] + center[2]
        f_arr = np.array(faces, dtype=np.uint32)

        if not smooth:
            self.add_triangles_flat(v_arr, f_arr, uv_scale=uv_scale)
        else:
            # Compute smooth vertex normals
            vnorms = np.zeros_like(v_arr)
            v0, v1, v2 = v_arr[f_arr[:, 0]], v_arr[f_arr[:, 1]], v_arr[f_arr[:, 2]]
            fn = np.cross(v1 - v0, v2 - v0)
            for k in range(3):
                np.add.at(vnorms, f_arr[:, k], fn)
            lens = np.linalg.norm(vnorms, axis=1, keepdims=True)
            vnorms /= np.maximum(lens, 1e-8)
            uv = np.stack([v_arr[:, 0] * uv_scale, v_arr[:, 1] * uv_scale + v_arr[:, 2] * uv_scale], axis=-1)
            self.add_raw(v_arr, vnorms, uv, f_arr.reshape(-1))


class GltfModel:
    def __init__(self, name: str):
        self.name = name
        self.parts: dict[str, MeshPart] = {}

    def part(self, mat: MaterialDef) -> MeshPart:
        if mat.name not in self.parts:
            self.parts[mat.name] = MeshPart(mat)
        return self.parts[mat.name]

    def bounds(self):
        all_p = [np.concatenate(p.positions, axis=0) for p in self.parts.values() if p.positions]
        pts = np.concatenate(all_p, axis=0)
        return pts.min(axis=0), pts.max(axis=0)

    def normalize(self, center_xz: bool = True, bottom_y: float | None = 0.0):
        mn, mx = self.bounds()
        dx = -0.5 * (mn[0] + mx[0]) if center_xz else 0.0
        dz = -0.5 * (mn[2] + mx[2]) if center_xz else 0.0
        dy = (bottom_y - mn[1]) if bottom_y is not None else 0.0
        shift = np.array([dx, dy, dz], dtype=np.float32)
        for p in self.parts.values():
            p.positions = [arr + shift for arr in p.positions]

    def tri_count(self) -> int:
        return sum(sum(len(i) for i in p.indices) // 3 for p in self.parts.values())

    def export(self, rel_path: str):
        out_path = ROOT / rel_path
        out_path.parent.mkdir(parents=True, exist_ok=True)
        is_glb = out_path.suffix.lower() == ".glb"

        bin_chunks = []
        buffer_views = []
        accessors = []
        materials = []
        textures = []
        images = []
        primitives = []
        tex_cache: dict[tuple[str, str], int] = {}

        def add_chunk(data: bytes, target: int | None = None) -> int:
            offset = sum(len(c) for c in bin_chunks)
            pad = (4 - (len(data) % 4)) % 4
            bin_chunks.append(data + b"\x00" * pad)
            bv = {"buffer": 0, "byteOffset": offset, "byteLength": len(data)}
            if target is not None:
                bv["target"] = target
            bv_idx = len(buffer_views)
            buffer_views.append(bv)
            return bv_idx

        def get_texture_idx(folder: str, kind: str) -> int | None:
            key = (folder, kind)
            if key in tex_cache:
                return tex_cache[key]
            img_path = PROP_TEX / folder / f"{kind}.jpg"
            if not img_path.exists():
                return None
            raw = img_path.read_bytes()
            if is_glb:
                bv_idx = add_chunk(raw)
                img_idx = len(images)
                images.append({"bufferView": bv_idx, "mimeType": "image/jpeg"})
            else:
                b64 = base64.b64encode(raw).decode("ascii")
                img_idx = len(images)
                images.append({"uri": f"data:image/jpeg;base64,{b64}"})
            tex_idx = len(textures)
            textures.append({"source": img_idx, "sampler": 0})
            tex_cache[key] = tex_idx
            return tex_idx

        for p in self.parts.values():
            if not p.positions:
                continue
            pos = np.concatenate(p.positions, axis=0).astype(np.float32)
            norm = np.concatenate(p.normals, axis=0).astype(np.float32)
            uv = np.concatenate(p.uvs, axis=0).astype(np.float32)
            idx = np.concatenate(p.indices, axis=0).astype(np.uint32)

            pos_bv = add_chunk(pos.tobytes(), 34962)
            norm_bv = add_chunk(norm.tobytes(), 34962)
            uv_bv = add_chunk(uv.tobytes(), 34962)
            idx_bv = add_chunk(idx.tobytes(), 34963)

            pos_acc = len(accessors)
            accessors.append({
                "bufferView": pos_bv, "componentType": 5126, "count": len(pos),
                "type": "VEC3",
                "min": [float(x) for x in pos.min(axis=0)],
                "max": [float(x) for x in pos.max(axis=0)],
            })
            norm_acc = len(accessors)
            accessors.append({
                "bufferView": norm_bv, "componentType": 5126, "count": len(norm), "type": "VEC3",
            })
            uv_acc = len(accessors)
            accessors.append({
                "bufferView": uv_bv, "componentType": 5126, "count": len(uv), "type": "VEC2",
            })
            idx_acc = len(accessors)
            accessors.append({
                "bufferView": idx_bv, "componentType": 5125, "count": len(idx), "type": "SCALAR",
            })

            mat = p.mat
            pbr = {
                "baseColorFactor": mat.base_color,
                "metallicFactor": mat.metallic,
                "roughnessFactor": mat.roughness,
            }
            mat_dict = {
                "name": mat.name,
                "pbrMetallicRoughness": pbr,
                "doubleSided": mat.double_sided,
            }
            if any(e > 0.0 for e in mat.emissive):
                mat_dict["emissiveFactor"] = mat.emissive
            if mat.tex_folder:
                albedo_tex = get_texture_idx(mat.tex_folder, "albedo")
                if albedo_tex is not None:
                    pbr["baseColorTexture"] = {"index": albedo_tex}
                norm_tex = get_texture_idx(mat.tex_folder, "normal")
                if norm_tex is not None:
                    mat_dict["normalTexture"] = {"index": norm_tex, "scale": mat.normal_scale}

            mat_idx = len(materials)
            materials.append(mat_dict)
            primitives.append({
                "attributes": {"POSITION": pos_acc, "NORMAL": norm_acc, "TEXCOORD_0": uv_acc},
                "indices": idx_acc,
                "material": mat_idx,
            })

        total_bin = b"".join(bin_chunks)
        gltf = {
            "asset": {"version": "2.0", "generator": "DrivingGameAssetScout/1.0"},
            "scene": 0,
            "scenes": [{"nodes": [0]}],
            "nodes": [{"name": self.name, "mesh": 0}],
            "meshes": [{"name": self.name, "primitives": primitives}],
            "materials": materials,
            "accessors": accessors,
            "bufferViews": buffer_views,
        }
        if textures:
            gltf["samplers"] = [{"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}]
            gltf["textures"] = textures
            gltf["images"] = images

        if is_glb:
            gltf["buffers"] = [{"byteLength": len(total_bin)}]
            json_bytes = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
            jpad = (4 - (len(json_bytes) % 4)) % 4
            json_bytes += b" " * jpad
            total_len = 12 + 8 + len(json_bytes) + 8 + len(total_bin)
            header = struct.pack("<III", 0x46546C67, 2, total_len)
            jchunk = struct.pack("<II", len(json_bytes), 0x4E4F534A) + json_bytes
            bchunk = struct.pack("<II", len(total_bin), 0x004E4942) + total_bin
            out_path.write_bytes(header + jchunk + bchunk)
        else:
            b64_bin = base64.b64encode(total_bin).decode("ascii")
            gltf["buffers"] = [{
                "byteLength": len(total_bin),
                "uri": f"data:application/octet-stream;base64,{b64_bin}",
            }]
            out_path.write_text(json.dumps(gltf, indent=2), encoding="utf-8")

        tris = self.tri_count()
        kb = out_path.stat().st_size // 1024
        print(f"  [export] {rel_path}: {tris} tris, {kb} KB")
        return tris
