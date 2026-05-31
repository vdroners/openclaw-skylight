#!/usr/bin/env bash
# Daily OpenClaw health review + week-2 PERF/NC/SESS/CAP gates.
# Usage: openclaw-day-review.sh [--check] [--write]
set -euo pipefail

OPENCLAW="${OPENCLAW_DIR:-$HOME/.openclaw}"
LOG_DIR="${OPENCLAW}/logs"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/load-nextcloud-env.sh"
[[ -f "${OPENCLAW}/.env" ]] && set -a && source "${OPENCLAW}/.env" && set +a
CRON_PREFIX="${OPENCLAW_CRON_UNIT_PREFIX:-openclaw-cron}"
JOBS="${OPENCLAW}/cron/jobs.json"
MANIFEST="${OPENCLAW}/workspace/references/cron-shell-direct.yaml"
HARD_FAIL=0
SOFT_FAIL=0
MODE="${1:---check}"

ok() { echo "PASS $*"; }
bad() { echo "FAIL $*" >&2; HARD_FAIL=$((HARD_FAIL + 1)); }
warn() { echo "WARN $*" >&2; SOFT_FAIL=$((SOFT_FAIL + 1)); }

journal_count() {
  local pattern="$1"
  local unit="${2:-openclaw-gateway}"
  local since="${3:-24 hours ago}"
  journalctl --user -u "$unit" --since "$since" --no-pager 2>/dev/null \
    | grep -cE "$pattern" || true
}

BASELINE_FILE="${OPENCLAW}/state/test-week-profile-applied.txt"
JOURNAL_SINCE="24 hours ago"
if [[ -f "$BASELINE_FILE" ]]; then
  JOURNAL_SINCE="$(cat "$BASELINE_FILE")"
fi

shell_timer_ok_today() {
  local unit="$1"
  local grep_token="$2"
  journalctl --user -u "$unit" --since today --no-pager 2>/dev/null \
    | grep -q "$grep_token"
}

[[ "$MODE" == "--check" || "$MODE" == "--write" ]] || {
  echo "usage: $0 [--check|--write]" >&2
  exit 2
}

# PERF-1..4
OPS_ROOM="${SKYLIGHT_OPS_TALK_ROOM:?set SKYLIGHT_OPS_TALK_ROOM}"
OPS_WAITS=$(journal_count "lane wait exceeded.*${OPS_ROOM}" openclaw-gateway "$JOURNAL_SINCE")
TIMEOUTS=$(journal_count 'surface_error reason=timeout' openclaw-gateway "$JOURNAL_SINCE")
INCOMPLETE=$(journal_count 'incomplete turn detected' openclaw-gateway "$JOURNAL_SINCE")
WORST_MS=$(journalctl --user -u openclaw-gateway --since "$JOURNAL_SINCE" --no-pager 2>/dev/null \
  | grep 'lane wait exceeded' | grep "$OPS_ROOM" \
  | sed -n 's/.*waitedMs=\([0-9]*\).*/\1/p' \
  | sort -n | tail -1 || true)
WORST_S=$(( (${WORST_MS:-0} + 999) / 1000 ))
PERF4_MAX="${PERF4_MAX_WAIT_S:-120}"

if [[ "$OPS_WAITS" -le 5 ]]; then ok "PERF-1 ops lane waits=${OPS_WAITS}/24h (max 5)"
else bad "PERF-1 ops lane waits=${OPS_WAITS}/24h (max 5)"; fi

if [[ "$TIMEOUTS" -le 3 ]]; then ok "PERF-2 llm timeouts=${TIMEOUTS}/24h (max 3)"
else bad "PERF-2 llm timeouts=${TIMEOUTS}/24h (max 3)"; fi

if [[ "$INCOMPLETE" -eq 0 ]]; then ok "PERF-3 incomplete turns=${INCOMPLETE}/24h"
else bad "PERF-3 incomplete turns=${INCOMPLETE}/24h"; fi

if [[ "$WORST_S" -le "$PERF4_MAX" ]]; then ok "PERF-4 worst ops lane wait=${WORST_S}s (max ${PERF4_MAX}s)"
else bad "PERF-4 worst ops lane wait=${WORST_S}s (max ${PERF4_MAX}s)"; fi

CRON_PREFIX="${OPENCLAW_CRON_UNIT_PREFIX:-openclaw-cron}"

morning_timer_ok() {
  local token="$1"
  shell_timer_ok_today "${CRON_PREFIX}-email-daily-digest.service" "$token"
}

