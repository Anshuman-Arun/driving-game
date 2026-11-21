# Local Visual Lab — Environment Preflight

**Date:** 2026-11-21  
**Branch / Isolation:** Separate Git worktree on branch `feat/local-visual-lab` (branched from `origin/main` at `2f6d2a7`).  
**Write Scope:** Strictly confined to `experiments/local-visual-lab/`.

## Software Versions

| Component | Status | Details |
|---|---|---|
| OS | Installed | Windows (x64) |
| Git | Installed | `git version 2.48.1.windows.1` |
| Git LFS | Installed | `git-lfs/3.6.1 (GitHub; windows amd64)` |
| Godot Engine | Installed (via WinGet, user-approved) | `Godot Engine v4.7.2.stable.official.ed1daf0bf` (standard GDScript, Windows x64) |
| Blender | Not installed | Optional; all lab geometry is procedural inside Godot 4.7.2 |

## Graphics Hardware & Display

| Adapter | Driver Version | Active Display Mode |
|---|---|---|
| NVIDIA GeForce RTX 4050 Laptop GPU (Vulkan Device #0) | `32.0.15.9282` | `3440 × 1440 @ 99 Hz` |
| Intel(R) UHD Graphics (integrated) | `31.0.101.5186` | `1920 × 1080 @ 60 Hz` |

## Vulkan Forward+ Preflight Verification

Command executed:
```powershell
& "<godot_console_exe>" --path "<repo>/experiments/local-visual-lab" --quit-after 5
```

Observed output:
```text
Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org
Vulkan 1.4.325 - Forward+ - Using Device #0: NVIDIA - NVIDIA GeForce RTX 4050 Laptop GPU
```

Exit code: `0`. Vulkan Forward+ initializes directly on the discrete NVIDIA GeForce RTX 4050 Laptop GPU with no driver or renderer fallback.

## Setup Notes

- Godot 4.7.2 was installed via official WinGet package `GodotEngine.GodotEngine` (`4.7.2`, SHA256 verified against `Godot_v4.7.2-stable_win64.exe.zip`).
- Benchmark runs target a standardized `1920 × 1080` viewport (`--resolution 1920x1080`, VSync disabled) for consistent, comparable performance measurements across rendering tiers.
