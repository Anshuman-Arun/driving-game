#!/usr/bin/env python3
"""Static cross-workstream collision and literal resource-path preflight.

Operates ONLY on a disposable assembled checkout, never on other PR branches.
Runtime-computed resource paths still require the mandatory Godot import gate.
"""
from __future__ import annotations

import argparse
from collections import defaultdict
from pathlib import Path
import re
import sys

CLASS = re.compile(r"(?m)^\s*class_name\s+([A-Za-z_][A-Za-z0-9_]*)\b")
RESOURCE = re.compile(
    r"""(?:\bpreload\s*\(\s*["'](res://[^"']+)["']\s*\)|\bpath\s*=\s*["'](res://[^"']+)["'])"""
)
IGNORED = {".git", ".godot", "__pycache__"}


def check(root: Path) -> int:
    classes: dict[str, list[str]] = defaultdict(list)
    missing: set[tuple[str, str]] = set()
    count = 0
    for path in sorted(root.rglob("*")):
        if not path.is_file() or any(part in IGNORED for part in path.relative_to(root).parts):
            continue
        if path.suffix not in {".gd", ".tscn", ".tres"}:
            continue
        count += 1
        rel = path.relative_to(root).as_posix()
        try:
            data = path.read_text(encoding="utf-8")
        except UnicodeError:
            print(f"ERROR: Cannot decode {rel}")
            return 1
        if path.suffix == ".gd":
            for found in CLASS.finditer(data):
                classes[found.group(1)].append(rel)
        for found in RESOURCE.finditer(data):
            uri = found.group(1) or found.group(2)
            # Static only. Dynamic ResourceLoader paths are checked by Godot import.
            if not uri or "://" not in uri or not uri.startswith("res://"):
                continue
            resource = uri[len("res://"):].split("::", 1)[0]
            # Standalone modules carry their own project.godot and use
            # res:// relative to that project. Accept a path found in the
            # owning subproject OR the final integrated root, then let the
            # actual combined Godot import check runtime compatibility.
            candidates = [root]
            for ancestor in (path.parent, *path.parents):
                if ancestor == root or root not in ancestor.parents:
                    break
                if (ancestor / "project.godot").is_file():
                    candidates.append(ancestor)
                    break
            if not resource or not any((base / resource).is_file() for base in candidates):
                missing.add((rel, uri))

    duplicates = {name: paths for name, paths in classes.items() if len(paths) > 1}
    for name, paths in sorted(duplicates.items()):
        print(f"ERROR: duplicate GDScript class_name {name}: {', '.join(paths)}")
    for source, uri in sorted(missing):
        print(f"ERROR: unresolved literal resource from {source}: {uri}")

    print(f"Scanned {count} GDScript/scene/resource files; "
          f"{len(classes)} globally declared class names; "
          f"{len(duplicates)} duplicates; {len(missing)} missing literal resource files.")
    if duplicates or missing:
        print("FAIL: integrated static references (no source branch modified)")
        return 1
    print("PASS: integrated static reference preflight; runtime/import is a separate gate")
    return 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("project", type=Path, help="staged project root")
    args = parser.parse_args()
    if not (args.project / "project.godot").is_file():
        parser.error("target has no project.godot")
    sys.exit(check(args.project.resolve()))
