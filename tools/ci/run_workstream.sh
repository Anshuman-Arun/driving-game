#!/usr/bin/env bash
# Run one independently checked-out feature branch. No files are written to GitHub.
set -Eeuo pipefail
track="${1:?track required}"
worktree="$(cd "${2:?checkout directory required}" && pwd)"
out="${3:?output directory required}"
ci_dir="$(cd "${4:?CI scripts directory required}" && pwd)"
mkdir -p "$out"
out="$(cd "$out" && pwd)"
summary="$out/SUMMARY.md"
failures=0
case "$track" in core|racing|traffic|world|art) ;; *) echo "::error::Unknown workstream: $track" >&2; exit 2;; esac
{
  printf '## %s standalone validation\n\n' "$track"
  printf 'Branch checkout SHA: %s\n\n' "$(git -C "$worktree" rev-parse HEAD)"
  printf '| Required gate | Result |\n| --- | --- |\n'
} > "$summary"

run_required() {
  local name="$1" rc
  shift
  printf '::group::%s — %s\n' "$track" "$name"
  printf 'Command:'; printf ' %q' "$@"; printf '\n'
  set +e
  (cd "$worktree" && "$@") 2>&1 | tee "$out/$name.log"
  rc=${PIPESTATUS[0]}
  set -e
  # Godot 4.7.2 may exit zero even when the importer or a GDScript suite
  # reports parse/runtime errors. Those errors always invalidate a headless pass,
  # including when a compromised test runner prints a misleading PASS counter.
  if [[ "$name" == godot-import || "$name" == godot-tests || "$name" == art-import ]]; then
    if grep -Eiq '(^|[[:space:]])(SCRIPT ERROR:|ERROR:|Parse Error:|FAIL:)' "$out/$name.log"; then
      echo "::error::Godot logged a parser/runtime/import/test error in $name.log"
      rc=1
    fi
  fi
  if (( rc == 0 )); then
    printf '| %s | PASS |\n' "$name" >> "$summary"
  else
    printf '| %s | **FAIL (exit %s)** |\n' "$name" "$rc" >> "$summary"
    echo "::error::$track/$name failed (exit $rc); see retained $name.log"
  fi
  echo "::endgroup::"
  if (( rc != 0 )); then failures=$((failures + 1)); fi
  return 0 # Run remaining independent checks before failing the overall workstream.
}

case "$track" in
  core)
    test -f "$worktree/project.godot"
    test -f "$worktree/tests/core/smoke.gd"
    run_required godot-import timeout 420 godot --headless --path "$worktree" --editor --quit
    run_required godot-tests timeout 420 godot --headless --path "$worktree" --script res://tests/core/smoke.gd
    ;;
  racing)
    test -f "$worktree/modules/racing/project.godot"
    test -f "$worktree/modules/racing/tests/run_tests.gd"
    run_required godot-import timeout 600 godot --headless --path "$worktree/modules/racing" --editor --quit
    run_required godot-tests timeout 420 godot --headless --path "$worktree/modules/racing" --script res://tests/run_tests.gd
    ;;
  traffic)
    test -f "$worktree/modules/traffic/project.godot"
    test -f "$worktree/modules/traffic/tests/run_tests.gd"
    export PYTHONDONTWRITEBYTECODE=1
    run_required python-fixtures python -m unittest discover -s modules/traffic/tests -p fixture_checks.py -v
    run_required python-flow python modules/traffic/tests/reference_flow_sim.py
    run_required godot-import timeout 600 godot --headless --path "$worktree/modules/traffic" --editor --quit
    run_required godot-tests timeout 420 godot --headless --path "$worktree/modules/traffic" --script res://tests/run_tests.gd
    ;;
  world)
    test -f "$worktree/worldgen/generate.js"
    run_required world-graph node worldgen/tests/test_world.js
    run_required world-turns node worldgen/tests/test_turns.js
    run_required world-regenerate node worldgen/generate.js
    run_required world-deterministic git diff --exit-code -- data/world worldgen/previews
    ;;
  art)
    test -f "$worktree/assets/curated/MANIFEST.json"
    run_required art-structure node tools/asset_pipeline/validate.mjs
    run_required art-licenses python "$ci_dir/check_art_manifest.py" "$worktree"
    run_required art-supplementary node tools/asset_pipeline/generate.js --check
    run_required art-previews node tools/asset_pipeline/render_previews.mjs
    run_required art-environment node tools/asset_pipeline/generate_environment.mjs
    run_required art-textures node tools/asset_pipeline/generate_textures.mjs
    run_required art-deterministic git diff --exit-code -- assets/curated
    run_required art-revalidate node tools/asset_pipeline/validate.mjs
    # Art has no standalone Godot project; create a disposable one on the runner.
    if [[ -e "$worktree/project.godot" ]]; then
      echo "::error::Art branch unexpectedly contains a Godot project" >&2
      exit 1
    fi
    printf 'config_version=5\n\n[application]\nconfig/name="Aster Valley CI art importer"\n' > "$worktree/project.godot"
    run_required art-import timeout 420 godot --headless --path "$worktree" --editor --quit
    ;;
esac
{
  if (( failures == 0 )); then
    printf '\nAll required headless/data gates passed for **%s**.\n\n' "$track"
  else
    printf '\n**%s required gate(s) FAILED** for %s. Other independent gates were still attempted.\n\n' "$failures" "$track"
  fi
  printf '**NOT TESTED:** interactive rendering, visual driving competence, Xbox hardware, frame rate, Windows export, and cross-branch integration. Headless execution cannot establish these qualities.\n'
} >> "$summary"
if (( failures != 0 )); then
  echo "::error::$track has $failures failed required gate(s); inspect logs and summary."
  exit 1
fi
echo "PASS: required $track validation (headless/data only)"
