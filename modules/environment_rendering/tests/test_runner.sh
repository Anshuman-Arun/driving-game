#!/usr/bin/env bash
# Test the shell runner's control flow with mock processes, NOT Godot behavior.
set -Eeuo pipefail
here="$(cd "$(dirname "$0")" && pwd -P)"
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
repo="$work/mock checkout"
testdir="$repo/modules/environment_rendering/tests"
mkdir -p "$testdir" "$repo/shaders" "$work/bin"
cp "$here/run_headless.sh" "$testdir/"
touch "$repo/modules/environment_rendering/render_profile.gd" "$testdir/render_profile_test.gd" "$repo/shaders/car_paint.gdshader" "$repo/project.godot"
cat > "$work/bin/mock-godot" <<'MOCK'
#!/usr/bin/env bash
set -eu
case " $* " in
  *' --version '*)
    case "$MOCK_CASE" in
      version) echo 4.6.stable ;;
      version-prefix) echo 4.7.2.stablefake ;;
      *) echo 4.7.2.stable.mock ;;
    esac
    exit 0 ;;
esac
project= script= editor=0
while (( $# )); do
  case "$1" in
    --path) project="$2"; shift ;;
    --script) script="$2"; shift ;;
    --editor) editor=1 ;;
  esac
  shift
done
[[ -f "$project/project.godot" ]]
if (( editor )); then
  if [[ "$MOCK_CASE" == import-error ]]; then echo 'SCRIPT ERROR: mock import parse error'; fi
  exit 0
fi
case "$script" in
  *render_profile_test.gd)
    [[ "$project" != "$MOCK_REPO" && -f "$project/shaders/car_paint.gdshader" ]]
    case "$MOCK_CASE" in
      no-marker) echo 'mock exited before test' ;;
      zero-checks) echo 'RENDER_PROFILE_RESULT passed=0 total=0 failures=0' ;;
      bad-count) echo 'RENDER_PROFILE_RESULT passed=1 total=2 failures=0' ;;
      duplicate-marker) printf '%s\n' 'RENDER_PROFILE_RESULT passed=3 total=3 failures=0' 'RENDER_PROFILE_RESULT passed=3 total=3 failures=0' ;;
      shader-error) printf '%s\n' 'SHADER ERROR: mock failure' 'RENDER_PROFILE_RESULT passed=3 total=3 failures=0' ;;
      assertion) echo 'FAIL mock assertion' ;;
      nonzero) echo 'RENDER_PROFILE_RESULT passed=3 total=3 failures=0'; exit 7 ;;
      timeout) exit 124 ;;
      *) echo 'RENDER_PROFILE_RESULT passed=3 total=3 failures=0' ;;
    esac ;;
  *live_root_test.gd)
    [[ "$project" == "$MOCK_REPO" ]]
    if [[ "$MOCK_CASE" == live-empty ]]; then echo 'LIVE_RENDER_PROFILE_RESULT failures=0 paint_surfaces=0'; else echo 'LIVE_RENDER_PROFILE_RESULT failures=0 paint_surfaces=2'; fi ;;
  *)
    [[ "$project" == "$MOCK_REPO" ]]
    if [[ "$script" == *garage_world.gd ]]; then
      case "$MOCK_CASE" in
        regression) echo 'FAIL mock existing regression'; exit 0 ;;
        regression-error) echo 'ERROR: FAIL mock push_error' ;;
        regression-no-marker) exit 0 ;;
        regression-duplicate) echo 'GARAGE WORLD failures: 0' ;;
      esac
    fi
    case "$script" in
      *map_width_check.gd) echo 'Map width: 1782 edge rays, 0 isolated seam rechecks, 0 failures' ;;
      *roadworks_check.gd) echo 'PASS Verified five widened approaches, three water crossings and one new elevated span' ;;
      *world_visual_qa.gd) echo 'PASS Live car moved on all 16 corridors, including 2 gravel' ;;
      *garage_world.gd) echo 'GARAGE WORLD failures: 0' ;;
      *vehicle_world.gd) echo 'Vehicle/world integration failures: 0' ;;
      *) exit 2 ;;
    esac ;;
esac
MOCK
cat > "$work/bin/git" <<'MOCK'
#!/usr/bin/env bash
set -eu
[[ "$1" == -C && "$2" == "$MOCK_REPO" && "$3" == lfs ]]
case "$4" in
  fsck) [[ "$MOCK_CASE" != lfs-fsck ]] ;;
  ls-files)
    if [[ "$MOCK_CASE" == lfs-pointer ]]; then echo '0123456789 - world.bin'; else echo '0123456789 * world.bin'; fi ;;
  *) exit 2 ;;
esac
MOCK
chmod +x "$work/bin/mock-godot" "$work/bin/git"
export PATH="$work/bin:$PATH" GODOT_BIN="$work/bin/mock-godot" MOCK_REPO="$repo"
count=0
check() {
  local scenario="$1" expected="$2" mode="$3" code=0
  export MOCK_CASE="$scenario" RENDER_PROFILE_LOG_DIR="$work/logs/$scenario"
  bash "$testdir/run_headless.sh" "$mode" > "$work/$scenario.log" 2>&1 || code=$?
  if [[ "$code" != "$expected" ]]; then
    cat "$work/$scenario.log" >&2
    echo "FAIL $scenario expected $expected got $code" >&2
    exit 1
  fi
  echo "PASS runner mock: $scenario (exit $code)"
  count=$((count+1))
}
check success 0 --owned
check version 2 --owned
check version-prefix 2 --owned
for scenario in import-error no-marker zero-checks bad-count duplicate-marker shader-error assertion nonzero timeout; do
  check "$scenario" 1 --owned
done
check full-success 0 --full
for scenario in lfs-fsck lfs-pointer live-empty regression regression-error regression-no-marker regression-duplicate; do
  check "$scenario" 1 --full
done
# A failure must not silently skip the remaining existing regression suites.
for scenario in regression regression-error regression-no-marker regression-duplicate; do
  [[ -f "$work/logs/$scenario/vehicle_world.log" ]]
done
[[ -f "$work/logs/full-success/map_width_check.log" ]]
echo "RUNNER_MOCK_RESULT passed=$count total=$count failures=0"
