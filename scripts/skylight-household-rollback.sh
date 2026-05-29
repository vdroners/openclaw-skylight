#!/usr/bin/env bash
# Restore a proposal snapshot. Usage: rollback.sh --id enrich-chore-001
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/load-skylight-env.sh"

PID=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --id) PID="$2"; shift 2 ;;
    *) echo "Unknown: $1" >&2; exit 1 ;;
  esac
done
[[ -n "$PID" ]] || { echo "Usage: $0 --id <proposal-id>" >&2; exit 1; }

SNAP="${OPENCLAW_DIR:-$HOME/.openclaw}/state/household-proposals/snapshots/${PID}-pre.json"
[[ -f "$SNAP" ]] || { echo "No snapshot for $PID" >&2; exit 1; }

python3 <<PY
import json, os, sys, urllib.request
from pathlib import Path

pid = "$PID"
snap = json.loads(Path("$SNAP").read_text())
fid = os.environ["SKYLIGHT_FRAME_ID"]
api = os.environ["SKYLIGHT_API_URL"]
auth = os.environ["SKYLIGHT_AUTHORIZATION"]

if pid.startswith("enrich-chore"):
    a = snap.get("attributes") or {}
    rel = (snap.get("relationships") or {}).get("category") or {}
    gid = str(a.get("group") or snap["id"].split("-")[0])
    body = {
        "summary": a.get("summary"),
        "reward_points": a.get("reward_points"),
        "routine": a.get("routine"),
        "start_time": a.get("start_time"),
        "recurrence_set": a.get("recurrence_set"),
        "start": a.get("start"),
        "category_id": (rel.get("data") or {}).get("id"),
    }
    url = f"{api}/frames/{fid}/chores/{gid}"
elif pid.startswith("enrich-calendar"):
    a = (snap.get("data") or {}).get("attributes") or snap.get("attributes") or {}
    eid = (snap.get("data") or {}).get("id") or snap.get("id")
    body = {
        "summary": a.get("summary"),
        "starts_at": a.get("starts_at"),
        "ends_at": a.get("ends_at"),
        "timezone": a.get("timezone"),
        "location": a.get("location") or "",
        "description": a.get("description") or "",
    }
    if a.get("calendar_id"):
        body["calendar_id"] = int(a["calendar_id"])
    url = f"{api}/frames/{fid}/calendar_events/{eid}"
else:
    print(f"Cannot rollback {pid}", file=sys.stderr)
    sys.exit(1)

r = urllib.request.Request(
    url, data=json.dumps(body).encode(),
    headers={"Authorization": auth, "Content-Type": "application/json", "User-Agent": "SkylightMobile (web)"},
    method="PUT",
)
with urllib.request.urlopen(r, timeout=30) as resp:
    print(f"Rollback {pid} HTTP {resp.status}")
PY
