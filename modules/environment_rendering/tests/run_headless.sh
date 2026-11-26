#!/usr/bin/env bash
# Owned mode imports a minimal temporary project: no LFS/world assets needed.
set -Eeuo pipefail
repo="$(cd "$(dirname "$0")/../../.." && pwd -P)"
GODOT_BIN="${GODOT_BIN:-godot}"
GODOT_BIN="$(command -v "$GODOT_BIN")" || { echo 'Godot executable unavailable' >&2; exit 2; }
GODOT_BIN="$(realpath "$GODOT_BIN")"
mode="${1:---owned}"
if [[ $# -gt 1 || ( "$mode" != --owned && "$mode" != --full ) ]]; then
  echo 'Usage: bash modules/environment_rendering/tests/run_headless.sh [--owned|--full]' >&2
  exit 2
fi
version="$(timeout --kill-after=5s 15 "$GODOT_BIN" --headless --version)"
[[ "$version" == 4.7.2.stable || "$version" == 4.7.2.stable.* ]] || { echo "Unexpected Godot: $version" >&2; exit 2; }
logdir="${RENDER_PROFILE_LOG_DIR:-$(mktemp -d)}"
mkdir -p "$logdir"
logdir="$(realpath "$logdir")"
fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT
mkdir -p "$fixture/modules/environment_rendering/tests" "$fixture/shaders"
cp "$repo/modules/environment_rendering/render_profile.gd" "$fixture/modules/environment_rendering/"
cp "$repo/modules/environment_rendering/tests/render_profile_test.gd" "$fixture/modules/environment_rendering/tests/"
cp "$repo/shaders/car_paint.gdshader" "$fixture/shaders/"
cat > "$fixture/project.godot" <<'PROJECT'
config_version=5
[application]
config/name="Agent E rendering fixture"
[rendering]
renderer/rendering_method="gl_compatibility"
PROJECT
printf 'Godot %s; logs: %s\n' "$version" "$logdir"
failed=0
run() {
  local name="$1" limit="$2" project="$3" marker="$4"
  shift 4
  local status=0 log="$logdir/$name.log"
  timeout --kill-after=10s "$limit" "$GODOT_BIN" --headless --path "$project" "$@" 2>&1 | tee "$log" || status=$?
  if [[ "$status" != 0 ]] || grep -Eq 'SCRIPT ERROR|Parse Error|Failed to load script|SHADER ERROR|Shader compilation failed|[Ee]rror compiling shader|(^|[[:space:]])FAIL([ :]|$)' "$log"; then
    echo "FAIL $name (exit $status)" >&2
    failed=1
    return 1
  fi
  # The owned suites and fixture import must not accept an engine error even
  # when the process exits zero. Existing baseline suites retain their pinned
  # error policy (known engine cleanup diagnostics may be inherited).
  if [[ "$name" == fixture-import || "$marker" == owned || "$marker" == live ]] && grep -Eq '^ERROR:' "$log"; then
    echo "FAIL $name (engine error)" >&2
    failed=1
    return 1
  fi
  if [[ "$marker" == owned ]] && ! awk '/^RENDER_PROFILE_RESULT([[:space:]]|$)/ {n++; if ($0 ~ /^RENDER_PROFILE_RESULT passed=[0-9]+ total=[0-9]+ failures=0$/) {split($2,p,"="); split($3,t,"="); if (p[2]+0 == t[2]+0 && t[2]+0 > 0) ok++}} END {exit !(n==1 && ok==1)}' "$log"; then
    echo "FAIL $name (missing or invalid completion marker)" >&2
    failed=1
    return 1
  fi
  if [[ "$marker" == live ]] && { [[ "$(grep -Ec '^LIVE_RENDER_PROFILE_RESULT([[:space:]]|$)' "$log" || true)" != 1 ]] || [[ "$(grep -Ec '^LIVE_RENDER_PROFILE_RESULT failures=0 paint_surfaces=[1-9][0-9]*$' "$log" || true)" != 1 ]]; }; then
    echo "FAIL $name (missing or invalid completion marker)" >&2
    failed=1
    return 1
  fi
  # Existing pinned regression scripts have different terminal messages.
  # Do not accept exit 0 if a suite quit before reaching its final check.
  if [[ "$marker" != none && "$marker" != owned && "$marker" != live ]]; then
    local family="$marker"
    case "$name" in
      map_width_check) family='^Map width:' ;;
      garage_world) family='^GARAGE WORLD failures:' ;;
      vehicle_world) family='^Vehicle/world integration failures:' ;;
    esac
    if [[ "$(grep -Ec "$family" "$log" || true)" != 1 || "$(grep -Ec "$marker" "$log" || true)" != 1 ]]; then
      echo "FAIL $name (missing or duplicate regression completion marker)" >&2
      failed=1
      return 1
    fi
  fi
  echo "PASS $name"
}
run fixture-import 120 "$fixture" none --editor --import || exit 1
run render-profile 120 "$fixture" owned --script res://modules/environment_rendering/tests/render_profile_test.gd || true
if [[ "$mode" == --full ]]; then
  # Refuse a full-world run against LFS pointer text, even if import exits zero.
  git -C "$repo" lfs fsck
  git -C "$repo" lfs ls-files > "$logdir/lfs-files.log"
  if grep -Eq '^[0-9a-f]+ - ' "$logdir/lfs-files.log"; then
    echo 'FAIL Git LFS pointers remain in worktree; run git lfs pull' >&2
    exit 1
  fi
  run root-import 600 "$repo" none --editor --import || exit 1
  run live-root 420 "$repo" live --fixed-fps 60 --script res://modules/environment_rendering/tests/live_root_test.gd || true
  # The pinned base contains the network_upgrade map-width data and test.
  run map_width_check 420 "$repo" '^Map width: [1-9][0-9]* edge rays, [0-9]+ isolated seam rechecks, 0 failures$' --fixed-fps 60 --script res://tests/integration/map_width_check.gd || true
  run roadworks_check 420 "$repo" '^PASS Verified five widened approaches, three water crossings and one new elevated span$' --fixed-fps 60 --script res://tests/integration/roadworks_check.gd || true
  run world_visual_qa 420 "$repo" '^PASS Live car moved on all 16 corridors, including [1-9][0-9]* gravel$' --fixed-fps 60 --script res://tests/integration/world_visual_qa.gd || true
  run garage_world 420 "$repo" '^GARAGE WORLD failures: 0$' --fixed-fps 60 --script res://tests/integration/garage_world.gd || true
  run vehicle_world 420 "$repo" '^Vehicle/world integration failures: 0$' --fixed-fps 60 --script res://tests/integration/vehicle_world.gd || true
fi
exit "$failed"
