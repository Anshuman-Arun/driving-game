import array
import math
from pathlib import Path
import shutil
import tempfile
import unittest
import wave
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import source_native_bank as bank


def plan():
    return {"rpm_basis": "fixture only", "anchors": [
        {"rpm": rpm, "layer": layer, "start_s": 0, "end_s": 1,
         "rpm_basis": "fixture", "load_basis": "fixture"}
        for layer in ("on", "off")
        for rpm in (1000, 2000, 3000, 4000, 5000, 6000, 7000, 8000)]}


class NativeBankTests(unittest.TestCase):
    def test_complete_and_reject_incomplete(self):
        good = plan()
        bank.validate(good, 900, 8700)
        for mode in ("gap", "duplicate", "unknown_load", "nan"):
            bad = plan()
            if mode == "gap":
                bad["anchors"] = [a for a in bad["anchors"] if a["rpm"] != 4000]
            elif mode == "duplicate":
                bad["anchors"].append(dict(bad["anchors"][0]))
            elif mode == "unknown_load":
                bad["anchors"][0]["load_basis"] = ""
            else:
                bad["anchors"][0]["start_s"] = float("nan")
            with self.assertRaises(ValueError):
                bank.validate(bad, 900, 8700)

    @unittest.skipUnless(shutil.which("ffmpeg"), "FFmpeg required")
    def test_native_pcm_cut(self):
        with tempfile.TemporaryDirectory() as d:
            original, output = Path(d)/"raw.wav", Path(d)/"cut.wav"
            pcm = array.array("h", (round(3000*math.sin(i*0.05)) for i in range(96000)))
            if sys.byteorder != "little":
                pcm.byteswap()
            with wave.open(str(original), "wb") as f:
                f.setparams((1, 2, 48000, 0, "NONE", "not compressed"))
                f.writeframes(pcm.tobytes())
            metrics = bank.extract(original, output, 0.5, 1.5)
            with wave.open(str(output), "rb") as f:
                self.assertEqual(f.readframes(f.getnframes()), pcm.tobytes()[48000:144000])
            self.assertEqual(metrics["duration_s"], 1.0)
            self.assertEqual(metrics["sha256"], bank.digest(output))


if __name__ == "__main__":
    unittest.main()
