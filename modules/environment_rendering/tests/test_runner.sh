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
  case "$MOCK_CASE" in
    import-error) echo 'SCRIPT ERROR: mock import parse error' ;;
    import-engine-error) echo 'ERROR: mock import resource error' ;;
  esac
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
      engine-error) printf '%s\n' 'ERROR: mock engine failure' 'RENDER_PROFILE_RESULT passed=3 total=3 failures=0' ;;
      mixed-marker) printf '%s\n' 'RENDER_PROFILE_RESULT passed=1 total=3 failures=2' 'RENDER_PROFILE_RESULT passed=3 total=3 failures=0' ;;
      assertion) echo 'FAIL mock assertion' ;;
      nonzero) echo 'RENDER_PROFILE_RESULT passed=3 total=3 failures=0'; exit 7 ;;
      timeout) exit 124 ;;
      *) echo 'RENDER_PROFILE_RESULT passed=3 total=3 failures=0' ;;
    esac ;;
  *live_root_test.gd)
    [[ "$project" == "$MOCK_REPO" ]]
    case "$MOCK_CASE" in
      live-empty) echo 'LIVE_RENDER_PROFILE_RESULT failures=0 paint_surfaces=0' ;;
      live-mixed) printf '%s\n' 'LIVE_RENDER_PROFILE_RESULT failures=1 paint_surfaces=2' 'LIVE_RENDER_PROFILE_RESULT failures=0 paint_surfaces=2' ;;
      live-engine-error) printf '%s\n' 'ERROR: mock live engine failure' 'LIVE_RENDER_PROFILE_RESULT failures=0 paint_surfaces=2' ;;
      *) echo 'LIVE_RENDER_PROFILE_RESULT failures=0 paint_surfaces=2' ;;
    esac ;;
  *)
    [[ "$project" == "$MOCK_REPO" ]]
    if [[ "$script" == *garage_world.gd ]]; then
      case "$MOCK_CASE" in
        regression) echo 'FAIL mock existing regression'; exit 0 ;;
        regression-error) echo 'ERROR: FAIL mock push_error' ;;
        regression-no-marker) exit 0 ;;
        regression-duplicate) echo 'GARAGE WORLD failures: 0' ;;
        regression-mixed) echo 'GARAGE WORLD failures: 1' ;;
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
for scenario in import-error import-engine-error no-marker zero-checks bad-count duplicate-marker mixed-marker shader-error engine-error assertion nonzero timeout; do
  check "$scenario" 1 --owned
done
check full-success 0 --full
for scenario in lfs-fsck lfs-pointer live-empty live-mixed live-engine-error regression regression-error regression-no-marker regression-duplicate regression-mixed; do
  check "$scenario" 1 --full
done
# A failure must not silently skip the remaining existing regression suites.
for scenario in regression regression-error regression-no-marker regression-duplicate regression-mixed; do
  [[ -f "$work/logs/$scenario/vehicle_world.log" ]]
done
[[ -f "$work/logs/full-success/map_width_check.log" ]]
echo "RUNNER_MOCK_RESULT passed=$count total=$count failures=0"
