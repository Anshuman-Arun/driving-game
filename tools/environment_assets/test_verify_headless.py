"""Subprocess fixtures test the gate itself; they are not Godot results."""
import contextlib
import io
import json
import sys
import unittest
from verify_headless import run, validate_report


class RunnerTests(unittest.TestCase):
    def launch(self, code, marker=None, engine=False, timeout=2):
        with contextlib.redirect_stdout(io.StringIO()):
            return run([sys.executable, "-c", code], timeout, marker, engine)

    def test_success(self):
        self.assertIn("done", self.launch("print('done')", "done"))

    def test_exit_code(self):
        with self.assertRaisesRegex(RuntimeError, "failed command"):
            self.launch("print('done');raise SystemExit(7)", "done")

    def test_script_error_zero_exit(self):
        with self.assertRaisesRegex(RuntimeError, "failed command"):
            self.launch("print('SCRIPT ERROR: broken');print('done')", "done", True)

    def test_error_on_stderr(self):
        with self.assertRaisesRegex(RuntimeError, "failed command"):
            self.launch("import sys;print('ERROR: bad shader',file=sys.stderr);print('done')", "done", True)

    def test_missing_marker(self):
        with self.assertRaisesRegex(RuntimeError, "missing completion marker"):
            self.launch("print('not done')", "done")

    def test_timeout(self):
        with self.assertRaisesRegex(RuntimeError, "timed out"):
            self.launch("import time;print('started',flush=True);time.sleep(5)", timeout=0.1)

    def test_bad_report(self):
        with self.assertRaisesRegex(RuntimeError, "incomplete Node validation report"):
            validate_report(json.dumps({"negative_fixtures": 30}))

    def test_valid_report(self):
        validate_report(json.dumps({"negative_fixtures": 30, "rejected": [f"fixture {i}" for i in range(30)],
                                    "sha256_vectors": 2, "determinism": True, "lod_shared_scaffold": True,
                                    "report": [{"species": x, "lod0": 100, "lod1": 50, "bytes": 1000} for x in ["fern", "reed", "sapling", "shrub", "wildflower"]]}))


if __name__ == "__main__":
    unittest.main(verbosity=2)
