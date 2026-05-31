#!/usr/bin/env bash
# Run a post script directly (no LLM). Append OpenClaw-compatible run log for ai-gates.
# Usage: run-openclaw-cron-shell.sh JOB_ID JOB_NAME SCRIPT [SUCCESS_GREP]
set -euo pipefail

JOB_ID="${1:?job id}"
JOB_NAME="${2:?job name}"
SCRIPT="${3:?script path}"
SUCCESS_GREP="${4:-POSTED}"

OPENCLAW="${OPENCLAW_DIR:-$HOME/.openclaw}"
RUNS="${OPENCLAW}/cron/runs"
LOG="${RUNS}/${JOB_ID}.jsonl"
START_MS=$(python3 -c 'import time; print(int(time.time()*1000))')

# shellcheck source=/dev/null
[[ -f "${OPENCLAW}/cron/env.sh" ]] && source "${OPENCLAW}/cron/env.sh"
[[ -f "${OPENCLAW}/.env" ]] && set -a && source "${OPENCLAW}/.env" && set +a

mkdir -p "$RUNS"
TMP_OUT="$(mktemp)"
trap 'rm -f "$TMP_OUT"' EXIT

RC=0
if bash "$SCRIPT" >"$TMP_OUT" 2>&1; then
  RC=0
else
  RC=$?
fi
OUT="$(cat "$TMP_OUT")"
END_MS=$(python3 -c 'import time; print(int(time.time()*1000))')
DUR=$(( END_MS - START_MS ))

if [[ "$RC" -eq 0 ]] && grep -q "$SUCCESS_GREP" <<<"$OUT"; then
  STATUS=ok
  ERR=""
else
  STATUS=error
  ERR="${OUT:0:500}"
fi

SUMMARY="$(grep -E 'POSTED|watchdog|urgent-alert|AUDIT|MONITOR_OK|BACKUP_OK' <<<"$OUT" | tail -1 | tr -d '\n' | cut -c1-240 || true)"
[[ -n "$SUMMARY" ]] || SUMMARY="$(head -1 <<<"$OUT" | tr -d '\n' | cut -c1-240)"

python3 - "$LOG" "$JOB_ID" "$JOB_NAME" "$START_MS" "$END_MS" "$DUR" "$STATUS" "$SUMMARY" "$ERR" <<'PY'
import json, sys
log, job_id, job_name, start_ms, end_ms, dur, status, summary, err = sys.argv[1:]
entry = {
    "ts": int(end_ms),
    "jobId": job_id,
    "jobName": job_name,
    "action": "finished",
    "status": status,
    "summary": summary or f"shell-direct {job_name}",
    "runAtMs": int(start_ms),
    "durationMs": int(dur),
    "provider": "shell-direct",
    "deliveryStatus": "n/a",
    "delivered": False,
}
if err and status != "ok":
    entry["error"] = err[:500]
with open(log, "a", encoding="utf-8") as f:
    f.write(json.dumps(entry, ensure_ascii=False) + "\n")
PY

echo "$OUT"
exit "$RC"
