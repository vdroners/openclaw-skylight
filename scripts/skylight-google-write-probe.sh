#!/usr/bin/env bash
# V-11: Create + delete a smoke calendar event (flat API body; uses frame default calendar).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/load-skylight-env.sh"

FID="$SKYLIGHT_FRAME_ID"
API="$SKYLIGHT_API_URL"
AUTH="$SKYLIGHT_AUTHORIZATION"
TZ="${SKYLIGHT_TIMEZONE:-America/Los_Angeles}"

TOMORROW=$(date -d tomorrow +%F 2>/dev/null || python3 -c "from datetime import date,timedelta; print((date.today()+timedelta(days=1)).isoformat())")

python3 <<PY
import json, os, sys, urllib.request
from datetime import date, timedelta

fid = os.environ["SKYLIGHT_FRAME_ID"]
api = os.environ["SKYLIGHT_API_URL"]
auth = os.environ["SKYLIGHT_AUTHORIZATION"]
tz = os.environ.get("SKYLIGHT_TIMEZONE", "America/Los_Angeles")
tomorrow = (date.today() + timedelta(days=1)).isoformat()
summary = "OpenClaw smoke: calendar write probe"
payload = {
    "summary": summary,
    "starts_at": f"{tomorrow}T09:00:00.000-07:00",
    "ends_at": f"{tomorrow}T09:30:00.000-07:00",
    "timezone": tz,
}
headers = {
    "Authorization": auth,
    "Content-Type": "application/json",
    "User-Agent": "SkylightMobile (web)",
    "Accept": "application/json",
}
req = urllib.request.Request(
    f"{api}/frames/{fid}/calendar_events",
    data=json.dumps(payload).encode(),
    headers=headers,
    method="POST",
)
try:
    with urllib.request.urlopen(req, timeout=30) as resp:
        data = json.loads(resp.read().decode())
except urllib.error.HTTPError as e:
    print(f"V-11 FAIL: create HTTP {e.code}", file=sys.stderr)
    print(e.read().decode(), file=sys.stderr)
    sys.exit(1)
event_id = (data.get("data") or {}).get("id")
if not event_id:
    print("V-11 FAIL: no event id", file=sys.stderr)
    sys.exit(1)
delreq = urllib.request.Request(
    f"{api}/frames/{fid}/calendar_events/{event_id}",
    headers={"Authorization": auth, "User-Agent": "SkylightMobile (web)"},
    method="DELETE",
)
try:
    with urllib.request.urlopen(delreq, timeout=30) as resp:
        pass
except urllib.error.HTTPError as e:
    print(f"V-11 WARN: created {event_id} but delete HTTP {e.code}", file=sys.stderr)
    sys.exit(1)
cal = os.environ.get("SKYLIGHT_DEFAULT_CALENDAR_ID", "frame-default")
print(f"V-11 PASS: created+deleted smoke event (calendar env={cal})")
PY
