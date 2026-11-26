import json
from contextlib import redirect_stdout
from io import StringIO
from pathlib import Path
import tempfile
import unittest
from qa import verify_mask, verify_assets, verify_understory, sample, digest, ERROR, payload
from report import percentile, summarize, compare, MATCH, load, png_matches, main as report_main
from qa import run_command
import sys
import struct
from unittest.mock import patch

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

    def matching_meta(self, scenario="stationary"):
        m=dict.fromkeys(MATCH,"same")
        m.update(scenario=scenario,traffic="enabled",audio="enabled",commit="a"*40,complete=True,
                 preset="medium",width=1920,height=1080,scale=1.0,sample_s=64,
                 renderer="forward_plus",gpu="GPU",cpu="CPU",driver=["driver"],car="mclaren_senna",
                 vsync="disabled",max_fps=0,capture_conditions_changed=False,
                 _screenshots_present=True,interaction=False,route_departed=False,warmup_s=15,
                 camera_start_position=[0,3,8],camera_start_forward=[0,0,-1],route_hash="f"*64)
        return (dict(m,mode="baseline",features="",legacy_grass="enabled"),
                dict(m,mode="candidate",features="a",legacy_grass="disabled"))

    def rows(self, moving=False, interval=16, duration=64):
        return [dict(frame_ms=interval,elapsed_s=(i+1)*interval/1000,speed_mps=22 if moving else 0,
                     x=i*interval/1000*22 if moving else 0,y=0,z=0,fov=58,gear="2" if moving else "N",
                     grass_instances=20,draws=100,triangles=200,gpu_ms=8,cpu_ms=4,vram_mib=1000)
                for i in range(round(duration*1000/interval))]

    def test_report(self):
        self.assertEqual(percentile([10,20],.5),15)
        self.assertIsNone(percentile([], .99))
        rows=[{"frame_ms":"10","gpu_ms":"0"}]*99+[{"frame_ms":"50"}]
        s=summarize(rows)
        self.assertAlmostEqual(s["one_percent_low_fps"],20)
        self.assertEqual(s["gpu_ms"]["n"],0)
        self.assertEqual(s["deadline_misses"],1)
        self.assertEqual(summarize([{"frame_ms":"nan"}])["invalid_intervals"],1)
        a,b=self.matching_meta()
        frames=summarize(self.rows())
        self.assertTrue(compare((a,frames),(b,frames))["candidate_budget_met"])
        b["width"]=1280
        self.assertFalse(compare((a,frames),(b,frames))["comparable"])
        self.assertIsNone(compare((a,frames),(b,frames))["candidate_budget_met"])

    def test_report_false_passes(self):
        a,b=self.matching_meta()
        good=summarize(self.rows())
        for key,value in {"legacy_grass":"enabled","features":"","commit":"b"*40,
                          "capture_conditions_changed":True,"_screenshots_present":False,
                          "renderer":"gl_compatibility","complete":False}.items():
            with self.subTest(key=key):
                self.assertIsNone(compare((a,good),(dict(b,**{key:value}),good))["candidate_budget_met"])
        for bad in (self.rows(duration=60), self.rows()[:-1]):
            self.assertFalse(compare((a,good),(b,summarize(bad)))["comparable"])
        for field,value in (("elapsed_s",1),("x","nan"),("gear",""),("grass_instances",0),("draws","")):
            rows=self.rows()
            for row in rows:
                row[field]=value
            self.assertFalse(compare((a,good),(b,summarize(rows)))["comparable"],field)
        rows=self.rows()
        rows[200]["x"]=5
        self.assertFalse(compare((a,good),(b,summarize(rows)))["comparable"])
        # Lighting-only candidate should not require grass metrics.
        rows=self.rows()
        for row in rows:
            row["grass_instances"]=""
        self.assertTrue(compare((a,good),(dict(b,features="e",legacy_grass="enabled"),summarize(rows)))["comparable"])

    def test_bad_csv_and_missing_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)
            (path/"meta.json").write_text("{}")
            (path/"frames.csv").write_text("frame_ms,frame_ms\n10,10\n")
            with self.assertRaises(ValueError):
                load(path)
            output=path/"failure.json"
            with patch.object(sys,"argv",["report.py",str(path),str(path/"missing"),"--out",str(output)]):
                self.assertEqual(report_main(),1)
            self.assertFalse(json.loads(output.read_text())["comparable"])

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
            entry["lod0"]="res://../outside.glb"
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
        summary=summarize(self.rows(moving=True))
        a,b=self.matching_meta("route")
        self.assertTrue(compare((a,summary),(b,summary))["candidate_budget_met"])
        b["traffic"]="unverified"
        self.assertFalse(compare((a,summary),(b,summary))["comparable"])
        b["traffic"]="enabled"
        b["route_departed"]=True
        result=compare((a,summary),(b,summary))
        self.assertIsNone(result["candidate_budget_met"])
        self.assertIsNotNone(result["observed_frame_ms_delta"])
        b["route_departed"]=False
        rows=self.rows(moving=True)
        for row in rows:
            row["x"]+=30
        self.assertFalse(compare((a,summary),(b,summarize(rows)))["comparable"])

    def test_png_dimension_and_truncation(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/"image.png"
            # Header/trailer fixture only; not a claim of real rendered pixels.
            head=b"\x89PNG\r\n\x1a\n"+struct.pack(">I",13)+b"IHDR"+struct.pack(">II",1920,1080)+b"\x00"*10
            tail=b"\x00\x00\x00\x00IEND\xaeB\x60\x82"
            path.write_bytes(head+tail)
            self.assertTrue(png_matches(path,1920,1080))
            self.assertFalse(png_matches(path,1280,720))
            path.write_bytes(head)
            self.assertFalse(png_matches(path,1920,1080))

    def test_timeout_and_early_log_error(self):
        with tempfile.TemporaryDirectory() as tmp:
            log=Path(tmp)/"test.log"
            with redirect_stdout(StringIO()) as captured:
                self.assertNotEqual(run_command([sys.executable,"-c","print('SCRIPT ERROR: early'); print('x'*13000)"],log,10),0)
                self.assertEqual(run_command([sys.executable,"-c","print('PASS')"],log,10),0)
                self.assertEqual(run_command([sys.executable,"-c","import time; time.sleep(5)"],log,.05),124)
                self.assertEqual(run_command([sys.executable,"-c","raise SystemExit(7)"],log,10),7)
            self.assertIn("Matched failure diagnostics",captured.getvalue())

    def test_log_gate(self):
        self.assertTrue(ERROR.search("SCRIPT ERROR: Parser failed"))
        self.assertTrue(ERROR.search("FAIL route"))
        self.assertFalse(ERROR.search("PASS route"))
