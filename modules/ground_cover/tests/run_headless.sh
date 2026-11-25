#!/usr/bin/env bash
# Run from repository root with Godot 4.7.2 installed and LFS payloads fetched.
set -euo pipefail
engine="${GODOT:-godot}"
[[ "$("$engine" --headless --version)" == 4.7.2.stable* ]]
logdir="$(mktemp -d)"
echo "Logs: $logdir"
run() {
  local name="$1"; shift
  timeout 420 "$engine" --headless --path . "$@" 2>&1 | tee "$logdir/$name.log"
  if grep -E 'SCRIPT ERROR|Parse Error|Failed to load script|Shader compilation failed|FAIL ' "$logdir/$name.log"; then return 1; fi
}
run import --editor --import
run fixture --script res://modules/ground_cover/tests/run_tests.gd
run canonical --script res://modules/ground_cover/tests/real_world_smoke.gd
if [[ "${RUN_EXISTING:-0}" == 1 ]]; then
  for script in tests/integration/map_width_check.gd tests/integration/roadworks_check.gd tests/integration/world_visual_qa.gd tests/integration/garage_world.gd tests/integration/vehicle_world.gd; do
    if [[ -f "$script" ]]; then
      run "$(basename "$script" .gd)" --fixed-fps 60 --script "res://$script"
    fi
  done
fi
