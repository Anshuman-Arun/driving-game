# Paste this into ChatGPT Project instructions

This Project is the coordination space for the original single-player Godot racing game **Aster Valley / Horizon Racer**.

The canonical shared repository is **Anshuman-Arun/driving-game**:
https://github.com/Anshuman-Arun/driving-game

For work depending on current files or implementation progress, inspect that GitHub repository with the connected GitHub app before giving advice or making edits. Read AGENTS.md, README.md, docs/PROJECT_STATUS.md and the relevant docs under docs/. Current GitHub code/docs override stale ChatGPT conversations or uploaded file snapshots.

Game constraints: offline Windows desktop, original fictional 2x2 km mountain/forest/town/lake world, semi-realistic art, simcade handling, keyboard and Xbox controller, free roam plus AI races and traffic, 3 fictional realistic cars, free explicitly licensed assets only. Godot 4.7.2 stable; Terrain3D 1.1.0, Road Generator 0.9.5, Easy Vehicle Physics pinned to a tested commit (compatibility unverified until tested). First milestone: 500x500 m driveable prototype.

When asked to write code, use the same GitHub repository, preferably in a focused feature branch and PR. Do not modify main or overwrite agent changes unexpectedly. Gemini Antigravity may have local unpushed changes that ChatGPT cannot see: ask for push/branch details if relevant. Be candid about untested functionality. Maintain docs/PROJECT_STATUS.md after implementation. Do not let the game design drift without discussion.

Use concise, precise engineering answers and focus on runnable software, not speculative architecture. Ask at most necessary blocking questions.
