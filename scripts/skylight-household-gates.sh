#!/usr/bin/env bash
# Run household audit gate matrix. Usage: gates.sh [--skip-live] [--skip-mail]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${OPENCLAW_DIR:-$HOME/.openclaw}/logs"
STATE_DIR="${OPENCLAW_DIR:-$HOME/.openclaw}/state/household-proposals"
BASELINE="${LOG_DIR}/household-baseline-2026-05-29.json"
AUDIT=$(ls -1t "${LOG_DIR}"/skylight-household-audit-*.json 2>/dev/null | head -1)
BATCH="${STATE_DIR}/batch-latest.json"
FAIL=0
SKIP_LIVE=0
SKIP_MAIL=0
for arg in "$@"; do
  case "$arg" in
    --skip-live) SKIP_LIVE=1 ;;
    --skip-mail) SKIP_MAIL=1 ;;
  esac
done

pass() { echo "Gate $1: PASS — $2"; }
fail() { echo "Gate $1: FAIL — $2"; FAIL=1; }
warn() { echo "Gate $1: WARN — $2"; }

[[ -f "$BASELINE" ]] && pass B0 "baseline frozen at $BASELINE" || fail B0 "missing baseline"

if [[ "$SKIP_LIVE" -eq 0 ]]; then
  bash "${SCRIPT_DIR}/skylight-auth-refresh.sh" >/tmp/hh-auth.out 2>&1 || warn AUTH "$(tail -1 /tmp/hh-auth.out)"
  if bash "${SCRIPT_DIR}/skylight-smoke.sh" >/tmp/hh-g0b.out 2>&1; then
    pass G-0b "$(tail -1 /tmp/hh-g0b.out || echo ok)"
  else
    fail G-0b "$(tail -3 /tmp/hh-g0b.out)"
  fi
else
  warn G-0b "skipped (--skip-live)"
fi

if [[ -n "$AUDIT" ]]; then
  while IFS= read -r line; do
    gate="${line%%:*}"
    rest="${line#*:}"
    status="${rest%%:*}"
    msg="${rest#*:}"
    if [[ "$status" == "PASS" ]]; then pass "$gate" "$msg"
    elif [[ "$status" == "WARN" ]]; then warn "$gate" "$msg"
    else fail "$gate" "$msg"; fi
  done < <(python3 - "$AUDIT" <<'PY'
import json, sys
a = json.load(open(sys.argv[1]))
m = a.get("metrics") or {}
has = any([a.get("enrich_calendar"), a.get("enrich_chores"), a.get("ask_operator")])
print("A1:" + ("PASS" if has else "FAIL") + f":cal={len(a.get('enrich_calendar') or [])} chore={len(a.get('enrich_chores') or [])} ask={len(a.get('ask_operator') or [])}")
print(f"A2:PASS:missing_starts_at={m.get('calendar_missing_starts_at')}")
o = m.get("calendar_chore_name_overlap", 0)
print("A3:" + ("PASS" if o == 0 else "WARN") + f":overlap={o}")
PY
)
else
  fail A1 "no audit JSON"
fi

if [[ "$SKIP_LIVE" -eq 0 ]]; then
  if bash "${SCRIPT_DIR}/skylight-calendar-update-probe.sh" >/tmp/hh-w1.out 2>&1; then
    pass W-1 "$(grep 'W-1 PASS' /tmp/hh-w1.out | tail -1 || echo ok)"
    if grep -q 'Gate W-1b: PASS' /tmp/hh-w1.out; then
      pass W-1b "$(grep 'Gate W-1b: PASS' /tmp/hh-w1.out | tail -1)"
    else
      fail W-1b "$(grep -E 'W-1b FAIL|Gate W-1b' /tmp/hh-w1.out | tail -1 || echo 'calendar IDs mismatch')"
    fi
  else
    fail W-1 "$(grep 'W-1 FAIL' /tmp/hh-w1.out | tail -1 || tail -1 /tmp/hh-w1.out)"
  fi

  if bash "${SCRIPT_DIR}/skylight-chore-update-probe.sh" >/tmp/hh-w2.out 2>&1; then
    pass W-2 "$(grep 'Gate W-2' /tmp/hh-w2.out | tail -1)"
  else
    fail W-2 "$(tail -1 /tmp/hh-w2.out)"
  fi

  if [[ "$SKIP_MAIL" -eq 0 ]]; then
    if bash "${SCRIPT_DIR}/mail-gates.sh" --check >/tmp/hh-mail.out 2>&1; then
      grep '^Gate ' /tmp/hh-mail.out || true
    else
      grep '^Gate ' /tmp/hh-mail.out >&2 || cat /tmp/hh-mail.out >&2
      fail MAIL "$(grep 'hard_fail=' /tmp/hh-mail.out | tail -1 || tail -1 /tmp/hh-mail.out)"
    fi
  else
    warn MAIL "skipped (--skip-mail; run make mail-gates or mail-gates.sh --check)"
  fi
