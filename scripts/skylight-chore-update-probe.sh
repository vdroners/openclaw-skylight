#!/usr/bin/env bash
# W-2: Prove chore PUT with start_time + routine on Dishes series.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/load-skylight-env.sh"

DISHES_GID="${SKYLIGHT_PROBE_CHORE_GID:-75506838}"
SNAP_DIR="${OPENCLAW_DIR:-$HOME/.openclaw}/state/household-proposals/snapshots"
mkdir -p "$SNAP_DIR"

python3 <<PY
import json, os, subprocess, sys, urllib.request
from pathlib import Path

fid = os.environ["SKYLIGHT_FRAME_ID"]
api = os.environ["SKYLIGHT_API_URL"]
auth = os.environ["SKYLIGHT_AUTHORIZATION"]
gid = "$DISHES_GID"
snap_dir = Path("$SNAP_DIR")

def cli_chores():
    out = subprocess.check_output(
        ["skylight", "chores", "listChores", "--frame-id", fid,
         "--after", "2026-05-29", "--before", "2026-07-28", "--json"],
        text=True,
    )
    return json.loads(out)

def find_series(chores, group_id):
    for c in chores.get("data") or []:
        a = c.get("attributes") or {}
        g = str(a.get("group") or c["id"].split("-")[0])
        if g == group_id:
            return c
    return None

def allowed_byhour(start_time):
    hour = int((start_time or "20:00").split(":")[0])
    if hour <= 8:
        return 6, "06:00"
    if hour <= 15:
        return 14, "14:00"
    return 20, "20:00"

def sync_rrule(recurrence_set, byhour):
    import re
    out = []
    for rule in recurrence_set or []:
        if not rule.startswith("RRULE:"):
            out.append(rule)
            continue
        body = rule[6:]
        body = re.sub(r";BYHOUR=\d+", "", body)
        body = re.sub(r";BYMINUTE=\d+", "", body)
        out.append(f"RRULE:{body};BYHOUR={byhour}")
    return out or [f"RRULE:FREQ=DAILY;INTERVAL=1;WKST=MO;BYHOUR={byhour}"]

def put_chore(body):
    data = json.dumps(body).encode()
    r = urllib.request.Request(
        f"{api}/frames/{fid}/chores/{gid}",
        data=data,
        headers={"Authorization": auth, "Content-Type": "application/json", "User-Agent": "SkylightMobile (web)"},
        method="PUT",
    )
    with urllib.request.urlopen(r, timeout=30) as resp:
        return resp.status, json.loads(resp.read().decode())

chores = cli_chores()
cur = find_series(chores, gid)
if not cur:
    print(f"Gate W-2: FAIL — series {gid} not found", file=sys.stderr)
    sys.exit(1)

a = cur.get("attributes") or {}
rel = (cur.get("relationships") or {}).get("category") or {}
cat_id = (rel.get("data") or {}).get("id")
snap_dir.joinpath("w2-dishes-pre.json").write_text(json.dumps(cur, indent=2))

target_time = "20:00"
routine = True
bh, slot_time = allowed_byhour(target_time)
body = {
    "summary": a.get("summary") or "Dishes",
    "reward_points": a.get("reward_points") or 1,
    "routine": routine,
    "recurrence_set": sync_rrule(a.get("recurrence_set"), bh),
    "start": a.get("start"),
    "category_id": cat_id,
}
try:
    status, resp = put_chore(body)
except urllib.error.HTTPError as e:
    print(f"Gate W-2: FAIL PUT HTTP {e.code} {e.read().decode()}", file=sys.stderr)
    sys.exit(1)

chores2 = cli_chores()
after = find_series(chores2, gid)
aa = (after or {}).get("attributes") or {}
snap_dir.joinpath("w2-dishes-post.json").write_text(json.dumps(after, indent=2))

ok = aa.get("start_time") and aa.get("routine") is True
print(f"Gate W-2: {'PASS' if ok else 'FAIL'} — Dishes start_time={aa.get('start_time')} routine={aa.get('routine')} HTTP={status}")
sys.exit(0 if ok else 1)
PY
