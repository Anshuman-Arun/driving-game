import json
import tempfile
import unittest
from pathlib import Path

import numpy as np
from scipy.spatial import cKDTree
import bake_biomes as b

ROOT = Path(__file__).resolve().parents[3]


class UnitTests(unittest.TestCase):
    def test_coordinates(self):
        self.assertEqual(b.cell_index(-999,-999),(0,0))
        self.assertEqual(b.cell_index(999,999),(999,999))
        self.assertEqual(b.cell_index(0,0),(500,500))
        for x,z in [(1000,0),(0,1000),(-1000.01,0)]:
            with self.assertRaises(ValueError):
                b.cell_index(x,z)
        x,z=b.coords()
        self.assertEqual((x[0,1],z[0,1]),(-997,-999))
        self.assertEqual((x[1,0],z[1,0]),(-999,-997))

    def test_triangles(self):
        h=np.zeros((501,501))
        h[:2,:2]=[[10,14],[18,40]]
        self.assertAlmostEqual(float(b.surface(h,-999,-999)),13)
        self.assertAlmostEqual(float(b.surface(h,-997,-997)),28)
        self.assertAlmostEqual(float(b.surface(h,-998,-998)),16)
        self.assertEqual(float(b.surface(h,-996,-996)),40)
        with self.assertRaises(ValueError):
            b.surface(h,1001,0)

    def test_capsule(self):
        x,z=b.coords()
        a=np.zeros(x.shape,bool)
        b.capsule(a,x,z,[-100,0],[100,0],5)
        self.assertTrue(a[500,500])
        self.assertFalse(a[510,500])
        self.assertTrue(a[500,450])

    def test_water(self):
        lake=dict(origin_x=-1000,origin_z=-1000,spacing_m=4,cells=[[1,2]])
        w=b.water_mask(lake,dict(waters=[dict(cells=[[4,5]])]))
        self.assertEqual(int(w.sum()),8)
        self.assertTrue(w[4:6,2:4].all())
        self.assertFalse(w[2,4])
        with self.assertRaises(ValueError):
            b.water_mask(dict(lake,cells=[[500,1]]),dict(waters=[]))

    def test_missing_corrupt(self):
        with tempfile.TemporaryDirectory() as tmp:
            source=b.Sources(tmp)
            with self.assertRaises(FileNotFoundError):
                source.read("missing")
            Path(tmp,"pointer").write_text("version https://git-lfs.github.com/spec/v1")
            with self.assertRaises(ValueError):
                source.read("pointer")
        meta=json.loads((ROOT/"data/world/world_metadata_v1.json").read_text())
        with self.assertRaises(ValueError):
            b.decode_height(b"bad",meta)
        raw=bytes(4000000)
        manifest=dict(schema_version=1,width=1000,height=1000,cell_size_m=2,
            origin_x=-1000,origin_z=-1000,byte_order="RGBA",channels=b.CHANNELS,sha256=b.sha(raw))
        self.assertEqual(b.validate_mask(raw,manifest).shape,(1000,1000,4))
        for corrupted in (raw[:-1],b"x"+raw[1:]):
            with self.assertRaises(ValueError):
                b.validate_mask(corrupted,manifest)


class CanonicalTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.result=b.bake(ROOT,20261121)

    def test_repeatable_and_publish(self):
        raw,m,u,s=self.result
        self.assertEqual(self.result,b.bake(ROOT,20261121))
        with tempfile.TemporaryDirectory() as tmp:
            b.publish(tmp,*self.result)
            self.assertEqual(Path(tmp,"biome_rgba8.bin").read_bytes(),raw)
            self.assertEqual(json.loads(Path(tmp,"manifest.json").read_text()),m)
        for name,digest in m["source_hashes"].items():
            self.assertEqual(b.sha((ROOT/name).read_bytes()),digest)

    def test_exclusions_and_ecology(self):
        raw,m,u,s=self.result
        mask=b.validate_mask(raw,m)
        x,z=b.coords()
        src=b.Sources(ROOT)
        graph=src.json("data/world/road_graph_v1.json")
        works=src.json("data/world/roadworks.json")
        lake=src.json("content/scenery/lake/water_cells_v1.json")
        road=b.road_mask(graph,works,x,z,b.DEFAULTS["road_margin_m"])
        wet=b.water_mask(lake,works)
        protected,props,_=b.scenery_masks(src,x,z)
        self.assertTrue(np.all(mask[:,:,0][road|wet|protected]==0))
        self.assertTrue(np.all(mask[:,:,2][wet]==255))
        for lane in graph["lanes"]:
            for px,_,pz in lane["points"]:
                i,j=b.cell_index(px,pz)
                self.assertEqual(mask[j,i,0],0)
        h=b.decode_height(src.read("data/world/terrain_roadworks_r16le.bin"),
                          src.json("data/world/world_metadata_v1.json"))
        dz,dx=np.gradient(b.surface(h,x,z),2)
        slope=np.hypot(dx,dz)
        grass=mask[:,:,0].astype(float)/255
        far=((x-45)**2+(z-170)**2<250**2)&(b.distance(road)>80)&(slope<.25)&~protected&~wet
        rocky=(slope>.7)&~road&~wet&~protected
        self.assertTrue(far.any() and rocky.any())
        self.assertGreater(grass[far].mean(),.5)
        self.assertGreater(grass[far].mean(),grass[rocky].mean()+.15)
        # Interior smoothness, excluding hard safety boundaries.
        valid=(b.distance(road|wet|protected)>8)
        diff=np.abs(np.diff(mask.astype(float),axis=1))
        self.assertLess(np.quantile(diff[valid[:,1:]&valid[:,:-1]],.99),65)
        self.assertLess(s["lane_alignment_max_m"],.015)
        self.assertGreater(len(u["placements"]),0)
        coords=np.array([[p["x"],p["z"]] for p in u["placements"]])
        self.assertEqual(len(cKDTree(coords).query_pairs(b.DEFAULTS["spacing_m"]*.65-.00002)),0)
        rd,wd=b.distance(road),b.distance(wet)
        for p in u["placements"]:
            i,j=b.cell_index(p["x"],p["z"])
            self.assertIn(p["species_id"],b.SPECIES)
            self.assertFalse(props[j,i] or protected[j,i] or wet[j,i] or road[j,i])
            self.assertGreaterEqual(rd[j,i],b.DEFAULTS["sightline_m"])
            self.assertGreater(wd[j,i],b.DEFAULTS["water_margin_m"])


if __name__=="__main__":
    unittest.main()
