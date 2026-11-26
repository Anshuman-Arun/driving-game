import base64
import unittest
from audit_alpha import alpha_stats

# Real 3x2 RGBA PNG encoded by Pillow, known alpha values 0,50,99,100,200,255.
FIXTURE = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAMAAAACCAYAAACddGYaAAAAIklEQVR4nGNkZGJmYGBgMGJgYDBkYGRiTmFkYj7ByMT8HwAP1wKoR2+cZAAAAABJRU5ErkJggg==")


class AlphaTests(unittest.TestCase):
    def test_coverage(self):
        result = alpha_stats(FIXTURE)
        self.assertEqual(result, {"width": 3, "height": 2, "below_scissor_039": 3,
                                  "above_scissor_039": 3, "coverage": 0.5, "zero": 1,
                                  "fully_opaque": 1, "partial": 4})

    def test_crc(self):
        data = bytearray(FIXTURE)
        data[50] ^= 1
        with self.assertRaisesRegex(ValueError, "CRC"):
            alpha_stats(data)

    def test_truncation(self):
        with self.assertRaisesRegex(ValueError, "PNG chunk"):
            alpha_stats(FIXTURE[:-1])

    def test_pointer(self):
        with self.assertRaisesRegex(ValueError, "signature"):
            alpha_stats(b"version https://git-lfs.github.com/spec/v1")


if __name__ == "__main__":
    unittest.main(verbosity=2)
