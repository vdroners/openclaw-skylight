#!/usr/bin/env bash
# OpenClaw AI-layer gates — hard_fail on critical cron reliability (shell-direct + OpenClaw).
# Usage: openclaw-ai-gates.sh --check
set -euo pipefail

OPENCLAW="${OPENCLAW_DIR:-$HOME/.openclaw}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/load-skylight-env.sh" 2>/dev/null || true
MENTION="${OPENCLAW_AGENT_MENTION:-@openclaw}"
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
  if bash "${OPENCLAW}/scripts/skylight-family-hub-dispatch.sh" --dry-run "${MENTION} NO ${TEST_PID}" >/tmp/ai-dis1.out 2>&1 \
    && grep -qE 'DRY-RUN C1b:|Gate C1b:' /tmp/ai-dis1.out; then
    ok "DIS-1 dispatch dry-run NO ${TEST_PID}"
  else
    bad "DIS-1 dispatch dry-run failed: $(tail -1 /tmp/ai-dis1.out 2>/dev/null)"
  fi
else
  warn "DIS-1 no enrich-chore proposal in batch (run propose first)"
fi

# DIS-3: non-match exits 2
if bash "${OPENCLAW}/scripts/skylight-family-hub-dispatch.sh" "${MENTION} what's for dinner?" >/dev/null 2>&1; then
  bad "DIS-3 non-proposal should exit 2"
else
  rc=$?
  [[ "$rc" -eq 2 ]] && ok "DIS-3 non-proposal exits 2" || bad "DIS-3 expected exit 2 got $rc"
fi

# CR-1: digest script direct
if bash "${OPENCLAW}/scripts/email-daily-digest-post.sh" >/tmp/ai-cr1.out 2>&1 \
  && grep -q 'DIGEST_POSTED' /tmp/ai-cr1.out; then
  ok "CR-1 email-daily-digest-post.sh DIGEST_POSTED"
else
  bad "CR-1 email-daily-digest-post.sh failed: $(tail -1 /tmp/ai-cr1.out 2>/dev/null)"
fi

# MDL-* model routing
if [[ -x "${SCRIPT_DIR}/validate-model-routing.sh" ]]; then
  if bash "${SCRIPT_DIR}/validate-model-routing.sh" --check >/tmp/ai-mdl.out 2>&1; then
    ok "MDL-ALL validate-model-routing.sh"
  else
    grep -E '^(PASS|FAIL|WARN) ' /tmp/ai-mdl.out | while read -r line; do
      case "$line" in
        PASS*) ok "${line#PASS }" ;;
        FAIL*) bad "${line#FAIL }" ;;
        WARN*) warn "${line#WARN }" ;;
      esac
    done
  fi
elif [[ -x "${OPENCLAW}/scripts/validate-model-routing.sh" ]]; then
  bash "${OPENCLAW}/scripts/validate-model-routing.sh" --check >/tmp/ai-mdl.out 2>&1 \
    && ok "MDL-ALL validate-model-routing.sh" \
    || bad "MDL validate-model-routing failed (see /tmp/ai-mdl.out)"
else
  warn "MDL skipped — validate-model-routing.sh missing"
fi

# CR-AUDIT critical shell-direct cron errors
if [[ -x "${OPENCLAW}/scripts/cron-audit.sh" ]]; then
  if bash "${OPENCLAW}/scripts/cron-audit.sh" --check >/tmp/ai-cron-audit.out 2>&1; then
    ok "CR-AUDIT cron-audit.sh --check"
  else
    bad "CR-AUDIT cron-audit failed: $(grep CR-AUDIT /tmp/ai-cron-audit.out | tail -1 || tail -1 /tmp/ai-cron-audit.out)"
  fi
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

# FT-* / G-ALF flight-triage gates
FT_GATES=""
for cand in \
  "${OPENCLAW}/scripts/openclaw-flight-triage-gates.sh" \
  "${OPENCLAW}/scripts/alfred-flight-triage-gates.sh" \
  "/media/4TB/openclaw-skylight/scripts/openclaw-flight-triage-gates.sh"
do
  if [[ -x "$cand" ]]; then FT_GATES="$cand"; break; fi
done
if [[ -n "$FT_GATES" ]]; then
  if bash "$FT_GATES" >/tmp/ai-ft-gates.out 2>&1; then
    ok "FT-ALL openclaw-flight-triage-gates"
  else
    bad "FT-ALL flight-triage gates failed: $(grep ' FAIL ' /tmp/ai-ft-gates.out | head -3 | tr '\n' '; ')"
  fi
else
  bad "FT-ALL openclaw-flight-triage-gates.sh missing"
fi

# FORGE-* 3DPrintForge integration gates
if [[ "${FORGE_ENABLED:-0}" == "1" ]] && [[ -x "${OPENCLAW}/scripts/forge-gates.sh" ]]; then
  if bash "${OPENCLAW}/scripts/forge-gates.sh" --check --phase infra,cfg,webhook,monitor,fastpath,talk >/tmp/ai-forge-gates.out 2>&1; then
    ok "FORGE-ALL automated forge gates"
  else
    bad "FORGE-ALL forge gates failed: $(grep '^FAIL' /tmp/ai-forge-gates.out | head -3 | tr '\n' '; ')"
  fi
fi

# G-DAY week-2 perf / cap / sess gates
if [[ -x "${OPENCLAW}/scripts/openclaw-day-review.sh" ]]; then
  set +e
  bash "${OPENCLAW}/scripts/openclaw-day-review.sh" --check >/tmp/ai-day-review.out 2>&1
  day_rc=$?
  set -e
  if [[ "$day_rc" -eq 0 ]]; then
    ok "G-DAY openclaw-day-review.sh --check"
  else
    grep -E '^(PASS|FAIL|WARN) ' /tmp/ai-day-review.out | while read -r line; do
      case "$line" in
        PASS*) ok "${line#PASS }" ;;
        FAIL*) bad "${line#FAIL }" ;;
        WARN*) warn "${line#WARN }" ;;
      esac
    done
  fi
else
  warn "G-DAY openclaw-day-review.sh missing"
fi

echo "hard_fail=${HARD_FAIL} soft_fail=${SOFT_FAIL}"
exit "$HARD_FAIL"
