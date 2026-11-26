#!/usr/bin/env bash
# Shared strict gate. Source this file; the caller sets GATE_LOG_DIR.
gate_run() {
  local name="$1"; shift
  local log="$GATE_LOG_DIR/$name.log"
  if timeout --kill-after=10 420 "$@" 2>&1 | tee "$log"; then
    :
  else
    local status=$?
    printf 'FAIL %s: command/tee exited %s\n' "$name" "$status" >&2
    return "$status"
  fi
  if grep -E 'SCRIPT ERROR|Parse Error|Failed to load script|Shader compilation failed|Shader error|ERROR:|FAIL ' "$log"; then
    printf 'FAIL %s: error marker\n' "$name" >&2
    return 1
  fi
}
gate_expect() {
  local name="$1" pattern="$2"
  if ! grep -Eq "$pattern" "$GATE_LOG_DIR/$name.log"; then
    printf 'FAIL %s: missing nonvacuous completion marker\n' "$name" >&2
    return 1
  fi
}
