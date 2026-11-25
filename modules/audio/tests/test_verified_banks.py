"""Check the frozen source plans, and that repeat installs verify rather than overwrite."""
import json
import pathlib
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]/"tools"))
import install_verified_banks as installer
import source_native_bank as bank


class VerifiedPlanTests(unittest.TestCase):
    def test_both_pinned_plans_have_valid_coverage(self):
        for profile in bank.SOURCES:
            _, plan = installer.load_plan(profile)
            self.assertEqual(len(plan["anchors"]), 17)
            self.assertTrue(plan["verified_run"].endswith("/45552767921"))

    def test_existing_files_must_match_plan_and_hash(self):
        profile = "mclaren_senna"
        _, plan = installer.load_plan(profile)
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            dest = root / profile
            dest.mkdir()
            rows = []
            for a in plan["anchors"]:
                name = "%s_%d.wav" % (a["layer"], a["rpm"])
                path = dest / name
                path.write_bytes(b"test fixture; not shipping audio")
                rows.append(dict(a, file=name, gain=.5, sha256=bank.digest(path)))
            (dest/"manifest.json").write_text(json.dumps(dict(profile=profile,status=bank.STATUS,
                source_sha256=plan["source_sha256"],loops=rows)),encoding="utf-8")
            with patch.object(bank,"fetch",side_effect=AssertionError("must not fetch")):
                self.assertEqual(installer.install(profile,root,root),dest)
                (dest / rows[0]["file"]).write_bytes(b"changed")
                with self.assertRaisesRegex(ValueError,"Move existing bank aside"):
                    installer.install(profile,root,root)

if __name__ == "__main__":
    unittest.main()
