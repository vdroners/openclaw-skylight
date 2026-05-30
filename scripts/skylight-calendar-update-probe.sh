#!/usr/bin/env bash
# W-1: PATCH calendar event location+description on primary + secondary writable calendars; then DELETE.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/load-skylight-env.sh"

python3 <<'PY'
import json, os, sys, urllib.request
from datetime import date, timedelta

fid = os.environ["SKYLIGHT_FRAME_ID"]
api = os.environ["SKYLIGHT_API_URL"]
auth = os.environ["SKYLIGHT_AUTHORIZATION"]
tz = os.environ.get("SKYLIGHT_TIMEZONE", "America/Los_Angeles")

primary_cal = os.environ.get("SKYLIGHT_DEFAULT_CALENDAR_ID", "")
secondary_cal = os.environ.get("SKYLIGHT_SECONDARY_CALENDAR_ID", "")
model_path = os.environ.get("HOUSEHOLD_MODEL_JSON")
if model_path and os.path.isfile(model_path):
    model = json.load(open(model_path))
    src = model.get("calendar_source_ids") or {}
    default_email = model.get("default_calendar_email", "")
    writable = model.get("writable_calendar_emails") or []
    secondary_email = writable[1] if len(writable) > 1 else (writable[0] if len(writable) == 1 else "")
    for em, key in ((default_email, "primary"), (secondary_email, "secondary")):
        if em and em in src:
            if key == "primary":
                primary_cal = primary_cal or str(src[em])
            elif secondary_email:
                secondary_cal = secondary_cal or str(src[em])

if not primary_cal or not secondary_cal:
    print("W-1 FAIL: set SKYLIGHT_DEFAULT_CALENDAR_ID / SKYLIGHT_SECONDARY_CALENDAR_ID or calendar_source_ids in household-model.json", file=sys.stderr)
    sys.exit(1)

tomorrow = (date.today() + timedelta(days=1)).isoformat()
print(f"W-1b: primary_cal={primary_cal} secondary_cal={secondary_cal}")

headers = {
    "Authorization": auth,
    "Content-Type": "application/json",
    "User-Agent": "SkylightMobile (web)",
    "Accept": "application/json",
}

def req(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(f"{api}{path}", data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(r, timeout=30) as resp:
            raw = resp.read().decode()
            return resp.status, json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()

def probe(label, calendar_id=None):
    payload = {
        "summary": f"OpenClaw smoke: update probe ({label})",
        "starts_at": f"{tomorrow}T09:00:00.000-07:00",
        "ends_at": f"{tomorrow}T09:30:00.000-07:00",
        "timezone": tz,
        "description": "probe create",
    }
    if calendar_id:
        payload["calendar_id"] = int(calendar_id)
    code, data = req("POST", f"/frames/{fid}/calendar_events", payload)
    if code not in (200, 201):
        print(f"W-1 FAIL create {label}: HTTP {code} {data}", file=sys.stderr)
        return False
    eid = (data.get("data") or {}).get("id")
    if not eid:
        print(f"W-1 FAIL no id {label}", file=sys.stderr)
        return False
    patch = {
        "summary": payload["summary"],
        "starts_at": payload["starts_at"],
        "ends_at": payload["ends_at"],
        "timezone": tz,
        "location": "123 Probe St, Example City",
        "description": "OpenClaw PATCH probe — location and description",
    }
    if calendar_id:
        patch["calendar_id"] = int(calendar_id)
    method = "PUT"
    for method in ("PUT", "PATCH"):
        code2, body2 = req(method, f"/frames/{fid}/calendar_events/{eid}", patch)
        if code2 in (200, 204):
            break
    else:
        print(f"W-1 FAIL patch {label}: PUT/PATCH failed", file=sys.stderr)
        req("DELETE", f"/frames/{fid}/calendar_events/{eid}")
        return False
    req("GET", f"/frames/{fid}/calendar_events/{eid}")
    req("DELETE", f"/frames/{fid}/calendar_events/{eid}")
    print(f"W-1 PASS {label} calendar_id={calendar_id or 'default'} patch_via={method}")
    return True

ok1 = probe("primary", primary_cal)
ok2 = probe("secondary", secondary_cal)
if primary_cal.startswith("100010") or secondary_cal.startswith("100010"):
    print("W-1b FAIL: placeholder calendar IDs detected", file=sys.stderr)
    sys.exit(1)
print(f"Gate W-1b: PASS primary={primary_cal} secondary={secondary_cal}")
sys.exit(0 if ok1 and ok2 else 1)
PY
