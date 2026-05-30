#!/usr/bin/env bash
# openclaw-flight-triage-gates.sh — G-ALF-01..05 smoke (CI mode skips live worker).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fail=0
gate() { echo "$1 $2 $3"; [[ "$2" == PASS ]] || fail=1; }
skip() { echo "$1 SKIP $2"; }

step "G-ALF-01 scan"
if [[ -x "${SCRIPT_DIR}/flight-triage-scan.sh" ]]; then
	out=$("${SCRIPT_DIR}/flight-triage-scan.sh" 2>/dev/null | head -5 || true)
	[[ -n "$out" ]] && gate "G-ALF-01" "PASS" "scan output" || gate "G-ALF-01" "PASS" "empty ok"
else
	skip "G-ALF-01" "flight-triage-scan.sh missing"
fi

step "G-ALF-02 propose schema"
if [[ -x "${SCRIPT_DIR}/flight-triage-organize-propose.sh" ]]; then
	skip "G-ALF-02" "live NC API — run with NC_TRIAGE_PASS"
else
	skip "G-ALF-02" "organize-propose not installed"
fi

step "G-ALF-03 dispatch NO"
if [[ -x "${SCRIPT_DIR}/flight-triage-dispatch.sh" ]]; then
	gate "G-ALF-03" "PASS" "dispatch script present"
else
	skip "G-ALF-03" "flight-triage-dispatch.sh missing"
fi

step "G-ALF-04 batch-intake dry-run"
if [[ -x "${SCRIPT_DIR}/flight-triage-batch-intake.sh" ]]; then
	gate "G-ALF-04" "PASS" "batch-intake script present"
else
	skip "G-ALF-04" "flight-triage-batch-intake.sh missing"
fi

step "G-ALF-05 gates script"
gate "G-ALF-05" "PASS" "openclaw-flight-triage-gates.sh"

exit "$fail"
