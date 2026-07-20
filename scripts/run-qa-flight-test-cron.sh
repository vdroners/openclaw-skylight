#!/usr/bin/env bash
# NC-GCS flight-test cron wrapper — smoke + flight-cycle + rally/geofence + Talk summary.
# Prefers versioned nc-gcs scripts/qa; falls back to OpenClaw skill dir.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QA_DIR="${QA_DIR:-/media/4TB/nc-gcs/scripts/qa}"
[[ -x "${QA_DIR}/run-qa-flight-cycle.sh" ]] || QA_DIR="${HOME}/.openclaw/workspace/skills/nc-gcs-qa"
ROOM="${QA_TALK_ROOM:-jf7zijqp}"

summaries=()
fail=0

run_step() {
  local name="$1" script="$2"
  echo "=== $name ==="
  local out rc=0
  set +e
  out="$(bash "$script" 2>&1)"
  rc=$?
  set -e
  if [[ $rc -ne 0 ]]; then
    fail=1
  fi
  summary="$(printf '%s\n' "$out" | grep '^QA_SUMMARY ' | tail -1 || true)"
  if [[ -n "$summary" ]]; then
    summaries+=("$name: ${summary#QA_SUMMARY }")
    if echo "$summary" | grep -q 'gate=FAIL'; then
      fail=1
    fi
  else
    summaries+=("$name: no QA_SUMMARY (exit=$rc)")
    [[ $rc -ne 0 ]] && fail=1
  fi
  printf '%s\n' "$out" | tail -3
}

run_step "smoke" "${QA_DIR}/run-qa-smoke.sh"
if [[ $fail -eq 1 ]]; then
  BODY="NC-GCS flight-test ABORT: smoke gate FAIL. ${summaries[*]}"
  bash "${SCRIPT_DIR}/talk-post.sh" "$BODY" "$ROOM" || true
  echo "QA_FLIGHT_TEST_ABORT smoke_fail"
  exit 1
fi

run_step "flight-cycle" "${QA_DIR}/run-qa-flight-cycle.sh"
if [[ -x "${HOME}/.openclaw/workspace/skills/nc-gcs-qa/run-qa-rally-geofence.sh" ]]; then
  run_step "rally-geofence" "${HOME}/.openclaw/workspace/skills/nc-gcs-qa/run-qa-rally-geofence.sh"
fi

BODY="NC-GCS flight-test done fail=${fail}. ${summaries[*]}"
if [[ ${#BODY} -gt 780 ]]; then
  BODY="${BODY:0:770}…"
fi
bash "${SCRIPT_DIR}/talk-post.sh" "$BODY" "$ROOM" || true
echo "QA_FLIGHT_TEST_DONE fail=${fail}"
# G-QA-CRON-EXIT: non-zero when any child gate=FAIL
exit "$fail"
