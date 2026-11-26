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
[[ "$version" == 4.7.2.stable* ]] || { echo "Unexpected Godot: $version" >&2; exit 2; }
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
  if [[ "$status" != 0 ]] || grep -Eq 'SCRIPT ERROR|Parse Error|Failed to load script|SHADER ERROR|Shader compilation failed|[Ee]rror compiling shader|^FAIL([ :]|$)' "$log"; then
    echo "FAIL $name (exit $status)" >&2
    failed=1
    return 1
  fi
  if [[ "$marker" == owned ]] && ! awk '/^RENDER_PROFILE_RESULT passed=[0-9]+ total=[0-9]+ failures=0$/ {n++; split($2,p,"="); split($3,t,"="); if (p[2]+0 == t[2]+0 && t[2]+0 > 0) ok++} END {exit !(n==1 && ok==1)}' "$log"; then
    echo "FAIL $name (missing or invalid completion marker)" >&2
    failed=1
    return 1
  fi
  if [[ "$marker" == live ]] && [[ "$(grep -Ec '^LIVE_RENDER_PROFILE_RESULT failures=0 paint_surfaces=[1-9][0-9]*$' "$log" || true)" != 1 ]]; then
    echo "FAIL $name (missing or invalid completion marker)" >&2
    failed=1
    return 1
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
  for suite in roadworks_check world_visual_qa garage_world vehicle_world; do
    run "$suite" 420 "$repo" none --fixed-fps 60 --script "res://tests/integration/$suite.gd" || true
  done
fi
exit "$failed"
