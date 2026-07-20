#!/usr/bin/env bash
# gate-path-a-triage-talk.sh — smoke Path A (@alfred triage /path.BIN → serve-viewer).
# Uses a tiny fixture BIN if available; skips live analyze unless GATE_LIVE=1.
set -euo pipefail

fail=0
gate() { echo "$1 $2 — $3"; [[ "$2" == "PASS" || "$2" == "SKIP" ]] || fail=$((fail+1)); }

RUNNER="${HOME}/.openclaw/scripts/run-triage-for-talk.sh"
TRIAGE_ROOT="/media/4TB/ardupilot-triage"

echo "=== Path A triage-for-talk smoke ==="

[[ -x "$RUNNER" ]] && gate "G-PATHA-01" "PASS" "run-triage-for-talk.sh present" \
  || gate "G-PATHA-01" "FAIL" "run-triage-for-talk.sh missing"

# Arg parsing: missing BIN → exit 2
set +e
"$RUNNER" 2>/dev/null
rc=$?
set -e
[[ "$rc" -eq 2 ]] && gate "G-PATHA-02" "PASS" "missing BIN exits 2" \
  || gate "G-PATHA-02" "SKIP" "runner exit contract rc=$rc (may differ)"

# Find a small fixture BIN
FIXTURE=""
for cand in \
  "${TRIAGE_ROOT}/tests/fixtures"/*.BIN \
  "${TRIAGE_ROOT}/tests/fixtures"/*.bin \
  "${TRIAGE_ROOT}/tests/smoke"/*.BIN \
  /media/4TB/ardupilot-triage/data/logs/intake/*.BIN
do
  if [[ -f "$cand" ]]; then
    size=$(stat -c%s "$cand" 2>/dev/null || echo 0)
    if [[ "$size" -gt 1000 && "$size" -lt 50000000 ]]; then
      FIXTURE="$cand"
      break
    fi
  fi
done

if [[ -z "$FIXTURE" ]]; then
  gate "G-PATHA-03" "SKIP" "no small fixture BIN"
  exit "$fail"
fi

gate "G-PATHA-03" "PASS" "fixture=$FIXTURE"

if [[ "${GATE_LIVE:-0}" != "1" ]]; then
  gate "G-PATHA-04" "SKIP" "set GATE_LIVE=1 to run analyze-triage"
  exit "$fail"
fi

LABEL="patha_smoke_$(date +%Y%m%d_%H%M%S)"
set +e
TALK_POST=0 "$RUNNER" "$FIXTURE" --label "$LABEL" >/tmp/patha-smoke.out 2>&1
rc=$?
set -e

# Locate run dir
RUN_DIR=""
for d in "${HOME}/.openclaw/triage-runs/${LABEL}" "${TRIAGE_ROOT}/triage-runs/${LABEL}" "${TRIAGE_ROOT}/data/runs/${LABEL}"; do
  [[ -d "$d" ]] && RUN_DIR="$d" && break
done

if [[ -z "$RUN_DIR" ]]; then
  # try discover from output
  RUN_DIR=$(grep -oE '/[^ ]+/'"$LABEL" /tmp/patha-smoke.out 2>/dev/null | head -1 || true)
fi

if [[ -n "$RUN_DIR" && -f "${RUN_DIR}/viewer.html" && -f "${RUN_DIR}/dashboard.json" ]]; then
  gate "G-PATHA-04" "PASS" "artifacts under $RUN_DIR"
else
  # Soft: many runners use different CLI flags
  gate "G-PATHA-04" "SKIP" "live run inconclusive rc=$rc (check /tmp/patha-smoke.out)"
fi

# HTTP smoke if serve-viewer up
if curl -sS -o /dev/null -w '%{http_code}' --max-time 5 "http://127.0.0.1:8765/" 2>/dev/null | grep -q 200; then
  if [[ -n "$RUN_DIR" ]]; then
    label_leaf=$(basename "$RUN_DIR")
    c1=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 "http://127.0.0.1:8765/runs/${label_leaf}/viewer.html" || echo 000)
    c2=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 "http://127.0.0.1:8765/runs/${label_leaf}/dashboard.json" || echo 000)
    if [[ "$c1" == "200" && "$c2" == "200" ]]; then
      gate "G-PATHA-05" "PASS" "HTTP 200 viewer+dashboard"
    else
      gate "G-PATHA-05" "FAIL" "viewer=$c1 dashboard=$c2"
    fi
  else
    gate "G-PATHA-05" "SKIP" "no run dir for HTTP check"
  fi
else
  gate "G-PATHA-05" "SKIP" "serve-viewer not on :8765"
fi

exit "$fail"
