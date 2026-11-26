#!/usr/bin/env bash
# Exercise the gate using deliberate shell fixtures, NOT a simulated Godot pass.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source test_gate.sh
GATE_LOG_DIR="$(mktemp -d)"
trap 'rm -rf -- "$GATE_LOG_DIR"' EXIT
n=0
reject() {
  if "$@" > "$GATE_LOG_DIR/negative.log" 2>&1; then
    echo "FAIL test gate unexpectedly accepted: $*" >&2
    exit 1
  fi
  n=$((n+1))
}
gate_run clean bash -c 'printf "%s\n" "[GroundCover] 17 checks, 0 failures"'
gate_expect clean '^\[GroundCover\] [1-9][0-9]* checks, 0 failures$'
n=$((n+1))
reject gate_run exit_status bash -c 'echo ordinary; exit 7'
reject gate_run parser bash -c 'echo "SCRIPT ERROR: Parse Error: bad expression"; exit 0'
reject gate_run shader bash -c 'echo "Shader compilation failed"; exit 0'
reject gate_run error bash -c 'echo "ERROR: invalid multimesh buffer"; exit 0'
reject gate_run fixture_failure bash -c 'echo "FAIL road clearance"; exit 0'
gate_run no_marker bash -c 'echo ordinary'
reject gate_expect no_marker '^\[GroundCover\] [1-9][0-9]* checks, 0 failures$'
gate_run zero_checks bash -c 'echo "[GroundCover] 0 checks, 0 failures"'
reject gate_expect zero_checks '^\[GroundCover\] [1-9][0-9]* checks, 0 failures$'
gate_run nonzero_failures bash -c 'echo "[GroundCover] 12 checks, 1 failures"'
reject gate_expect nonzero_failures '^\[GroundCover\] [1-9][0-9]* checks, 0 failures$'
echo "GroundCover gate self-test: $n cases passed (shell only)"
