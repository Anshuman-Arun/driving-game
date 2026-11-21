#!/usr/bin/env python3
"""Offline WAV integrity, peak/headroom, loops and determinism tests."""
import math
import pathlib
import struct
import sys
import unittest
import wave

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import synthesize

LOOPS = set(synthesize.names()) - {"gearshift", "collision", "suspension"}


class AudioAssetsTest(unittest.TestCase):
    def test_all_assets_exist_are_pcm_and_match_generation(self):
        for name in synthesize.names():
            path = ROOT / "assets" / (name + ".wav")
            with self.subTest(name=name), wave.open(str(path), "rb") as wav:
                self.assertEqual((wav.getnchannels(), wav.getsampwidth(), wav.getframerate()), (1, 2, 22050))
                self.assertGreater(wav.getnframes(), 10000)
                data = wav.readframes(wav.getnframes())
                samples = struct.unpack("<" + "h" * (len(data) // 2), data)
                self.assertEqual(samples, synthesize.generate(name))
                peak = max(abs(x) for x in samples) / 32768.0
                self.assertGreater(peak, 0.30)
                self.assertLessEqual(peak, 0.80)
                if name in LOOPS:
                    self.assertGreaterEqual(wav.getnframes() / 22050, 3.0)
                    # For periodic high-frequency waves, the last->first sample
                    # difference is a *normal* one-sample slope, not a click.
                    differences = [samples[i] - samples[i - 1] for i in range(1, len(samples))]
                    rms_delta = math.sqrt(sum(d * d for d in differences) / len(differences))
                    self.assertLess(abs(samples[0] - samples[-1]), 3.0 * rms_delta)
                    self.assertLess(abs((samples[1] - samples[0]) - (samples[-1] - samples[-2])) / 32768.0, 0.09)

    def test_engine_characteristics_are_distinct(self):
        signatures = [synthesize.generate(f"engine_{p}_mid")[:256] for p in synthesize.PROFILES]
        self.assertEqual(len(set(signatures)), 3)


if __name__ == "__main__":
    unittest.main(verbosity=2)
