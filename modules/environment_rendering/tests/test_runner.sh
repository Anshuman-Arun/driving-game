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
    if [[ "$MOCK_CASE" == version ]]; then echo 4.6.stable; else echo 4.7.2.stable.mock; fi
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
    if [[ "$MOCK_CASE" == regression && "$script" == *garage_world.gd ]]; then echo 'FAIL mock existing regression'; fi ;;
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
for scenario in import-error no-marker zero-checks bad-count duplicate-marker shader-error assertion nonzero timeout; do
  check "$scenario" 1 --owned
done
check full-success 0 --full
for scenario in lfs-fsck lfs-pointer live-empty regression; do
  check "$scenario" 1 --full
done
# A failure must not silently skip the remaining existing regression suites.
[[ -f "$work/logs/regression/vehicle_world.log" ]]
echo "RUNNER_MOCK_RESULT passed=$count total=$count failures=0"
