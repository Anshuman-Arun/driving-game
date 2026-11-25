import json
from pathlib import Path
import tempfile
import unittest
from qa import verify_mask, verify_assets, verify_understory, sample, digest, ERROR, payload
from report import percentile, summarize, compare, MATCH

class QA(unittest.TestCase):
    def test_mask(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp)
            data = bytearray(4_000_000)
            data[:4] = bytes((1, 2, 3, 4))
            data[4000:4004] = bytes((5, 6, 7, 8))
            data[-4:] = bytes((9, 10, 11, 12))
            manifest = dict(schema_version=1, width=1000, height=1000, cell_size_m=2,
                origin_x=-1000, origin_z=-1000, byte_order="RGBA",
                channels=["grass", "woodland", "moisture", "rock"],
                seed=42, source_hashes={"fixture": "0"*64}, sha256=digest(data))
            (path / "manifest.json").write_text(json.dumps(manifest))
            raw = path / "biome_rgba8.bin"
            raw.write_bytes(data)
            verified = verify_mask(path)
            self.assertEqual(sample(verified, -999, -999), (1,2,3,4))
            self.assertEqual(sample(verified, -999, -997), (5,6,7,8))
            self.assertEqual(sample(verified, 999, 999), (9,10,11,12))
            self.assertIsNone(sample(verified, 1000, 0))
            self.assertIsNone(sample(verified, float("nan"), 0))
            data[0] ^= 1
            raw.write_bytes(data)
            with self.assertRaises(ValueError):
                verify_mask(path)
            raw.write_bytes(b"version https://git-lfs.github.com/spec/v1")
            with self.assertRaises(ValueError):
                payload(raw)
            raw.unlink()
            with self.assertRaises(OSError):
                verify_mask(path)

    def test_report(self):
        self.assertEqual(percentile([10, 20], .5), 15)
        self.assertIsNone(percentile([], .99))
        rows = [{"frame_ms": "10", "gpu_ms": "0"}] * 99 + [{"frame_ms": "50"}]
        s = summarize(rows)
        self.assertAlmostEqual(s["one_percent_low_fps"], 20)
        self.assertEqual(s["gpu_ms"]["n"], 0)
        self.assertEqual(s["deadline_misses"], 1)
        self.assertEqual(summarize([{"frame_ms":"nan"}])["invalid_intervals"], 1)
        m = dict.fromkeys(MATCH, "same")
        m.update(scenario="stationary", traffic="enabled", audio="enabled", commit="abc", complete=True,
                 preset="medium",width=1920,height=1080,scale=1.0)
        frames = summarize([{"frame_ms": "16", "grass_instances": "1"}] * 4000)
        a, b = dict(m, mode="baseline"), dict(m, mode="candidate")
        self.assertTrue(compare((a, frames), (b, frames))["candidate_budget_met"])
        b["width"] = 1280
        self.assertFalse(compare((a, frames), (b, frames))["comparable"])
        self.assertIsNone(compare((a, frames), (b, frames))["candidate_budget_met"])

    def test_assets_and_understory(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            lod=root/"fern.glb"
            lod.write_bytes(b"fixture payload, not an imported asset")
            manifest=root/"manifest.json"
            entry=dict(species_id="fern",variant_id="one",lod0="res://fern.glb",lod1="res://fern.glb",
                dimensions_m=[1,.5,1],origin="ground_center",source_url="original fixture",
                author="QA",license="fixture",license_notice="fixture",sha256_by_path={"fern.glb":digest(lod.read_bytes())})
            manifest.write_text(json.dumps(dict(schema_version=1,assets=[entry])))
            verify_assets(manifest,root)
            lod.unlink()
            with self.assertRaises(ValueError):
                verify_assets(manifest,root)
            entry["lod0"]="../outside.glb"
            manifest.write_text(json.dumps(dict(schema_version=1,assets=[entry])))
            with self.assertRaises(ValueError):
                verify_assets(manifest,root)
            row=dict(species_id="fern",x=-999,z=999,yaw_rad=0,scale=1,seed=1)
            understory=dict(schema_version=1,seed=1,source_hashes={"fixture":"0"*64},placements=[row])
            manifest.write_text(json.dumps(understory))
            verify_understory(manifest)
            row["x"]=1000
            manifest.write_text(json.dumps(understory))
            with self.assertRaises(ValueError):
                verify_understory(manifest)
            row["x"]=float("nan")
            manifest.write_text(json.dumps(understory))
            with self.assertRaises(ValueError):
                verify_understory(manifest)

    def test_moving_and_incomplete(self):
        rows=[dict(frame_ms=16,elapsed_s=i*.016,speed_mps=22,x=i*.352,y=0,z=0,grass_instances=20) for i in range(4000)]
        summary=summarize(rows)
        m=dict.fromkeys(MATCH,"same")
        m.update(scenario="route",traffic="enabled",audio="enabled",commit="abc",complete=True,
                 preset="medium",width=1920,height=1080,scale=1.0)
        a,b=dict(m,mode="baseline"),dict(m,mode="candidate")
        self.assertTrue(compare((a,summary),(b,summary))["candidate_budget_met"])
        b["traffic"]="unverified"
        self.assertFalse(compare((a,summary),(b,summary))["comparable"])
        b["traffic"]="enabled"
        b["route_departed"]=True
        result=compare((a,summary),(b,summary))
        self.assertIsNone(result["candidate_budget_met"])
        self.assertIsNotNone(result["observed_frame_ms_delta"])

    def test_log_gate(self):
        self.assertTrue(ERROR.search("SCRIPT ERROR: Parser failed"))
        self.assertTrue(ERROR.search("FAIL route"))
        self.assertFalse(ERROR.search("PASS route"))
