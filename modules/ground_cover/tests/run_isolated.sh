#!/usr/bin/env bash
# No game assets, LFS, plugins or main-scene import needed for these fixtures.
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
stage="$(mktemp -d)"
trap 'rm -rf -- "$stage"' EXIT
GATE_LOG_DIR="$(mktemp -d)"
echo "Logs: $GATE_LOG_DIR"
mkdir -p "$stage/modules/ground_cover/tests" "$stage/modules/world_runtime/src"
for file in ground_cover.gd grass_mesh.gd grass.gdshader biome_mask.gd placement_math.gd; do
  cp "modules/ground_cover/$file" "$stage/modules/ground_cover/$file"
done
for file in fixture_world.gd numeric_engine.gd run_tests.gd mask_production.gd demo.gd demo.tscn; do
  cp "modules/ground_cover/tests/$file" "$stage/modules/ground_cover/tests/$file"
done
cp modules/world_runtime/src/road_clearance.gd "$stage/modules/world_runtime/src/road_clearance.gd"
cat > "$stage/project.godot" <<'PROJECT'
config_version=5
[application]
config/name="Aster Valley Ground Cover Isolated Fixtures"
[rendering]
renderer/rendering_method="gl_compatibility"
PROJECT
gate_run import "$engine" --headless --path "$stage" --editor --import
gate_run numeric "$engine" --headless --path "$stage" --script res://modules/ground_cover/tests/numeric_engine.gd
gate_expect numeric '^\[GroundCoverNumeric\] [1-9][0-9]* checks, 0 failures$'
gate_run fixture "$engine" --headless --path "$stage" --script res://modules/ground_cover/tests/run_tests.gd
gate_expect fixture '^\[GroundCover\] [1-9][0-9]* checks, 0 failures$'
gate_run mask "$engine" --headless --path "$stage" --script res://modules/ground_cover/tests/mask_production.gd
gate_expect mask '^\[GroundCoverMask\] [1-9][0-9]* checks, 0 failures$'
echo "Ground cover isolated fixtures PASS (headless only)"
