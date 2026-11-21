#!/usr/bin/env bash
# Additional independently staged workstream gates. Source branches are NEVER merged.
set -Eeuo pipefail
track="${1:?track required}"
root="$(cd "${2:?feature checkout required}" && pwd)"
out="${3:?output directory required}"
ci_dir="$(cd "${4:?CI scripts directory required}" && pwd)"
world_dir="${5:-}"
traffic_module_dir="${6:-}"
mkdir -p "$out"
out="$(cd "$out" && pwd)"
summary="$out/SUMMARY.md"
failures=0

case "$track" in
  core-qa|world-runtime|game-shell|audio|race-content|racing-production|traffic-content) ;;
  *) echo "::error::Unknown expanded suite: $track" >&2; exit 2 ;;
esac
{
  printf '## %s standalone validation\n\n' "$track"
  printf 'Source SHA: `%s`\n\n' "$(git -C "$root" rev-parse HEAD)"
  if [[ -n "$world_dir" ]]; then
    world_dir="$(cd "$world_dir" && pwd)"
    printf 'Authoritative World SHA: `%s`\n\n' "$(git -C "$world_dir" rev-parse HEAD)"
  fi
  if [[ -n "$traffic_module_dir" ]]; then
    traffic_module_dir="$(cd "$traffic_module_dir" && pwd)"
    printf 'Traffic module SHA: `%s`\n\n' "$(git -C "$traffic_module_dir" rev-parse HEAD)"
  fi
  printf '| Gate | Status |\n| --- | --- |\n'
} > "$summary"

required_file() {
  if [[ ! -f "$root/$1" ]]; then
    echo "::error::Required source file missing: $1" >&2
    printf '| source file: %s | **FAIL (missing)** |\n' "$1" >> "$summary"
    failures=$((failures+1))
    return 1
  fi
}

gate() {
  local label="$1" rc
  shift
  echo "::group::$track / $label"
  printf 'Command:'; printf ' %q' "$@"; printf '\n'
  set +e
  (cd "$root" && "$@") 2>&1 | tee "$out/$label.log"
  rc=${PIPESTATUS[0]}
  set -e
  # Godot can return 0 on parser, resource and test failures. Inspect logs as a required gate.
  if [[ "$label" == godot-* ]] && grep -Eiq '(^|[[:space:]])(SCRIPT ERROR:|ERROR:|Parse Error:|FAIL:|FAILED:)' "$out/$label.log"; then
    rc=1
    echo "::error::Godot reported a parser/runtime/import/test failure in $label.log"
  fi
  if ((rc==0)); then
    printf '| %s | PASS |\n' "$label" >> "$summary"
  else
    printf '| %s | **FAIL (exit %s)** |\n' "$label" "$rc" >> "$summary"
    echo "::error::$track/$label failed; inspect $out/$label.log"
    failures=$((failures+1))
  fi
  echo "::endgroup::"
  return 0 # Try independent gates; do not hide errors.
}

