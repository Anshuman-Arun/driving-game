"""Offline fixture for publisher ignoring Range and serving a ZIP."""
import hashlib
import io
import pathlib
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "tools"))
import professional_reference as reference

class Response(io.BytesIO):
    status = 200
    def __init__(self, data):
        super().__init__(data)
        self.headers = {"Content-Length": str(len(data)),
                        "Content-Type": "application/octet-stream"}

class DownloadTests(unittest.TestCase):
    def test_http_200_fallback_extracts_and_hashes_member(self):
        wav = b"RIFF" + b"fixture bytes"
        archive = io.BytesIO()
        with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as z:
            z.writestr("nested/test.wav", wav)
        cfg = {"url": "https://example.com/library.zip", "file": "test.wav", "offset": 0}
        with tempfile.TemporaryDirectory() as tmp:
            dest = pathlib.Path(tmp) / "take.wav"
            with patch.object(reference.urllib.request, "urlopen",
                              side_effect=lambda *a, **kw: Response(archive.getvalue())):
                result = reference.acquire(cfg, dest)
            self.assertEqual(dest.read_bytes(), wav)
            self.assertEqual(result, hashlib.sha256(wav).hexdigest())
            self.assertFalse(dest.with_suffix(".zip").exists())

    def test_reject_html_response_and_cleanup(self):
        cfg = {"url": "https://example.com/library.zip", "file": "test.wav"}
        with tempfile.TemporaryDirectory() as tmp:
            dest = pathlib.Path(tmp) / "take.wav"
            with patch.object(reference.urllib.request, "urlopen",
                              side_effect=lambda *a, **kw: Response(b"<html>not a ZIP</html>")):
                with self.assertRaises(ValueError):
                    reference.acquire_full(cfg, dest)
            self.assertFalse(dest.exists())
            self.assertFalse(dest.with_suffix(".zip").exists())

if __name__ == "__main__":
    unittest.main()
