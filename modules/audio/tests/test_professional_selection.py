"""Deterministic selection coverage regression; no shipping synthesized sound."""
import pathlib
import sys
import unittest

sys.path.insert(0,str(pathlib.Path(__file__).resolve().parents[1]/"tools"))
from install_professional_banks import choose
from source_native_bank import validate

class CoverageTests(unittest.TestCase):
    def test_near_target_and_adjacent_coverage(self):
        cfg = dict(idle=900,redline=8700)
        rows = []
        for layer in ("on","off"):
            for i,rpm in enumerate([900,1800,2700,3600,4500,5400,6300,7200,8100]):
                start = 3*i+(40 if layer=="off" else 0)
                rows.append(dict(measured_rpm=rpm,start_s=start,end_s=start+.6,
                                 trend=.05 if layer=="on" else -.05,
                                 rms_dbfs=-18 if layer=="on" else -29,
                                 agreement=.6,confidence=8,full_line=12,spread=.04))
        # High-scoring edge windows would yield 5900 -> 7625, a 1725 RPM hole.
        for i,rpm in enumerate([5900,7625]):
            rows.append(dict(measured_rpm=rpm,start_s=80+2*i,end_s=80+2*i+.6,
                             trend=.25,rms_dbfs=-9,agreement=1,confidence=20,
                             full_line=100,spread=.02))
        anchors, misses = choose(rows,cfg)
        self.assertFalse(misses)
        validate(dict(rpm_basis="fixture",anchors=anchors),900,8700)
        for layer in ("on","off"):
            rpms=sorted(a["rpm"] for a in anchors if a["layer"]==layer)
            self.assertLessEqual(max(b-a for a,b in zip(rpms,rpms[1:])),1500)

if __name__=="__main__":
    unittest.main()