# PERF-5 morning posts
if morning_timer_ok DIGEST_POSTED \
   && shell_timer_ok_today "${CRON_PREFIX}-skylight-family-morning.service" SKYLIGHT_FAMILY_BRIEF_POSTED; then
  ok "PERF-5 morning digest + family brief posted today"
else
  bad "PERF-5 morning posts missing today (digest or family brief)"
fi

# CAP-F1 / CAP-F2
if [[ -f "$JOBS" ]]; then
  python3 - "$JOBS" <<'PY' | while read -r line; do
import json, sys
jobs = {j["name"]: j for j in json.loads(open(sys.argv[1]).read()).get("jobs", [])}
for name, expect_disabled in (("flight-event-monitor", True), ("email-to-event", True)):
    j = jobs.get(name) or {}
    en = j.get("enabled", True)
    if expect_disabled and en:
        print(f"FAIL CAP shell job {name} agentTurn still enabled")
    elif expect_disabled:
        print(f"PASS CAP agentTurn disabled for {name}")
    else:
        print(f"PASS CAP {name} ok")
PY
    case "$line" in
      PASS*) ok "${line#PASS }" ;;
      FAIL*) bad "${line#FAIL }" ;;
    esac
  done
fi

shell_timer_ran() {
  local grep_token="$1"
  shift
  local unit
  for unit in "$@"; do
    if journalctl --user -u "${unit}.service" --since "24 hours ago" --no-pager 2>/dev/null | grep -q "$grep_token"; then
      return 0
    fi
  done
  return 1
}

if shell_timer_ran FLIGHT_MONITOR_OK "${CRON_PREFIX}-flight-event-monitor" \
   || shell_timer_ran FLIGHT_ALERT_POSTED "${CRON_PREFIX}-flight-event-monitor"; then
  ok "CAP-F1 flight-event-monitor shell timer ran in 24h"
else
  warn "CAP-F1 flight-event-monitor shell timer not seen yet (install timers)"
fi

if shell_timer_ran 'email-to-event:' "${CRON_PREFIX}-email-to-event"; then
  ok "CAP-F2 email-to-event shell timer ran in 24h"
else
  warn "CAP-F2 email-to-event shell timer not seen yet"
fi

# CAP-P1 enabled agentTurn count
if [[ -f "$JOBS" ]]; then
  AGENT_N=$(python3 -c "import json; j=json.load(open('$JOBS')); print(sum(1 for x in j.get('jobs',[]) if x.get('enabled') and (x.get('payload') or {}).get('kind')=='agentTurn'))")
  if [[ "$AGENT_N" -le 25 ]]; then ok "CAP-P1 enabled agentTurn=${AGENT_N} (max 25)"
  else bad "CAP-P1 enabled agentTurn=${AGENT_N} (max 25)"; fi
fi

