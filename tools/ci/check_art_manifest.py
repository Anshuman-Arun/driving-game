#!/usr/bin/env python3
"""Validate explicit art rights/provenance, manifest relationships and local references."""
import json
import sys
from pathlib import Path, PurePosixPath

ALLOWED_LICENSES = {"CC0-1.0", "CC-BY-4.0", "MIT", "Apache-2.0", "BSD-2-Clause", "BSD-3-Clause"}


def validate(root: Path) -> int:
    manifest_path = root / "assets/curated/MANIFEST.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("schema_version") != 1:
        raise ValueError("manifest schema_version must be 1")
    primary = manifest.get("assets")
    supplemental = manifest.get("supplementary_variants")
    if not isinstance(primary, list) or not isinstance(supplemental, list):
        raise ValueError("primary and supplementary inventories must be arrays")
    records = primary + supplemental
    if not records:
        raise ValueError("empty art manifest")

    def source_path(rel: str, prefix: str | None = None) -> Path:
        if not isinstance(rel, str) or not rel.strip():
            raise ValueError("missing referenced path")
        relative = PurePosixPath(rel)
        if relative.is_absolute() or any(part in (".", "..") for part in relative.parts):
            raise ValueError(f"unsafe path: {rel}")
        if prefix and not rel.startswith(prefix):
            raise ValueError(f"reference outside {prefix}: {rel}")
        target = root.joinpath(*relative.parts)
        if not target.is_file() or not target.resolve().is_relative_to(root.resolve()):
            raise ValueError(f"missing or escaped reference: {rel}")
        return target

    seen_paths: set[str] = set()
    seen_ids: set[str] = set()
    triangle_sum = 0
    all_models = 0
    third_party = 0
    for asset in records:
        if not isinstance(asset, dict):
            raise ValueError("asset record is not an object")
        ident = asset.get("id")
        rel = asset.get("path")
        if not isinstance(ident, str) or not ident or ident in seen_ids:
            raise ValueError(f"missing/duplicate asset ID: {ident!r}")
        if rel in seen_paths:
            raise ValueError(f"duplicate asset path: {rel}")
        seen_ids.add(ident)
        seen_paths.add(rel)
        source_path(rel, "assets/curated/")
        license_id = asset.get("license")
        if license_id not in ALLOWED_LICENSES:
            raise ValueError(f"missing/unapproved SPDX license for {ident}: {license_id!r}")
        if not isinstance(asset.get("author"), str) or not asset["author"].strip():
            raise ValueError(f"missing author for {ident}")
        if not isinstance(asset.get("attribution_required"), bool):
            raise ValueError(f"missing attribution flag for {ident}")
        source_path(asset.get("license_evidence_file"), "assets/curated/")
        evidence_url = asset.get("license_evidence_url")
        if not isinstance(evidence_url, str) or not evidence_url.startswith("https://"):
            raise ValueError(f"missing trusted license evidence URL for {ident}")
        source_path(asset.get("source_file"))
        url = asset.get("source_url")
        if url is not None:
            if not isinstance(url, str) or not url.startswith("https://"):
                raise ValueError(f"invalid source URL for {ident}")
            third_party += 1
        if asset.get("preview"):
            source_path(asset["preview"], "assets/curated/")
        if isinstance(asset.get("triangle_count"), (int, float)):
            triangle_sum += asset["triangle_count"]
        if str(rel).endswith((".gltf", ".glb")):
            all_models += 1
            if not isinstance(asset.get("triangle_count"), int) or asset["triangle_count"] <= 0:
                raise ValueError(f"invalid triangle count for {ident}")
    counts = manifest.get("counts", {})
    for name, actual in (
        ("primary_assets", len(primary)),
        ("supplementary_variant_models", len(supplemental)),
        ("all_model_files", all_models),
        ("all_model_triangles", triangle_sum),
    ):
        if counts.get(name) != actual:
            raise ValueError(f"manifest counts.{name}={counts.get(name)!r}, actual={actual}")
    if manifest.get("third_party_asset_count") != third_party:
        raise ValueError("third_party_asset_count does not match source URLs")
    print(f"PASS: {len(records)} manifest records, {all_models} models, {triangle_sum} triangles; "
          f"{third_party} third-party sources; all file, author and license evidence links present")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(validate(Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()))
    except (ValueError, OSError, json.JSONDecodeError) as exc:
        print(f"FAIL art manifest: {exc}", file=sys.stderr)
        sys.exit(1)
