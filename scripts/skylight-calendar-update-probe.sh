#!/usr/bin/env bash
# W-1: PATCH calendar event location+description on daniel default + mom calendar; then DELETE.
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
daniel_cal = os.environ.get("SKYLIGHT_DEFAULT_CALENDAR_ID", "1000101")
mom_cal = "1000102"
tomorrow = (date.today() + timedelta(days=1)).isoformat()

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
        "summary": f"Alfred smoke: update probe ({label})",
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
        "location": "123 Probe St, Portland OR",
        "description": "Alfred PATCH probe — location and description",
    }
    if calendar_id:
        patch["calendar_id"] = int(calendar_id)
    for method in ("PUT", "PATCH"):
        code2, body2 = req(method, f"/frames/{fid}/calendar_events/{eid}", patch)
        if code2 in (200, 204):
            break
    else:
        print(f"W-1 FAIL patch {label}: PUT/PATCH failed", file=sys.stderr)
        req("DELETE", f"/frames/{fid}/calendar_events/{eid}")
        return False
    code3, _ = req("GET", f"/frames/{fid}/calendar_events/{eid}")
    req("DELETE", f"/frames/{fid}/calendar_events/{eid}")
    print(f"W-1 PASS {label} calendar_id={calendar_id or 'default'} patch_via={method}")
    return True

ok1 = probe("daniel")
ok2 = probe("mom", mom_cal)
sys.exit(0 if ok1 and ok2 else 1)
PY
