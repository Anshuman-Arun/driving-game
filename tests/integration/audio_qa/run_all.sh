#!/usr/bin/env bash
# Run from any directory. Godot 4.7.2 and hydrated Git LFS assets are required.
set -Eeuo pipefail
cd "$(dirname "$0")/../../.."
GODOT_BIN="${GODOT_BIN:-godot}"
LOG_DIR="${AUDIO_QA_LOG_DIR:-$(mktemp -d)}"
mkdir -p "$LOG_DIR"
version="$("$GODOT_BIN" --headless --version)"
[[ "$version" == 4.7.2.stable* ]] || { echo "Expected Godot 4.7.2 stable; got $version"; exit 1; }
echo "Audio QA: $version; logs: $LOG_DIR"
run_gate() {
  local label="$1"; shift
  echo "=== $label ==="
  local limit=60
  case "$label" in import) limit=240;; run_audio_qa) limit=150;; esac
  if ! timeout "$limit" "$@" 2>&1 | tee "$LOG_DIR/$label.log"; then
    echo "FAILED: $label" >&2
    return 1
  fi
  # Godot can report script/assert failures without a failing process exit.
  if grep -E 'SCRIPT ERROR:|Parse Error:|^ERROR:' "$LOG_DIR/$label.log"; then
    echo "FAILED: engine error in $label" >&2
    return 1
  fi
}
run_gate asset_integrity python3 tests/integration/audio_qa/verify_assets.py
run_gate bank_preparation_self_test python3 modules/audio/tools/prepare_recorded_bank.py self-test
run_gate import "$GODOT_BIN" --headless --path . --editor --import
failures=0
for suite in \
  modules/audio/recorded_runtime/engine/tests/test_recorded_engine.gd \
  modules/audio/recorded_runtime/tires/tests/test_recorded_tires.gd \
  modules/audio/recorded_runtime/mix/tests/test_mix_subsystem.gd \
  modules/audio/recorded_runtime/chassis/tests/test_chassis_audio.gd \
  modules/audio/recorded_runtime/chassis/tests/test_mix_integration.gd \
  modules/audio/tests/godot_smoke.gd \
  modules/audio/tests/godot_regression.gd \
  tests/integration/audio_integration_test.gd \
  tests/integration/audio_qa/test_telemetry_bench.gd \
  tests/integration/audio_qa/test_hero_live_drive.gd \
  tests/integration/audio_qa/run_audio_qa.gd; do
  if ! run_gate "$(basename "$suite" .gd)" "$GODOT_BIN" --headless --path . --script "res://$suite"; then
    failures=$((failures + 1))
  fi
done
if [[ -n "${ASTER_AUDIO_CAPTURE_DIR:-}" ]]; then
  if ! run_gate isolated_exhaust_continuity python3 tests/integration/audio_qa/analyze_hero_captures.py "$ASTER_AUDIO_CAPTURE_DIR"; then
    failures=$((failures + 1))
  fi
fi
echo "$failures audio test suites failed"
test "$failures" -eq 0
