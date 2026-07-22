#!/usr/bin/env bash
# Shell-direct 3DPrintForge / K1 Max monitor (no LLM).
# Usage: forge-print-monitor.sh [--dry-run] [--force-alert]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/load-forge-env.sh"

DRY=0
FORCE=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY=1 ;;
    --force-alert) FORCE=1 ;;
  esac
done

if [[ "${FORGE_ENABLED:-0}" != "1" ]]; then
  echo "FORGE_MONITOR_SKIP enabled=0"
  exit 0
fi

ALERT_ROOM="${FORGE_ALERT_TALK_ROOM:?set FORGE_ALERT_TALK_ROOM}"
STATE_DIR="${OPENCLAW_DIR}/state"
STATE_FILE="${STATE_DIR}/forge-monitor-last-alert.json"
mkdir -p "$STATE_DIR"

eval "$(python3 - "$SCRIPT_DIR" "$STATE_FILE" "$FORCE" <<'PY'
import json, os, sys, time
from pathlib import Path

sys.path.insert(0, os.path.join(sys.argv[1], "lib"))
from forge_api import (
    forge_request,
    get_printer_state,
    get_printers,
    get_slicer_status,
    normalize_print_state,
    printer_id,
    slicer_health_direct,
)

state_path = Path(sys.argv[2])
force = sys.argv[3] == "1"
pid = printer_id()
min_interval = int(os.environ.get("FORGE_ALERT_MIN_INTERVAL_M", "15")) * 60
stuck_h = float(os.environ.get("FORGE_STUCK_PRINT_H", "2"))
slicer_down_m = int(os.environ.get("FORGE_SLICER_DOWN_M", "10")) * 60
now = int(time.time())

prev = {}
if state_path.is_file():
    try:
        prev = json.loads(state_path.read_text())
    except Exception:
        prev = {}

code_p, printers = get_printers()
online = "unknown"
if code_p == 200 and isinstance(printers, list):
    for p in printers:
        if str(p.get("id")) == pid:
            online = str(p.get("state") or "offline").lower()
            break
elif code_p == 0:
    online = "forge_down"

code_s, state_raw = get_printer_state(pid)
st = normalize_print_state(state_raw if isinstance(state_raw, dict) else {})
status = st.get("status") or "unknown"
progress = st.get("progress")
filename = st.get("filename") or ""

d_code, d_health = slicer_health_direct()
slicer_ok = isinstance(d_health, dict) and d_health.get("ok") is True
if not slicer_ok:
    f_code, f_st = get_slicer_status()
    probe = (f_st.get("probe") or {}) if isinstance(f_st, dict) else {}
    slicer_ok = bool(probe.get("ok")) if isinstance(probe, dict) else False

snap = {
    "online": online,
    "status": status,
    "filename": filename,
    "progress": progress,
    "slicer_ok": slicer_ok,
    "updated_at": now,
}
if progress is not None:
    last_prog = prev.get("last_progress")
    last_prog_at = prev.get("last_progress_at") or now
    if last_prog != progress or prev.get("filename") != filename:
        snap["last_progress"] = progress
        snap["last_progress_at"] = now
    else:
        snap["last_progress"] = last_prog
        snap["last_progress_at"] = last_prog_at
else:
    snap["last_progress"] = prev.get("last_progress")
    snap["last_progress_at"] = prev.get("last_progress_at")

if not slicer_ok:
    down_since = prev.get("slicer_down_since") or now
    snap["slicer_down_since"] = down_since
else:
    snap["slicer_down_since"] = None

alerts = []
if force:
    alerts.append(("high", "FORGE TEST ALERT: monitor force-alert gate check"))
elif online == "forge_down":
    alerts.append(("high", "3DPrintForge API unreachable"))
elif online == "offline" and prev.get("online") == "online":
    alerts.append(("high", f"Printer {pid} offline in Forge"))
elif status in ("error", "failed") and prev.get("status") not in ("error", "failed"):
    alerts.append(("high", f"Print failed on {pid}: {filename or 'unknown file'}"))
elif status in ("cancelled",) and prev.get("status") not in ("cancelled",):
    alerts.append(("medium", f"Print cancelled on {pid}: {filename or 'unknown file'}"))
elif status in ("complete", "standby") and prev.get("status") in ("printing", "paused"):
    alerts.append(("low", f"Print complete on {pid}: {filename or 'unknown file'}"))
elif (
    status == "printing"
    and snap.get("last_progress") is not None
    and snap.get("last_progress_at")
    and (now - int(snap["last_progress_at"])) > int(stuck_h * 3600)
):
    alerts.append(("medium", f"Print may be stuck on {pid} ({filename or 'unknown'}) — no progress in {stuck_h}h"))
elif snap.get("slicer_down_since") and (now - int(snap["slicer_down_since"])) > slicer_down_m:
    if prev.get("slicer_alert_sent_at") is None or (now - int(prev.get("slicer_alert_sent_at"))) > min_interval:
        alerts.append(("medium", "Forge Slicer down > threshold"))
        snap["slicer_alert_sent_at"] = now

severity = "none"
summary = ""
if alerts:
    severity = alerts[0][0]
    summary = alerts[0][1]

last_alert = prev.get("last_alert") or {}
last_sig = last_alert.get("signature") or ""
last_at = int(last_alert.get("posted_at") or 0)
sig = f"{severity}:{summary}"
should_post = "0"
if summary and (sig != last_sig or (now - last_at) > min_interval or force):
    should_post = "1"
    snap["last_alert"] = {"signature": sig, "posted_at": now, "severity": severity}

# Persist rolling state (not just on alert)
keep = {k: snap.get(k) for k in (
    "online", "status", "filename", "progress", "slicer_ok", "updated_at",
    "last_progress", "last_progress_at", "slicer_down_since", "slicer_alert_sent_at", "last_alert",
)}
state_path.write_text(json.dumps(keep, indent=2))
import shlex
print(f"summary={shlex.quote(summary)}")
print(f"severity={shlex.quote(severity)}")
print(f"should_post={shlex.quote(should_post)}")
PY
)" || {
  echo "FORGE_MONITOR_PARSE_FAIL" >&2
  exit 1
}

if [[ -z "$summary" ]]; then
  echo "FORGE_MONITOR_OK online=ok"
  exit 0
fi

if [[ "$should_post" != "1" ]]; then
  echo "FORGE_MONITOR_DEDUPED summary=${summary}"
  exit 0
fi

MSG="[forge] ${summary}. ${FORGE_DASHBOARD_URL:-https://forge-vdroners.ddns.net}"
if [[ "$DRY" -eq 1 ]]; then
  echo "FORGE_MONITOR_DRY_RUN ${MSG}"
  echo "FORGE_MONITOR_OK"
  exit 0
fi

bash "${SCRIPT_DIR}/talk-post.sh" "$MSG" "$ALERT_ROOM"
echo "FORGE_ALERT_POSTED room=${ALERT_ROOM} summary=${summary}"
