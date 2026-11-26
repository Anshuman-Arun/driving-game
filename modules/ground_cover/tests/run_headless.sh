#!/usr/bin/env bash
# Full game import plus owned suites; use run_isolated.sh without game assets.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../../.."
source modules/ground_cover/tests/test_gate.sh
bash modules/ground_cover/tests/test_gate_selftest.sh
node modules/ground_cover/tests/verify_numeric_source.mjs
engine="${GODOT:-godot}"
if ! command -v "$engine" >/dev/null 2>&1; then
  echo "FAIL pinned Godot executable not found: $engine" >&2
  exit 1
fi
actual="$("$engine" --headless --version)"
[[ "$actual" == 4.7.2.stable* ]] || { echo "FAIL expected Godot 4.7.2, got $actual" >&2; exit 1; }
GATE_LOG_DIR="$(mktemp -d)"
echo "Logs: $GATE_LOG_DIR"
run() { local name="$1"; shift; gate_run "$name" "$engine" --headless --path . "$@"; }
run import --editor --import
run numeric --script res://modules/ground_cover/tests/numeric_engine.gd
gate_expect numeric '^\[GroundCoverNumeric\] [1-9][0-9]* checks, 0 failures$'
run fixture --script res://modules/ground_cover/tests/run_tests.gd
gate_expect fixture '^\[GroundCover\] [1-9][0-9]* checks, 0 failures$'
run mask --script res://modules/ground_cover/tests/mask_production.gd
gate_expect mask '^\[GroundCoverMask\] [1-9][0-9]* checks, 0 failures$'
if [[ "${RUN_CANONICAL:-1}" == 1 ]]; then
  if [[ -n "${MASK_DIR:-}" ]]; then
    run canonical --script res://modules/ground_cover/tests/real_world_smoke.gd -- "--mask=$MASK_DIR"
  else
    run canonical --script res://modules/ground_cover/tests/real_world_smoke.gd
  fi
  gate_expect canonical '^\[GroundCoverRealWorld\] PASS$'
fi
if [[ "${RUN_EXISTING:-0}" == 1 ]]; then
  failed=0
  for script in tests/integration/map_width_check.gd tests/integration/roadworks_check.gd tests/integration/world_visual_qa.gd tests/integration/garage_world.gd tests/integration/vehicle_world.gd; do
    if [[ -f "$script" ]]; then
      if ! run "$(basename "$script" .gd)" --fixed-fps 60 --script "res://$script"; then failed=1; fi
    else
      echo "SKIP absent on current base: $script"
    fi
  done
  exit "$failed"
fi