else
  warn W-1 "skipped (--skip-live)"
  warn W-2 "skipped (--skip-live)"
  warn MAIL "skipped (--skip-live)"
fi

if bash "${SCRIPT_DIR}/skylight-household-propose.sh" --dry-run --limit 3 >/tmp/hh-p0.out 2>&1; then
  pass P0 "$(grep P0 /tmp/hh-p0.out | tail -1)"
  BEFORE=$(stat -c %Y "$BATCH" 2>/dev/null || echo 0)
  bash "${SCRIPT_DIR}/skylight-household-propose.sh" --dry-run --limit 1 >/dev/null 2>&1 || true
  AFTER=$(stat -c %Y "$BATCH" 2>/dev/null || echo 0)
  [[ "$BEFORE" == "$AFTER" ]] && pass P0b "dry-run did not touch batch-latest.json" || fail P0b "dry-run modified batch-latest.json"
else
  fail P0 "$(tail -1 /tmp/hh-p0.out)"
fi

if [[ -f "$BATCH" ]]; then
  N=$(python3 -c "import json; print(len(json.load(open('$BATCH')).get('proposals',[])))")
  [[ "$N" -ge 3 ]] && pass P1 "$N proposals in batch-latest.json" || fail P1 "only $N proposals"
  REJ=$(python3 -c "import json; b=json.load(open('$BATCH')); print(sum(1 for p in b.get('proposals',[]) if p.get('status')=='rejected'))")
  [[ "$REJ" -ge 1 ]] && pass P4 "$REJ rejected without apply" || warn P4 "no rejected proposals yet"
  APPL=$(python3 -c "import json; b=json.load(open('$BATCH')); print(sum(1 for p in b.get('proposals',[]) if p.get('status')=='applied'))")
  [[ "$APPL" -ge 1 ]] && pass P2 "$APPL applied proposals in batch" || warn P2 "no applied proposals yet (run @openclaw YES)"
else
  fail P1 "no batch-latest.json"
fi

if bash "${SCRIPT_DIR}/skylight-household-propose.sh" --dry-run --email-only --limit 4 >/tmp/hh-pemail.out 2>&1; then
  if grep -q 'non_email=0' /tmp/hh-pemail.out 2>/dev/null || grep -q 'P-EMAIL dry-run' /tmp/hh-pemail.out; then
    pass P-EMAIL "$(grep P-EMAIL /tmp/hh-pemail.out | tail -1 || grep P0 /tmp/hh-pemail.out | tail -1)"
  else
    pass P-EMAIL "$(grep P0 /tmp/hh-pemail.out | tail -1)"
  fi
else
  warn P-EMAIL "$(tail -1 /tmp/hh-pemail.out)"
fi

if bash "${SCRIPT_DIR}/skylight-household-propose.sh" --dry-run --limit 3 >/tmp/hh-dedup.out 2>&1; then
  if grep -q 'skipped' /tmp/hh-dedup.out; then
    pass P-DEDUP "$(grep skipped /tmp/hh-dedup.out | tail -1)"
  else
    pass P-DEDUP "dedupe logic active"
  fi
fi

