import json
import tempfile
import unittest
from pathlib import Path

import numpy as np
from scipy.spatial import cKDTree
import bake_biomes as b
import verify_road_envelope as geometry
import verify_package as package

ROOT = Path(__file__).resolve().parents[3]


class UnitTests(unittest.TestCase):
    def test_coordinates(self):
        self.assertEqual(b.cell_index(-999,-999),(0,0))
        self.assertEqual(b.cell_index(999,999),(999,999))
        self.assertEqual(b.cell_index(0,0),(500,500))
        self.assertEqual(b.cell_index(np.nextafter(1000.,-np.inf),0),(999,500))
        self.assertEqual(b.cell_index(np.nextafter(0.,-np.inf),0),(499,500))
        self.assertEqual(b.cell_index(np.nextafter(2.,-np.inf),0),(500,500))
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
        slopes=b.triangle_slope(h)
        self.assertAlmostEqual(slopes[0,0],np.hypot(4,8)/4)
        self.assertAlmostEqual(slopes[1,1],np.hypot(22,26)/4)
        self.assertEqual(slopes[0,1],slopes[1,1])
        self.assertEqual(slopes[1,0],slopes[1,1])
        with self.assertRaises(ValueError):
            b.surface(h,1001,0)
        field=np.zeros((1000,1000))
        field[500,502]=1.0
        footprint=b.footprint_slope(field)
        self.assertEqual(footprint[500,500],1.0)
        self.assertEqual(footprint[500,499],0.0)

    def test_capsule(self):
        x,z=b.coords()
        a=np.zeros(x.shape,bool)
        b.capsule(a,x,z,[-100,0],[100,0],5)
        self.assertTrue(a[500,500])
        self.assertFalse(a[510,500])
        self.assertTrue(a[500,450])
        b.capsule(a,x,z,[-10000,0],[-9000,0],2) # fully outside
        self.assertEqual(b.window(-2000,-2000,-1500,-1500),(slice(0,0),slice(0,0)))
        with self.assertRaises(ValueError):
            b.capsule(a,x,z,[0,0],[0,0],-1)

    def test_independent_geometry(self):
        lanes=[dict(id="lane_test_ab",road_id="test",surface="asphalt",width_m=3.4,
                    points=[[-100,50,-2],[0,50,-2],[100,50,-2]]),
               dict(id="lane_test_ba",road_id="test",surface="asphalt",width_m=3.4,
                    points=[[100,50,2],[0,50,2],[-100,50,2]]),
               dict(id="turn_test_corner",road_id="junction_test_corner",surface="asphalt",
                    width_m=3.4,points=[[100,50,0],[110,50,5],[112,50,15]])]
        graph=dict(lanes=lanes)
        works=dict(roads={"test":dict(center=100,width_m=12,wide_radius=80,
                    support_start=0,support_end=100)},network_upgrade=dict(
                    widths_m={"test":14},asphalt_shoulder_m=2,junction_extra_m=1))
        x,z=b.coords()
        excluded=b.road_mask(graph,works,x,z,2)
        result=geometry.audit(graph,works,excluded)
        self.assertEqual(result["misses"],0)
        self.assertEqual(result["outside"],0)
        self.assertGreater(result["bridge_samples"],0)
        self.assertGreater(result["junction_samples"],0)
        # Independent verifier must catch a damaged road cell.
        excluded[500,500]=False
        self.assertGreater(geometry.audit(graph,works,excluded)["misses"],0)

    def test_water(self):
        lake=dict(origin_x=-1000,origin_z=-1000,spacing_m=4,cells=[[1,2]])
        w=b.water_mask(lake,dict(waters=[dict(cells=[[4,5]])]))
        self.assertEqual(int(w.sum()),8)
        self.assertTrue(w[4:6,2:4].all())
        self.assertFalse(w[2,4])
        self.assertEqual(b.clearance_lower_bound(w)[4,4],0) # touching edges
        self.assertLess(b.clearance_lower_bound(w)[4,5],b.distance(w)[4,5])
        with self.assertRaises(ValueError):
            b.water_mask(dict(lake,cells=[[500,1]]),dict(waters=[]))

    def test_strict_json_and_source_replacement(self):
        for bad in ('{"a":1,"a":2}','{"a":NaN}','{"a":Infinity}','{"a":1e999}'):
            with self.assertRaises(ValueError):
                b.strict_json(bad)
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp,"source")
            p.write_bytes(b"first")
            src=b.Sources(tmp)
            self.assertEqual(src.read("source"),b"first")
            p.write_bytes(b"second")
            with self.assertRaisesRegex(ValueError,"Source changed"):
                src.read("source")
        with self.assertRaises(ValueError):
            b.bake(".",2**53)
        with self.assertRaises(ValueError):
            b.bake(".",1,[])

    def test_missing_corrupt(self):
        with tempfile.TemporaryDirectory() as tmp:
            source=b.Sources(tmp)
            with self.assertRaises(FileNotFoundError):
                source.read("missing")
            Path(tmp,"pointer").write_text("version https://git-lfs.github.com/spec/v1")
            with self.assertRaises(ValueError):
                source.read("pointer")
        meta=dict(heightfield=dict(sample_width=501,sample_height=501,spacing_m=4,
            origin_x=-1000,origin_z=-1000,row_order="z_ascending_x_ascending",
            format="uint16_le",scale_m_per_unit=.01,offset_m=0))
        with self.assertRaises(ValueError):
            b.decode_height(b"bad",meta)
        raw=bytes(4000000)
        manifest=dict(schema_version=1,width=1000,height=1000,cell_size_m=2,
            origin_x=-1000,origin_z=-1000,byte_order="RGBA",channels=b.CHANNELS,row_order="z_ascending_x_ascending",sha256=b.sha(raw))
        self.assertEqual(b.validate_mask(raw,manifest).shape,(1000,1000,4))
        with self.assertRaises(ValueError):
            b.validate_mask(raw,dict(manifest,row_order="x_ascending_z_ascending"))
        for corrupted in (raw[:-1],b"x"+raw[1:]):
            with self.assertRaises(ValueError):
                b.validate_mask(corrupted,manifest)


