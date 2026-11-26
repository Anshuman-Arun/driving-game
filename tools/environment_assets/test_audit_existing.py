import copy
import json
from pathlib import Path
import struct
import tempfile
import unittest
from audit_existing import inspect_glb

# Minimal container/reference fixture, not a decoded image or GPU fixture.
PAYLOAD = bytes(36) + b"\x89PNG\r\n\x1a\n"
DOC = {"asset": {"version": "2.0"}, "buffers": [{"byteLength": len(PAYLOAD)}],
       "bufferViews": [{"buffer": 0, "byteLength": 36}, {"buffer": 0, "byteOffset": 36, "byteLength": 8}],
       "accessors": [{"bufferView": 0, "type": "VEC3", "componentType": 5126, "count": 3}],
       "images": [{"bufferView": 1, "mimeType": "image/png"}], "textures": [{"source": 0}],
       "materials": [{"pbrMetallicRoughness": {"baseColorTexture": {"index": 0}}}],
       "meshes": [{"primitives": [{"attributes": {"POSITION": 0}, "material": 0}]}]}


def glb(doc, binary=PAYLOAD, swap=False):
    body = json.dumps(doc).encode()
    body += b" " * (-len(body) % 4)
    binary += b"\x00" * (-len(binary) % 4)
    chunks = [struct.pack("<I4s", len(body), b"JSON") + body,
              struct.pack("<I4s", len(binary), b"BIN\x00") + binary]
    if swap:
        chunks.reverse()
    return struct.pack("<4sII", b"glTF", 2, 12 + sum(map(len, chunks))) + b"".join(chunks)


class AuditTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.dir = Path(self.temp.name) / "scans"
        self.dir.mkdir()

    def rejected(self, modify, reason):
        doc = copy.deepcopy(DOC)
        modify(doc)
        with self.assertRaisesRegex(ValueError, reason):
            inspect_glb(glb(doc), self.dir)

    def test_valid(self):
        self.assertEqual(inspect_glb(glb(DOC), self.dir)["triangles"], 1)
        self.assertEqual(inspect_glb(glb(DOC), self.dir)["alpha_mask_materials"], 0)

    def test_pointer(self):
        with self.assertRaisesRegex(ValueError, "LFS pointer"):
            inspect_glb(b"version https://git-lfs.github.com/spec/v1\n", self.dir)

    def test_wrong_chunk_order(self):
        with self.assertRaisesRegex(ValueError, "JSON must be first"):
            inspect_glb(glb(DOC, swap=True), self.dir)

    def test_truncation(self):
        with self.assertRaisesRegex(ValueError, "invalid GLB header"):
            inspect_glb(glb(DOC)[:-1], self.dir)

    def test_bin_length(self):
        self.rejected(lambda d: d["buffers"][0].update(byteLength=1), "invalid BIN length")

    def test_view_bounds(self):
        self.rejected(lambda d: d["bufferViews"][1].update(byteOffset=999), "invalid buffer view")

    def test_missing_texture(self):
        self.rejected(lambda d: d["textures"].clear(), "invalid material texture index")

    def test_missing_image(self):
        self.rejected(lambda d: d["images"].clear(), "invalid texture image index")

    def test_missing_albedo(self):
        self.rejected(lambda d: d["materials"][0].clear(), "no base color texture bound")

    def test_missing_external_image(self):
        self.rejected(lambda d: d["images"].__setitem__(0, {"uri": "missing.png"}), "missing or unsafe external image")

    def test_external_traversal(self):
        (self.dir.parent / "outside.png").write_bytes(PAYLOAD[36:])
        self.rejected(lambda d: d["images"].__setitem__(0, {"uri": "%2e%2e/outside.png"}), "missing or unsafe external image")

    def test_image_mime(self):
        self.rejected(lambda d: d["images"][0].update(mimeType="image/jpeg"), "invalid image signature or MIME")

    def test_bad_triangle_count(self):
        self.rejected(lambda d: d["accessors"][0].update(count=4), "invalid triangle count")


if __name__ == "__main__":
    unittest.main(verbosity=2)
