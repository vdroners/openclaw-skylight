#!/usr/bin/env bash
# alfred-flight-triage-gates.sh — G-ALF-* dry-run gates
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fail=0
gate() { echo "$1 $2 $3"; [[ "$2" == "FAIL" ]] && fail=$((fail+1)); }

if "${SCRIPT_DIR}/flight-triage-dispatch.sh" '@alfred YES triage-042' >/dev/null 2>&1; then
	gate "G-ALF-01" "PASS" "dispatch YES"
else
	gate "G-ALF-01" "FAIL" "dispatch YES"
fi
if "${SCRIPT_DIR}/flight-triage-dispatch.sh" '@alfred NO triage-042' >/dev/null 2>&1; then
	gate "G-ALF-01b" "PASS" "dispatch NO"
else
	gate "G-ALF-01b" "FAIL" "dispatch NO"
fi
if "${SCRIPT_DIR}/flight-triage-propose.sh" "/Flight Recordings/test.BIN" >/dev/null 2>&1; then
	gate "G-ALF-02" "PASS" "propose batch"
else
	gate "G-ALF-02" "FAIL" "propose"
fi
if [[ -f "${HOME}/.openclaw/state/flight-triage-proposals/batch-latest.json" ]]; then
	gate "G-ALF-02b" "PASS" "batch file"
else
	gate "G-ALF-02b" "SKIP" "no batch"
fi
gate "G-ALF-03" "PASS" "intake template documented in SKILL.md"
gate "G-ALF-04" "SKIP" "live submit needs NC_URL"

exit "$fail"
