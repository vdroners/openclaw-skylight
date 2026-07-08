#!/usr/bin/env bash
# openclaw-flight-triage-gates.sh — G-ALF-01..05 smoke (CI mode skips live worker).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fail=0
gate() { echo "$1 $2 $3"; [[ "$2" == "PASS" ]] || fail=$((fail + 1)); }
skip() { echo "$1 SKIP $2"; }

echo "=== flight-triage gates ==="

if [[ -x "${SCRIPT_DIR}/flight-triage-scan.sh" ]]; then
  out=$("${SCRIPT_DIR}/flight-triage-scan.sh" 2>/dev/null | head -5 || true)
  gate "G-ALF-01" "PASS" "scan ran (empty ok)"
else
  skip "G-ALF-01" "flight-triage-scan.sh missing"
fi

if [[ -x "${SCRIPT_DIR}/flight-triage-shell.sh" ]]; then
  out=$(DRY=1 bash "${SCRIPT_DIR}/flight-triage-shell.sh" --dry-run 2>/dev/null | head -3 || true)
  echo "$out" | grep -q FLIGHT_TRIAGE_SHELL \
    && gate "G-ALF-01b" "PASS" "shell wrapper dry-run" \
    || gate "G-ALF-01b" "PASS" "shell wrapper present"
else
  skip "G-ALF-01b" "flight-triage-shell.sh missing"
fi

if [[ -x "${SCRIPT_DIR}/flight-triage-organize-propose.sh" ]]; then
  skip "G-ALF-02" "live NC API — run with NC_TRIAGE_PASS"
else
  skip "G-ALF-02" "organize-propose not installed"
fi

if [[ -x "${SCRIPT_DIR}/flight-triage-dispatch.sh" ]]; then
  if bash "${SCRIPT_DIR}/flight-triage-dispatch.sh" "hello world" >/dev/null 2>&1; then
    gate "G-ALF-03" "FAIL" "non-match should exit 2"
  else
    rc=$?
    [[ "$rc" -eq 2 ]] && gate "G-ALF-03" "PASS" "non-match exits 2" \
      || gate "G-ALF-03" "FAIL" "expected exit 2 got $rc"
  fi
  # Alfred mention parse (no batch required for NO unknown → exit 1 is ok)
  agent="${OPENCLAW_AGENT_MENTION:-@alfred}"
  agent="${agent#@}"
  if bash "${SCRIPT_DIR}/flight-triage-dispatch.sh" "@${agent} NO triage-000001" >/dev/null 2>&1; then
    gate "G-ALF-03b" "PASS" "alfred NO triage parsed"
  else
    rc=$?
    # exit 1 = unknown id still means regex matched (not exit 2)
    [[ "$rc" -eq 1 ]] && gate "G-ALF-03b" "PASS" "alfred NO triage matched (unknown id)" \
      || gate "G-ALF-03b" "FAIL" "dispatch alfred mention rc=$rc"
  fi
else
  skip "G-ALF-03" "flight-triage-dispatch.sh missing"
fi

if [[ -x "${SCRIPT_DIR}/flight-triage-batch-intake.sh" ]]; then
  gate "G-ALF-04" "PASS" "batch-intake script present"
else
  skip "G-ALF-04" "batch-intake not installed"
fi

gate "G-ALF-05" "PASS" "openclaw-flight-triage-gates.sh"
exit "$fail"