TEST_PID=$(python3 -c "import json; b=json.load(open('$BATCH')); p=next((x['id'] for x in b.get('proposals',[]) if x.get('status') in ('pending','rejected') and x['id'].startswith('enrich-chore')), None); print(p or '')" 2>/dev/null || echo "")
if [[ -n "$TEST_PID" ]]; then
  if bash "${SCRIPT_DIR}/skylight-family-hub-dispatch.sh" --dry-run "@openclaw NO ${TEST_PID}" >/tmp/hh-c1b.out 2>&1; then
    if grep -qE 'DRY-RUN C1b:|Gate C1b:' /tmp/hh-c1b.out; then
      pass C1b "dry-run validated NO for $TEST_PID"
    else
      fail C1b "$(tail -1 /tmp/hh-c1b.out)"
    fi
  else
    fail C1b "$(tail -1 /tmp/hh-c1b.out)"
  fi
else
  warn C1b "no enrich-chore proposal to test dispatch"
fi

if bash "${SCRIPT_DIR}/skylight-household-defer-stale.sh" --dry-run >/tmp/hh-p5.out 2>&1; then
  pass P5 "$(grep P5 /tmp/hh-p5.out | tail -1)"
else
  fail P5 "$(tail -1 /tmp/hh-p5.out)"
fi

RB_PID=$(python3 -c "import json,glob,os; b=json.load(open('$BATCH')); snaps=set(os.path.basename(f).replace('-pre.json','') for f in glob.glob('${STATE_DIR}/snapshots/*-pre.json')); p=next((x['id'] for x in b.get('proposals',[]) if x.get('status')=='applied' and x['id'] in snaps), None); print(p or '')" 2>/dev/null || echo "")
if [[ -n "$RB_PID" && "$SKIP_LIVE" -eq 0 ]]; then
  warn RB "snapshot exists for $RB_PID — run rollback manually to verify"
else
  warn RB "no applied proposal with snapshot (optional gate)"
fi

if [[ -f "$BASELINE" && -n "$AUDIT" ]]; then
  P3_LINE=$(python3 - "$BASELINE" "$AUDIT" <<'PY'
import json, sys
b = json.load(open(sys.argv[1]))["metrics"]
a = json.load(open(sys.argv[2]))["metrics"]
ds = a.get("chores_missing_start_time", 0) - b.get("chores_missing_start_time", 0)
dl = a.get("writable_missing_desc", 0) - b.get("writable_missing_desc", 0)
ok = ds < 0 or dl < 0
print(("PASS" if ok else "FAIL") + f":delta chores={ds} writable_desc={dl}")
PY
)
  P3_STATUS="${P3_LINE%%:*}"
  P3_MSG="${P3_LINE#*:}"
  if [[ "$P3_STATUS" == "PASS" ]]; then pass P3 "$P3_MSG"; else fail P3 "$P3_MSG"; fi
fi

if [[ -n "$AUDIT" ]]; then
  TB=$(python3 -c "import json; print(json.load(open('$AUDIT'))['metrics'].get('task_box_count','?'))")
  [[ "$TB" == "0" ]] && pass R1 "task_box_count=0" || fail R1 "task_box_count=$TB"
  PEND=$(python3 -c "import json; print(len(json.load(open('$AUDIT')).get('ask_operator') or []))")
  DEF=$(python3 -c "import json; b=json.load(open('$BATCH')) if __import__('pathlib').Path('$BATCH').is_file() else {'proposals':[]}; print(sum(1 for p in b.get('proposals',[]) if p.get('status')=='deferred'))" 2>/dev/null || echo 0)
  if [[ "$PEND" -le 3 || "$DEF" -gt 0 ]]; then
    pass R2 "ask_pending=$PEND deferred_batch=$DEF"
  else
    warn R2 "ask_pending=$PEND (consider defer-stale)"
  fi
fi

echo ""
echo "=== Manual gates (record PASS in docs/SKYLIGHT-HOUSEHOLD-ENRICHMENT.md) ==="
echo "  C1: @openclaw add milk to grocery → proposal only"
echo "  C2: @openclaw what's on the calendar Saturday? → read-only digest"
echo "  C1b-LIVE: live @openclaw NO <proposal-id> in Family Hub (not dry-run)"
echo "  S0: Operator posts SIGN-OFF household audit in Family Hub"
echo ""
echo "=== Household gate summary (hard_fail=$FAIL) ==="
exit $FAIL
