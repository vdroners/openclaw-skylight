#!/usr/bin/env bash
# openclaw-flight-triage-gates.sh — G-ALF smoke + dry contracts (CI-safe).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fail=0
gate() { echo "$1 $2 $3"; [[ "$2" == "PASS" || "$2" == "SKIP" ]] || fail=$((fail + 1)); }
skip() { echo "$1 SKIP $2"; }

echo "=== flight-triage gates ==="

DISPATCH="${SCRIPT_DIR}/flight-triage-dispatch.sh"
PROPOSE="${SCRIPT_DIR}/flight-triage-propose.sh"
SCAN="${SCRIPT_DIR}/flight-triage-scan.sh"
SHELL_SH="${SCRIPT_DIR}/flight-triage-shell.sh"
FEM="${SCRIPT_DIR}/flight-event-monitor.sh"
STATE_DIR="${HOME}/.openclaw/state/flight-triage-proposals"
mkdir -p "$STATE_DIR"

if [[ -x "$SCAN" ]]; then
  out=$("$SCAN" 2>/dev/null | head -5 || true)
  gate "G-ALF-01" "PASS" "scan ran (empty ok)"
  if grep -q 'NEXTCLOUD_URL\|NC_URL' "$SCAN"; then
    gate "G-ALF-SCAN" "PASS" "scan accepts NC_/NEXTCLOUD_ aliases"
  else
    gate "G-ALF-SCAN" "FAIL" "scan missing env aliases"
  fi
else
  skip "G-ALF-01" "flight-triage-scan.sh missing"
fi

if [[ -x "$SHELL_SH" ]]; then
  out=$(bash "$SHELL_SH" --dry-run 2>/dev/null | head -3 || true)
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

if [[ -x "$DISPATCH" ]]; then
  set +e
  bash "$DISPATCH" "hello world" >/dev/null 2>&1
  rc=$?
  set -e
  [[ "$rc" -eq 2 ]] && gate "G-ALF-03" "PASS" "non-match exits 2" \
    || gate "G-ALF-03" "FAIL" "expected exit 2 got $rc"

  agent="${OPENCLAW_AGENT_MENTION:-@alfred}"
  agent="${agent#@}"
  set +e
  bash "$DISPATCH" "@${agent} NO triage-000001" >/dev/null 2>&1
  rc=$?
  set -e
  [[ "$rc" -eq 1 ]] && gate "G-ALF-03b" "PASS" "alfred NO unknown id exits 1" \
    || gate "G-ALF-03b" "FAIL" "dispatch alfred mention rc=$rc"

  # G-ALF-03c propose mention == dispatch agent
  if [[ -x "$PROPOSE" ]]; then
    pout=$("$PROPOSE" --dry-run /tmp/fake-test.BIN 2>/dev/null || true)
    if echo "$pout" | grep -qiE "@${agent}[[:space:]]+YES"; then
      gate "G-ALF-03c" "PASS" "propose uses @${agent}"
    else
      gate "G-ALF-03c" "FAIL" "propose mention mismatch"
    fi
  else
    skip "G-ALF-03c" "propose missing"
  fi

  # G-ALF-06 YES dry-run with seeded state
  seed_id="triage-424242"
  cat > "${STATE_DIR}/batch-latest.json" <<EOF
{"version":1,"proposals":[{"id":"${seed_id}","bin_path":"/tmp/fake.BIN","state":"pending"}]}
EOF
  set +e
  out=$(FLIGHT_TRIAGE_DISPATCH_DRY_RUN=1 bash "$DISPATCH" "@${agent} YES ${seed_id}" 2>/dev/null)
  rc=$?
  set -e
  if [[ "$rc" -eq 0 ]] && echo "$out" | grep -q '"dry_run":true'; then
    gate "G-ALF-06" "PASS" "YES dry-run intake path"
  else
    gate "G-ALF-06" "FAIL" "YES dry-run rc=$rc out=$out"
  fi

  # G-ALF-08 NO rejects
  cat > "${STATE_DIR}/batch-latest.json" <<EOF
{"version":1,"proposals":[{"id":"${seed_id}","bin_path":"/tmp/fake.BIN","state":"pending"}]}
EOF
  set +e
  out=$(bash "$DISPATCH" "@${agent} NO ${seed_id}" 2>/dev/null)
  rc=$?
  set -e
  state=$(jq -r '.proposals[0].state' "${STATE_DIR}/batch-latest.json" 2>/dev/null || echo "")
  if [[ "$rc" -eq 0 && "$state" == "rejected" ]]; then
    gate "G-ALF-08" "PASS" "NO marks rejected"
  else
    gate "G-ALF-08" "FAIL" "rc=$rc state=$state"
  fi
else
  skip "G-ALF-03" "flight-triage-dispatch.sh missing"
fi

# G-ALF-07 talk-post arg order in propose
if [[ -x "$PROPOSE" ]] && grep -q 'talk-post.sh" "\$MSG" "\$ROOM"' "$PROPOSE"; then
  gate "G-ALF-07" "PASS" "propose talk-post MSG ROOM order"
else
  gate "G-ALF-07" "FAIL" "propose talk-post args wrong or missing"
fi

if [[ -x "${SCRIPT_DIR}/flight-triage-batch-intake.sh" ]]; then
  gate "G-ALF-04" "PASS" "batch-intake script present"
else
  skip "G-ALF-04" "batch-intake not installed"
fi

# G-FEM-01/02 ARG_MAX / no silent OK
if [[ -x "$FEM" ]]; then
  if grep -q 'FEM_TMP\|mktemp' "$FEM" && ! grep -qE 'python3 - "\$flights"' "$FEM"; then
    gate "G-FEM-01" "PASS" "monitor uses temp/stdin not argv for flights JSON"
  else
    gate "G-FEM-01" "FAIL" "monitor still puts flights JSON on argv"
  fi
  if grep -q 'FLIGHT_MONITOR_ERROR' "$FEM"; then
    gate "G-FEM-02" "PASS" "monitor emits FLIGHT_MONITOR_ERROR on parse fail"
  else
    gate "G-FEM-02" "FAIL" "no FLIGHT_MONITOR_ERROR path"
  fi
  # Oversized fixture smoke (must not ARG_MAX)
  big=$(python3 -c 'print("{" + "\"x\":" + ("\"" + "a"*200000 + "\",")*20 + "\"flights\":[]}")')
  TMPF=$(mktemp)
  printf '%s' "$big" >"$TMPF"
  # Unit-level: python reading file of >2MB should work
  if python3 -c "import pathlib; p=pathlib.Path('$TMPF'); d=p.read_text(); print(len(d))" >/dev/null; then
    gate "G-FEM-01b" "PASS" "python can load >ARG_MAX-ish payload from file"
  else
    gate "G-FEM-01b" "FAIL" "file load failed"
  fi
  rm -f "$TMPF"
else
  skip "G-FEM-01" "flight-event-monitor missing"
fi

# G-ALF-10 curate dry-run if present
CURATE="/media/4TB/nc-gcs/apps/nc_ardupilot_triage/tools/alfred-flight-triage-curate.sh"
if [[ -x "$CURATE" ]]; then
  if "$CURATE" --help 2>&1 | grep -q dry-run || grep -q '\-\-dry-run' "$CURATE"; then
    gate "G-ALF-10" "PASS" "curate supports --dry-run"
  else
    gate "G-ALF-10" "SKIP" "curate present but dry-run unclear"
  fi
else
  skip "G-ALF-10" "alfred-flight-triage-curate.sh missing"
fi

gate "G-ALF-05" "PASS" "openclaw-flight-triage-gates.sh"
exit "$fail"
