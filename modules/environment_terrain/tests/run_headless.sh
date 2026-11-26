#!/usr/bin/env bash
# Run from any directory in a checked-out, LFS-materialized repository.
set -Eeuo pipefail
cd "$(git rev-parse --show-toplevel)"
log_dir="${TERRAIN_LOG_DIR:-/tmp/aster-terrain-tests}"
mkdir -p "$log_dir"
if [[ "${1:-}" == "--static-only" ]]; then
  node modules/environment_terrain/tests/verify_contract.cjs | tee "$log_dir/source-contract.log"
  exit 0
fi
node modules/environment_terrain/tests/verify_contract.cjs --check-lfs | tee "$log_dir/source-contract.log"
engine="${GODOT:-godot}"
version="$("$engine" --headless --version)"
[[ "$version" == 4.7.2.stable* ]] || { echo "Unexpected Godot: $version" >&2; exit 1; }
run_checked() {
  local label="$1"; shift
  timeout 420 "$engine" "$@" 2>&1 | tee "$log_dir/$label.log"
  if grep -E 'SCRIPT ERROR|Parse Error|Shader compilation failed|Shader error|Failed to load script|(^|[[:space:]])FAIL([ :]|$)' "$log_dir/$label.log"; then
    return 1
  fi
}
run_checked import --headless --path . --editor --import
run_checked terrain --headless --path . --script res://modules/environment_terrain/tests/run_tests.gd -- --production
grep -Eq '^\[EnvironmentTerrain\] [1-9][0-9]* checks, 0 failures$' "$log_dir/terrain.log" || { echo "Missing successful terrain test summary" >&2; exit 1; }
if [[ "${1:-}" == "--baseline" ]]; then
  for path in tests/integration/map_width_check.gd tests/integration/roadworks_check.gd tests/integration/world_visual_qa.gd tests/integration/garage_world.gd tests/integration/vehicle_world.gd; do
    [[ -f "$path" ]] || { echo "Missing expected base test: $path" >&2; exit 1; }
    run_checked "$(basename "$path" .gd)" --headless --path . --fixed-fps 60 --script "res://$path"
  done
fi