class FixtureTests(unittest.TestCase):
    def test_full_bake(self):
        # Entire pipeline with small source records and real-sized synthetic raster.
        # Not a replacement for the canonical acceptance test.
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            def write(name,value):
                path=root/name
                path.parent.mkdir(parents=True,exist_ok=True)
                path.write_bytes(value if isinstance(value,bytes) else b.json_bytes(value))
            regions=[dict(id=k,center=c,radius_m=400) for k,c in (
                ("alder_town",[-620,560]),("cedar_woods",[-700,-320]),
                ("north_ridge",[230,-650]),("green_valley",[45,170]),
                ("eastwater_lake",[700,450]))]
            heightfield=dict(sample_width=501,sample_height=501,spacing_m=4,
                origin_x=-1000,origin_z=-1000,row_order="z_ascending_x_ascending",
                format="uint16_le",scale_m_per_unit=.01,offset_m=0)
            meta=dict(schema_version=1,bounds=b.BOUNDS,coordinate_system="godot_y_up",
                heightfield=heightfield,regions=regions)
            write("data/world/world_metadata_v1.json",meta)
            raw=np.full((501,501),5000,dtype="<u2").tobytes()
            write("data/world/terrain_height_r16le.bin",raw)
            write("data/world/terrain_roadworks_r16le.bin",raw)
            lanes=[dict(id="lane_test_ab",road_id="test",surface="asphalt",width_m=3.4,
                points=[[-100,50,-2],[100,50,-2]]),
                dict(id="lane_test_ba",road_id="test",surface="asphalt",width_m=3.4,
                points=[[100,50,2],[-100,50,2]])]
            write("data/world/road_graph_v1.json",dict(schema_version=1,bounds=b.BOUNDS,
                coordinate_system="godot_y_up",units="meters",lanes=lanes))
            write("data/world/roadworks.json",dict(roads={"test":{"width_m":12,"center":100,"wide_radius":80,
                "bridge_start":50,"bridge_end":100}},waters=[dict(cells=[[250,255]])],
                network_upgrade=dict(widths_m={"test":14},asphalt_shoulder_m=2)))
            write("content/scenery/lake/water_cells_v1.json",dict(origin_x=-1000,
                origin_z=-1000,spacing_m=4,cells=[[250,260]]))
            write("content/scenery/avoidance/race_gate_reservations_v1.json",
                dict(zones=[dict(x=100,z=100,radius_m=10)]))
            write("content/scenery/manifest.json",dict(assets={"house":dict(r=7,kind="architecture"),
                "pine":dict(r=3,kind="natural"),"garage":dict(r=8,kind="landmark"),
                "fuel_station":dict(r=12,kind="landmark"),"pier":dict(r=6.5,kind="landmark")},region_packs=[dict(path="content/scenery/packs/test.json")]))
            write("content/scenery/packs/test.json",dict(placements=[
                dict(asset="house",position=[40,50,40],scale=1),
                dict(asset="pine",position=[60,50,60],scale=2),
                dict(asset="garage",position=[-200,50,200],scale=1),
                dict(asset="fuel_station",position=[-300,50,300],scale=1),
                dict(asset="pier",position=[200,50,200],scale=1)]))
            for name in ("vegetation.bin","premium_foliage.bin"):
                write("data/world/"+name,np.array([[80,50,80,0,1,0,.5]],dtype="<f4").tobytes())
            tuning=dict(spacing_m=24,max_placements=400)
            result=b.bake(root,123,tuning)
            self.assertEqual(result,b.bake(root,123,tuning))
            raw,manifest,understory,stats=result
            mask=b.validate_mask(raw,manifest)
            self.assertEqual(mask[500,500,0],0)
            self.assertEqual(mask[504,500,0],0) # widened deck + shoulder buffer
            self.assertEqual(mask[520,500,2],255)
            self.assertEqual(mask[550,550,0],0) # gate reservation
            self.assertEqual(mask[520,520,0],0) # building
            self.assertGreater(mask[580,520,0],100)
            for a,z in ((-200,200),(-300,300),(208,200)):
                i,j=b.cell_index(a,z)
                self.assertEqual(mask[j,i,0],0)
            x,z=b.coords()
            protected,props,canopy=b.scenery_masks(b.Sources(root),x,z)
            self.assertTrue(np.any(canopy & ~props))
            self.assertGreater(canopy.sum(),0)
            self.assertTrue(props[b.cell_index(60,60)[1],b.cell_index(60,60)[0]])
            self.assertGreater(len(understory["placements"]),0)
            self.assertLessEqual(len(understory["placements"]),400)
            self.assertAlmostEqual(stats["lane_alignment_max_m"],0)
            for p in understory["placements"]:
                self.assertTrue(-980<=p["x"]<=980 and -980<=p["z"]<=980)
            self.assertEqual(sum(stats["species"].values()),len(understory["placements"]))
            b.publish(root/"output",*result)
            report=package.verify(root,root/"output")
            self.assertEqual(report["placements"],len(understory["placements"]))
            self.assertEqual(report["geometry"]["misses"],0)
            self.assertTrue(report["rebake_verified"])
            # A zero grass field can satisfy exclusions and hashes but must
            # fail reproducibility, even when its probes have been updated.
            blank=mask.copy()
            blank[:,:,0]=0
            blank_raw=blank.tobytes()
            blank_m=b.strict_json(b.json_bytes(manifest))
            blank_m["sha256"]=b.sha(blank_raw)
            for probe in blank_m["mask_probes"]:
                probe["rgba"][0]=0
            b.publish(root/"output",blank_raw,blank_m,understory,stats)
            self.assertFalse(package.verify(root,root/"output",rebuild=False)["rebake_verified"])
            with self.assertRaisesRegex(ValueError,"Deterministic rebake mismatch"):
                package.verify(root,root/"output")
            b.publish(root/"output",*result)
            # An updated hash alone must not legitimize an unsafe placement.
            corrupt=b.strict_json(b.json_bytes(understory))
            corrupt["placements"][0]["x"]=0
            corrupt["placements"][0]["z"]=0
            bad_manifest=dict(manifest,understory_sha256=b.sha(b.json_bytes(corrupt)))
            b.publish(root/"output",raw,bad_manifest,corrupt,stats)
            with self.assertRaisesRegex(ValueError,"Unsafe placement|overlapping placements"):
                package.verify(root,root/"output")
            b.publish(root/"output",*result)
            # Corrupt mask with matching hash must still fail geometric checks.
            damaged=bytearray(raw)
            damaged[4*(500*1000+500)]=255
            b.publish(root/"output",bytes(damaged),dict(manifest,sha256=b.sha(damaged)),understory,stats)
            with self.assertRaisesRegex(ValueError,"Grass on excluded cells"):
                package.verify(root,root/"output")
            b.publish(root/"output",*result)
            path=root/"data/world/vegetation.bin"
            previous=path.read_bytes()
            path.write_bytes(previous+b"x")
            with self.assertRaisesRegex(ValueError,"Stale source"):
                package.verify(root,root/"output")
            path.write_bytes(previous)
            lock=root/"output/.bake.lock"
            lock.mkdir()
            with self.assertRaises(FileExistsError):
                b.publish(root/"output",*result)
            with self.assertRaisesRegex(ValueError,"Publication"):
                package.verify(root,root/"output")
            lock.rmdir()
            self.assertEqual((root/"output/biome_rgba8.bin").stat().st_size,4000000)
            self.assertEqual(b.sha((root/"output/understory.json").read_bytes()),
                             manifest["understory_sha256"])
            self.assertEqual(b.sha((root/"output/statistics.json").read_bytes()),manifest["statistics_sha256"])
            self.assertEqual(manifest["generator_sha256"],b.sha(Path(b.__file__).read_bytes()))
            self.assertEqual(len(manifest["mask_probes"]),9)
            for probe in manifest["mask_probes"]:
                i,j=b.cell_index(probe["x"],probe["z"])
                self.assertEqual(list(raw[4*(1000*j+i):4*(1000*j+i)+4]),probe["rgba"])
            for invalid in (dict(spacing_m=0),dict(density=2),dict(road_margin_m=-1),
                            dict(max_placements=12001),dict(spacing_m=True)):
                with self.assertRaises(ValueError):
                    b.bake(root,123,invalid)
            # Malformed lane pairs fail before generating a partial result.
            graph_path=root/"data/world/road_graph_v1.json"
            graph=json.loads(graph_path.read_text())
            original=graph_path.read_bytes()
            graph["lanes"].pop()
            graph_path.write_bytes(b.json_bytes(graph))
            with self.assertRaises(ValueError):
                b.bake(root,123,tuning)
            graph_path.write_bytes(original)
            # Optional legacy premium cache can be absent; live vegetation cannot.
            (root/"data/world/premium_foliage.bin").unlink()
            optional=b.bake(root,123,dict(tuning,max_placements=0))
            self.assertFalse(optional[1]["optional_premium_cache_used"])
            self.assertEqual(optional[2]["placements"],[])
            self.assertEqual(optional[1]["surface_probes"],manifest["surface_probes"])
            b.publish(root/"output",*optional)
            self.assertEqual(package.verify(root,root/"output")["placements"],0)
            # Required real-world inputs fail closed before publication.
            (root/"data/world/vegetation.bin").unlink()
            with self.assertRaises(FileNotFoundError):
                b.bake(root,123,tuning)


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
        protected,props,trees=b.scenery_masks(src,x,z)
        self.assertTrue(np.all(mask[:,:,0][road|wet|protected]==0))
        self.assertTrue(np.all(mask[:,:,2][wet]==255))
        audit=geometry.audit(graph,works,mask[:,:,0]==0)
        self.assertEqual(audit["misses"]+audit["outside"],0)
        self.assertEqual(audit["corridors"],16)
        self.assertEqual(audit["junctions"],11)
        self.assertGreater(audit["bridge_samples"],0)
        for lane in graph["lanes"]:
            for px,_,pz in lane["points"]:
                i,j=b.cell_index(px,pz)
                self.assertEqual(mask[j,i,0],0)
        h=b.decode_height(src.read("data/world/terrain_roadworks_r16le.bin"),
                          src.json("data/world/world_metadata_v1.json"))
        slope=b.triangle_slope(h)
        plant_slope=b.footprint_slope(slope)
        grass=mask[:,:,0].astype(float)/255
        far=((x-45)**2+(z-170)**2<250**2)&(b.distance(road)>80)&(slope<.25)&~protected&~wet
        rocky=(slope>.7)&~road&~wet&~protected
        self.assertTrue(far.any() and rocky.any())
        self.assertGreater(grass[far].mean(),.5)
        self.assertGreater(grass[far].mean(),grass[rocky].mean()+.15)
        # Interior smoothness, excluding hard safety boundaries.
        valid=(b.distance(road|wet|protected)>8)
        for axis in (0,1):
            diff=np.abs(np.diff(mask.astype(float),axis=axis))
            adjacent=(valid[:,1:]&valid[:,:-1]) if axis==1 else (valid[1:,:]&valid[:-1,:])
            self.assertLess(np.quantile(diff[adjacent],.99),65)
        self.assertLess(s["lane_alignment_max_m"],.015)
        self.assertGreater(len(u["placements"]),0)
        coords=np.array([[p["x"],p["z"]] for p in u["placements"]])
        self.assertEqual(len(cKDTree(coords).query_pairs(b.DEFAULTS["spacing_m"]*.65-.00002)),0)
        rd,wd=b.clearance_lower_bound(road),b.clearance_lower_bound(wet)
        pd=b.clearance_lower_bound(props|protected)
        wc=b.distance(wet)
        canopy_dist=b.clearance_lower_bound(trees)
        for p in u["placements"]:
            i,j=b.cell_index(p["x"],p["z"])
            self.assertIn(p["species_id"],b.SPECIES)
            self.assertFalse(props[j,i] or protected[j,i] or wet[j,i] or road[j,i])
            self.assertGreaterEqual(rd[j,i],b.DEFAULTS["sightline_m"]+b.UNDERSTORY_RADIUS_M)
            self.assertGreater(wd[j,i],b.DEFAULTS["water_margin_m"]+b.UNDERSTORY_RADIUS_M)
            self.assertGreater(pd[j,i],b.UNDERSTORY_RADIUS_M)
            self.assertLessEqual(plant_slope[j,i],b.DEFAULTS["max_understory_slope"])
            if p["species_id"]=="sapling":
                self.assertGreater(canopy_dist[j,i],b.UNDERSTORY_RADIUS_M)
            if p["species_id"]=="reed":
                self.assertLessEqual(wc[j,i]+b.CELL_RADIUS,18)


if __name__=="__main__":
    unittest.main()
