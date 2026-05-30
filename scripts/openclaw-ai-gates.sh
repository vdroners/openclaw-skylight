#!/usr/bin/env bash
# OpenClaw AI-layer gates — hard_fail on critical cron reliability (shell-direct + OpenClaw).
# Usage: openclaw-ai-gates.sh --check
set -euo pipefail

OPENCLAW="${OPENCLAW_DIR:-$HOME/.openclaw}"
RUNS="${OPENCLAW}/cron/runs"
MANIFEST="${OPENCLAW}/workspace/references/cron-shell-direct.yaml"
JOBS_JSON="${OPENCLAW}/cron/jobs.json"
HARD_FAIL=0
SOFT_FAIL=0

ok() { echo "PASS $*"; }
bad() { echo "FAIL $*" >&2; HARD_FAIL=$((HARD_FAIL + 1)); }
warn() { echo "WARN $*" >&2; SOFT_FAIL=$((SOFT_FAIL + 1)); }

last_run_status() {
  local job_id="$1"
  local log="${RUNS}/${job_id}.jsonl"
  [[ -f "$log" ]] || { echo "missing"; return; }
  python3 - "$log" <<'PY'
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
lines = [ln for ln in p.read_text(encoding="utf-8").splitlines() if ln.strip()]
if not lines:
    print("missing"); raise SystemExit
print(json.loads(lines[-1]).get("status", "unknown"))
PY
}

last_run_age_hours() {
  local job_id="$1"
  local log="${RUNS}/${job_id}.jsonl"
  [[ -f "$log" ]] || { echo "999999"; return; }
  python3 - "$log" <<'PY'
import json, sys, time
from pathlib import Path
p = Path(sys.argv[1])
lines = [ln for ln in p.read_text(encoding="utf-8").splitlines() if ln.strip()]
if not lines:
    print(999999); raise SystemExit
ts = json.loads(lines[-1]).get("ts") or json.loads(lines[-1]).get("runAtMs") or 0
print(int((time.time()*1000 - ts) / 3600000))
PY
}

check_job() {
  local gate_id="$1"
  local job_id="$2"
  local max_age_h="${3:-48}"
  local st
  st="$(last_run_status "$job_id")"
  local age
  age="$(last_run_age_hours "$job_id")"
  if [[ "$st" == "ok" && "$age" -le "$max_age_h" ]]; then
    ok "${gate_id} ${job_id} status=ok age=${age}h"
  else
    bad "${gate_id} ${job_id} status=${st} age=${age}h (max ${max_age_h}h)"
  fi
}

[[ "${1:-}" == "--check" ]] || { echo "usage: $0 --check" >&2; exit 2; }

# AI-CRON-1..3 critical jobs
check_job AI-CRON-1 e1a2b3c4-email-daily-digest 36
check_job AI-CRON-2 b7c8d9e0-skylight-family-morning 36
check_job AI-CRON-3 eeb9dfa1-a825-4e7f-ad3a-f94c8ab03889 2

# AI-CRON-4: shell-direct manifest jobs must be disabled in OpenClaw cron
if [[ -f "$MANIFEST" && -f "$JOBS_JSON" ]]; then
  python3 - "$MANIFEST" "$JOBS_JSON" <<'PY' | while read -r line; do
import json, sys
from pathlib import Path
try:
    import yaml
except ImportError:
    raise SystemExit(0)
manifest = yaml.safe_load(Path(sys.argv[1]).read_text()) or {}
jobs = json.loads(Path(sys.argv[2]).read_text()).get("jobs", [])
by_id = {j["id"]: j for j in jobs}
for row in manifest.get("jobs", []):
    jid = row["id"]
    j = by_id.get(jid)
    if not j:
        print(f"WARN AI-CRON-4 missing openclaw job {jid}")
        continue
    if j.get("enabled", True):
        print(f"FAIL AI-CRON-4 {row['name']} still enabled in OpenClaw cron (should be shell-direct only)")
    else:
        print(f"PASS AI-CRON-4 {row['name']} disabled in OpenClaw cron")
PY
    case "$line" in
      PASS*) ok "${line#PASS }" ;;
      FAIL*) bad "${line#FAIL }" ;;
      WARN*) warn "${line#WARN }" ;;
    esac
  done
fi

# DIS-1: household dispatch dry-run gate (uses batch proposal id when available)
BATCH="${OPENCLAW}/state/household-proposals/batch-latest.json"
TEST_PID=""
if [[ -f "$BATCH" ]]; then
  TEST_PID=$(python3 -c "import json; b=json.load(open('$BATCH')); p=next((x['id'] for x in b.get('proposals',[]) if x.get('status') in ('pending','rejected') and str(x.get('id','')).startswith('enrich-chore')), None); print(p or '')" 2>/dev/null || echo "")
fi
if [[ -n "$TEST_PID" ]]; then
  if bash "${OPENCLAW}/scripts/skylight-family-hub-dispatch.sh" --dry-run "@openclaw NO ${TEST_PID}" >/tmp/ai-dis1.out 2>&1 \
    && grep -qE 'DRY-RUN C1b:|Gate C1b:' /tmp/ai-dis1.out; then
    ok "DIS-1 dispatch dry-run NO ${TEST_PID}"
  else
    bad "DIS-1 dispatch dry-run failed: $(tail -1 /tmp/ai-dis1.out 2>/dev/null)"
  fi
else
  warn "DIS-1 no enrich-chore proposal in batch (run propose first)"
fi

# DIS-3: non-match exits 2
if bash "${OPENCLAW}/scripts/skylight-family-hub-dispatch.sh" "@openclaw what's for dinner?" >/dev/null 2>&1; then
  bad "DIS-3 non-proposal should exit 2"
else
  rc=$?
  [[ "$rc" -eq 2 ]] && ok "DIS-3 non-proposal exits 2" || bad "DIS-3 expected exit 2 got $rc"
fi

# TR-* Talk response gates
if [[ -x "${OPENCLAW}/scripts/talk-response-audit.sh" ]]; then
  if bash "${OPENCLAW}/scripts/talk-response-audit.sh" --check --phase all >/tmp/ai-tr-gates.out 2>&1; then
    ok "TR-ALL talk-response-audit --phase all"
  else
    bad "TR-ALL talk-response-audit failed: $(grep '^FAIL' /tmp/ai-tr-gates.out | head -3 | tr '\n' '; ')"
  fi
else
  bad "TR-ALL talk-response-audit.sh missing"
fi

echo "hard_fail=${HARD_FAIL} soft_fail=${SOFT_FAIL}"
exit "$HARD_FAIL"