case "$track" in
  core-qa)
    if required_file project.godot && required_file tests/core/steering_camera.gd; then
      gate godot-import timeout 420 godot --headless --path "$root" --editor --quit
      gate godot-core-smoke timeout 240 godot --headless --path "$root" --fixed-fps 60 --script res://tests/core/smoke.gd
      for fps in 30 60 83 144; do
        gate "godot-steering-$fps" timeout 240 godot --headless --path "$root" --fixed-fps "$fps" --script res://tests/core/steering_camera.gd
      done
    fi
    ;;
  world-runtime)
    if required_file modules/world_runtime/project.godot && required_file modules/world_runtime/tests/verify_world_data.mjs; then
      if [[ -z "$world_dir" ]] || [[ ! -f "$world_dir/data/world/terrain_height_r16le.bin" ]]; then
        printf '| authoritative World source | **FAIL (missing)** |\n' >> "$summary"
        failures=$((failures+1))
      else
        mkdir -p "$root/modules/world_runtime/.world_source"
        for filename in world_metadata_v1.json road_graph_v1.json terrain_height_r16le.bin; do
          cp "$world_dir/data/world/$filename" "$root/modules/world_runtime/.world_source/$filename"
        done
        gate world-reference node modules/world_runtime/tests/verify_world_data.mjs modules/world_runtime/.world_source
        gate godot-import timeout 600 godot --headless --path "$root/modules/world_runtime" --editor --quit
        gate godot-preview timeout 480 godot --headless --path "$root/modules/world_runtime" --script res://tests/smoke.gd
        gate godot-full-world timeout 900 godot --headless --path "$root/modules/world_runtime" --script res://tests/smoke.gd -- --full-world
      fi
    fi
    ;;
  game-shell)
    if required_file modules/game_shell/project.godot && required_file modules/game_shell/tests/run_tests.gd; then
      gate godot-import timeout 420 godot --headless --path "$root/modules/game_shell" --editor --quit
      gate godot-tests timeout 420 godot --headless --path "$root/modules/game_shell" --script res://tests/run_tests.gd
    fi
    ;;
  audio)
    if required_file modules/audio/project.godot && required_file modules/audio/tests/godot_smoke.gd; then
      export PYTHONDONTWRITEBYTECODE=1
      gate python-tests python -m unittest discover -s modules/audio/tests -v
      gate wav-regeneration python modules/audio/tools/synthesize.py
      gate wav-deterministic git diff --exit-code -- modules/audio/assets
      gate godot-import timeout 480 godot --headless --path "$root/modules/audio" --editor --quit
      gate godot-smoke timeout 300 godot --headless --path "$root/modules/audio" --script res://tests/godot_smoke.gd
    fi
    ;;
  race-content)
    if required_file content/races/author.js && required_file content/races/tests/test_author.js; then
      if [[ -z "$world_dir" ]] || [[ ! -f "$world_dir/data/world/road_graph_v1.json" ]]; then
        printf '| authoritative World graph | **FAIL (missing)** |\n' >> "$summary"
        failures=$((failures+1))
      else
        gate race-author node content/races/author.js --graph "$world_dir/data/world/road_graph_v1.json" --check
        gate race-tests node content/races/tests/test_author.js "$world_dir/data/world/road_graph_v1.json"
      fi
    fi
    ;;
  racing-production)
    if required_file modules/racing/project.godot && required_file modules/racing/tests/run_tests.gd; then
      # Reuse the original racing gates, including the strict Godot log inspection.
      bash "$ci_dir/run_workstream.sh" racing "$root" "$out" "$ci_dir"
      exit $?
    fi
    ;;
  traffic-content)
    # Branches may exist before their actual content is written. Never pass a no-op.
    if [[ ! -d "$root/content/traffic" ]]; then
      printf '| traffic content | NOT EXECUTED (no content yet) |\n' >> "$summary"
      printf '\n**NOT EXECUTED:** no traffic-content source at this SHA, not a pass.\n' >> "$summary"
      cat "$summary"
      exit 0
    fi
    if required_file content/traffic/tests/validate_content.js && required_file content/traffic/tests/run_world_scenarios.gd; then
      if [[ -z "$world_dir" || -z "$traffic_module_dir" ]]; then
        printf '| required upstream World/Traffic sources | **FAIL (missing)** |\n' >> "$summary"
        failures=$((failures+1))
      elif [[ ! -f "$world_dir/data/world/road_graph_v1.json" || ! -f "$traffic_module_dir/modules/traffic/src/traffic_simulation.gd" ]]; then
        printf '| required source files | **FAIL (missing)** |\n' >> "$summary"
        failures=$((failures+1))
      else
        gate traffic-content-node node content/traffic/tests/validate_content.js "$world_dir/data/world/road_graph_v1.json"
        # GDScript native tests import both otherwise unmerged source branches
        # plus the immutable World graph in a new throwaway project.
        integrated="$out/traffic-native-project"
        mkdir -p "$integrated/content" "$integrated/modules" "$integrated/data"
        cp -a "$root/content/traffic" "$integrated/content/traffic"
        cp -a "$traffic_module_dir/modules/traffic" "$integrated/modules/traffic"
        cp -a "$world_dir/data/world" "$integrated/data/world"
        printf 'config_version=5\n\n[application]\nconfig/name="Aster Valley Traffic Content CI"\n' > "$integrated/project.godot"
        gate godot-import timeout 600 godot --headless --path "$integrated" --editor --quit
        gate godot-traffic-smoke timeout 600 godot --headless --path "$integrated" --script res://content/traffic/tests/run_world_scenarios.gd -- --smoke
        gate godot-traffic-full timeout 900 godot --headless --path "$integrated" --script res://content/traffic/tests/run_world_scenarios.gd -- --full
      fi
    fi
    ;;
esac
if ((failures)); then
  printf '\n**FAIL:** %s required gate(s) failed. See named logs.\n' "$failures" >> "$summary"
else
  printf '\n**PASS:** all executed required headless/data gates.\n' >> "$summary"
fi
printf '\nHeadless testing does not verify graphical QA, playable integration, FPS, physical gamepads or Windows export.\n' >> "$summary"
cat "$summary"
((failures==0))