# CAP-P2 no */10 agentTurn
if [[ -f "$JOBS" ]]; then
  BAD=$(python3 -c "
import json
j=json.load(open('$JOBS'))
bad=[x['name'] for x in j.get('jobs',[]) if x.get('enabled') and (x.get('payload') or {}).get('kind')=='agentTurn' and '*/10' in ((x.get('schedule') or {}).get('expr') or '')]
print(len(bad))
")
  if [[ "$BAD" -eq 0 ]]; then ok "CAP-P2 no enabled */10 agentTurn jobs"
  else bad "CAP-P2 found ${BAD} enabled */10 agentTurn jobs"; fi
fi

# SESS-1
SESS_FILE="${OPENCLAW}/agents/main/sessions/sessions.json"
if [[ -f "$SESS_FILE" ]]; then
  FEM=$(python3 -c "import json; d=json.load(open('$SESS_FILE')); print(sum(1 for v in d.values() if isinstance(v,dict) and 'flight-event-monitor' in (v.get('label') or '')))")
  if [[ "$FEM" -le 5 ]]; then ok "SESS-1 flight-event-monitor sessions=${FEM} (max 5)"
  else bad "SESS-1 flight-event-monitor sessions=${FEM} (max 5)"; fi
fi

# SESS-2 prune timer
if systemctl --user is-active openclaw-session-prune.timer >/dev/null 2>&1 \
   || systemctl --user is-active prune-openclaw-sessions.timer >/dev/null 2>&1; then
  ok "SESS-2 session prune timer active"
else
  warn "SESS-2 session prune timer not found (openclaw-session-prune or prune-openclaw-sessions)"
fi

# NC-TALK
TALK502=$(journal_count 'Talk send failed \(502\)|Talk send failed \(503\)' openclaw-gateway "$JOURNAL_SINCE")
if bash "${SCRIPT_DIR}/talk-post.sh" --dry-run "openclaw day-review probe" "$OPS_ROOM" >/dev/null 2>&1; then
  ok "NC-TALK-1 talk-post dry-run ok"
else
  bad "NC-TALK-1 talk-post dry-run failed"
fi
if bash "${SCRIPT_DIR}/talk-post.sh" --test-retry >/dev/null 2>&1; then
  ok "NC-TALK-2 talk-post retry self-test ok"
else
  warn "NC-TALK-2 talk-post retry self-test skipped or failed"
fi
if [[ -x "${SCRIPT_DIR}/verify-hpb-edge.sh" ]]; then
  if bash "${SCRIPT_DIR}/verify-hpb-edge.sh" >/dev/null 2>&1; then ok "NC-HPB-1 hpb edge ok"
  else warn "NC-HPB-1 hpb edge check failed"; fi
else
  warn "NC-HPB-1 verify-hpb-edge.sh missing"
fi
if [[ "$TALK502" -le 2 ]]; then ok "NC-TALK-3 talk 502/503 failures=${TALK502}/24h (max 2)"
else bad "NC-TALK-3 talk 502/503 failures=${TALK502}/24h"; fi

# HOME-1 batch freshness
BATCH="${OPENCLAW}/state/household-proposals/batch-latest.json"
if [[ -f "$BATCH" ]]; then
  AGE_H=$(python3 -c "import os,time; print(int((time.time()-os.path.getmtime('$BATCH'))/3600))")
  if [[ "$AGE_H" -le 168 ]]; then ok "HOME-1 batch-latest age=${AGE_H}h (max 168h)"
  else bad "HOME-1 batch-latest stale age=${AGE_H}h"; fi
  python3 - "$BATCH" <<'PY' | while read -r line; do
import json, sys
from collections import Counter
b=json.loads(open(sys.argv[1]).read())
c=Counter(p.get("status") for p in b.get("proposals",[]))
pending=c.get("pending",0)
applied=c.get("applied",0)
print(f"INFO pending={pending} applied={applied}")
if pending>10 and applied==0:
    print("WARN HOME-ENGAGE >10 pending and 0 applied")
PY
    case "$line" in
      WARN*) warn "${line#WARN }" ;;
      INFO*) echo "$line" ;;
    esac
  done
fi

# E2E-AUTO
export EMAIL_TO_EVENT_AUTO="${EMAIL_TO_EVENT_AUTO:-0}"
if grep -q '^EMAIL_TO_EVENT_AUTO=0' "${OPENCLAW}/.env" 2>/dev/null \
   && grep -q 'EMAIL_TO_EVENT_AUTO' "${SCRIPT_DIR}/email-to-event-scan.sh"; then
  ok "E2E-AUTO EMAIL_TO_EVENT_AUTO=0 in .env + script guard"
else
  bad "E2E-AUTO EMAIL_TO_EVENT_AUTO not gated (expect 0 in .env until S0)"
fi

# CTX-1
AGENTS="${OPENCLAW}/workspace/AGENTS.md"
if [[ -f "$AGENTS" ]]; then
  CHARS=$(wc -c <"$AGENTS")
  if [[ "$CHARS" -le 8192 ]]; then ok "CTX-1 AGENTS.md chars=${CHARS} (max 8192)"
  else warn "CTX-1 AGENTS.md chars=${CHARS} (>8192)"; fi
fi

# DAY-1 write JSON
TODAY=$(date +%F)
OUT_JSON="${LOG_DIR}/day-review-${TODAY}.json"
if [[ "$MODE" == "--write" || "$MODE" == "--check" ]]; then
  mkdir -p "$LOG_DIR"
  python3 - "$OUT_JSON" "$OPS_WAITS" "$TIMEOUTS" "$INCOMPLETE" "$WORST_S" "$TALK502" "$HARD_FAIL" <<'PY'
import json, sys, time
path, ow, to, inc, worst, talk502, hf = sys.argv[1:8]
doc = {
    "date": time.strftime("%Y-%m-%d"),
    "generated_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
    "perf": {
        "ops_lane_waits_24h": int(ow),
        "llm_timeouts_24h": int(to),
        "incomplete_turns_24h": int(inc),
        "worst_ops_wait_s": int(worst),
        "talk_502_24h": int(talk502),
    },
    "hard_fail": int(hf),
}
open(path, "w").write(json.dumps(doc, indent=2) + "\n")
print(f"DAY-1 wrote {path}")
PY
  ok "DAY-1 day-review json"
fi

echo "hard_fail=${HARD_FAIL} soft_fail=${SOFT_FAIL}"
exit "$HARD_FAIL"
