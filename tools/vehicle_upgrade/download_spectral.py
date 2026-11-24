#!/usr/bin/env python3
"""Fetch ONLY the audited, freely downloadable CC0 source GLB.

Use on a connected development PC at build time; no network is required by
the released game. Source must pass Git object SHA verification before use.
Requires no token, storefront login, or commercial entitlement.
"""
from __future__ import annotations
import argparse
import hashlib
from pathlib import Path
import tempfile
from urllib.request import Request, urlopen

UPSTREAM_COMMIT = "34499c501908818a2b08e589a7aecf963343cee7"
ASSET_NAME = "spectral_gt_rs_game_ready.glb"
UPSTREAM = "https://raw.githubusercontent.com/JaronKBragg7337/spectral-gt-rs/" + UPSTREAM_COMMIT + "/" + ASSET_NAME
EXPECTED_BLOB_SHA1 = "f5b814848453a6c75a48f5047fdadaa7bdc78969"
EXPECTED_BYTE_COUNT = 4_688_844


def git_blob_sha(data: bytes) -> str:
    return hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=Path("assets/vehicle_upgrade/source/spectral_gt_rs_game_ready.glb"))
    parser.add_argument("--source", type=Path, help="Offline lawful GLB supplied by artist, verified against pinned upstream SHA")
    args = parser.parse_args()
    if args.source:
        data = args.source.read_bytes()
    else:
        # Source is explicitly CC0 at the revision above. Never fetch through
        # an authenticated/gated catalog, viewer cache, or marketplace scrape.
        req = Request(UPSTREAM, headers={"User-Agent": "AsterValleyVehicleUpgrade/1.0"})
        with urlopen(req, timeout=90) as response:
            data = response.read(EXPECTED_BYTE_COUNT + 1)
    if len(data) != EXPECTED_BYTE_COUNT or git_blob_sha(data) != EXPECTED_BLOB_SHA1:
        raise SystemExit("REFUSED: downloaded bytes differ from audited CC0 repository source")
    if data[:4] != b"glTF":
        raise SystemExit("REFUSED: input is not a GLB")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=args.output.parent, delete=False) as temp:
        temp.write(data)
        intermediate = Path(temp.name)
    intermediate.replace(args.output)
    print(f"Verified CC0 source: {args.output} ({len(data)} bytes)")
    print(f"SHA-256: {hashlib.sha256(data).hexdigest()}")
    print("Source:", UPSTREAM)


if __name__ == "__main__":
    main()
