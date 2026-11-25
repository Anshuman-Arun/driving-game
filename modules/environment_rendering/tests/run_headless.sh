#!/usr/bin/env bash
# Run from any directory in a complete checkout using the pinned engine from map-regression.yml.
set -Eeuo pipefail
cd "$(dirname "$0")/../../.."
GODOT_BIN="${GODOT_BIN:-godot}"
mode="${1:---owned}"
if [[ "$mode" != --owned && "$mode" != --full ]]; then
  echo "Usage: bash modules/environment_rendering/tests/run_headless.sh [--owned|--full]" >&2
  exit 2
fi
version="$("$GODOT_BIN" --headless --version)"
[[ "$version" == 4.7.2.stable* ]] || { echo "Unexpected Godot: $version" >&2; exit 2; }
logdir="${RENDER_PROFILE_LOG_DIR:-$(mktemp -d)}"
mkdir -p "$logdir"
echo "Godot $version; logs: $logdir"
failed=0
run() {
  local name="$1" limit="$2"
  shift 2
  local status=0
  timeout "$limit" "$GODOT_BIN" --headless --path . "$@" 2>&1 | tee "$logdir/$name.log" || status=$?
  if [[ "$status" != 0 ]] || grep -Eq 'SCRIPT ERROR|Parse Error|Failed to load script|FAIL |Shader compilation failed' "$logdir/$name.log"; then
    echo "FAIL $name (exit $status)" >&2
    failed=1
    return 1
  fi
  echo "PASS $name"
}
run import 600 --editor --import || exit 1
run render-profile 120 --script res://modules/environment_rendering/tests/render_profile_test.gd || true
if [[ "$mode" == --full ]]; then
  run live-root 420 --fixed-fps 60 --script res://modules/environment_rendering/tests/live_root_test.gd || true
  for suite in roadworks_check world_visual_qa garage_world vehicle_world; do
    run "$suite" 420 --fixed-fps 60 --script "res://tests/integration/$suite.gd" || true
  done
fi
exit "$failed"
