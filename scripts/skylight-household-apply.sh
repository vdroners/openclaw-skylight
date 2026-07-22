#!/usr/bin/env bash
# Apply an approved household proposal. Usage: apply.sh --id enrich-chore-003 [--dry-run]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/load-skylight-env.sh"

STATE_DIR="${OPENCLAW_DIR:-$HOME/.openclaw}/state/household-proposals"
SNAP_DIR="${STATE_DIR}/snapshots"
OPS_ROOM="${SKYLIGHT_OPS_TALK_ROOM:-}"
PID=""
DRY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --id) PID="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    *) echo "Unknown: $1" >&2; exit 1 ;;
  esac
done

[[ -n "$PID" ]] || { echo "Usage: $0 --id <proposal-id> [--dry-run]" >&2; exit 1; }

BATCH="${STATE_DIR}/batch-latest.json"
[[ -f "$BATCH" ]] || { echo "No batch-latest.json" >&2; exit 1; }
mkdir -p "$SNAP_DIR"

python3 <<PY
import json, os, re, subprocess, sys, time, urllib.request
from datetime import datetime
from pathlib import Path

pid = "$PID"
dry = $DRY
batch = json.loads(Path("$BATCH").read_text())
prop = next((p for p in batch["proposals"] if p["id"] == pid), None)
if not prop:
    print(f"Unknown proposal {pid}", file=sys.stderr)
    sys.exit(1)

fid = os.environ["SKYLIGHT_FRAME_ID"]
api = os.environ["SKYLIGHT_API_URL"]
auth = os.environ["SKYLIGHT_AUTHORIZATION"]
tz = os.environ.get("SKYLIGHT_TIMEZONE", "America/Los_Angeles")
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
        if g == str(group_id):
            return c
    return None

def allowed_byhour(start_time):
    hour = int((start_time or "20:00").split(":")[0])
    if hour <= 8:
        return 6, "06:00"
    if hour <= 15:
        return 14, "14:00"
    return 20, "20:00"

def sync_rrule(recurrence_set, byhour, routine):
    if not routine:
        return list(recurrence_set or [])
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

def alert_ops(msg):
    try:
        subprocess.run(["bash", "$SCRIPT_DIR/talk-post.sh", msg, "$OPS_ROOM"], check=False)
    except Exception:
        pass

if prop["id"].startswith("enrich-chore"):
    gid = prop["group_id"]
    f = prop.get("fields") or {}
    target_time = f.get("start_time") or "20:00"
    routine = bool(f.get("routine"))
    bh, slot_time = allowed_byhour(target_time)
    if dry:
        print(f"DRY: PUT chore {gid} slot=BYHOUR={bh} routine={routine}" if routine else f"DRY: PUT chore {gid} start_time={target_time} routine={routine}")
        sys.exit(0)
    chores = cli_chores()
    cur = find_series(chores, gid)
    if not cur:
        print(f"FAIL {pid}: chore series {gid} not found", file=sys.stderr)
        sys.exit(1)
    snap_dir.joinpath(f"{pid}-pre.json").write_text(json.dumps(cur, indent=2))
    a = cur.get("attributes") or {}
    rel = (cur.get("relationships") or {}).get("category") or {}
    cat_id = (rel.get("data") or {}).get("id")
    body = {
        "summary": a.get("summary") or prop.get("summary"),
        "reward_points": f.get("reward_points", a.get("reward_points") or 1),
        "routine": routine,
        "recurrence_set": sync_rrule(a.get("recurrence_set"), bh, routine),
        "start": a.get("start"),
        "category_id": cat_id,
    }
    if not routine:
        body["start_time"] = target_time
    data = json.dumps(body).encode()
    r = urllib.request.Request(
        f"{api}/frames/{fid}/chores/{gid}",
        data=data,
        headers={"Authorization": auth, "Content-Type": "application/json", "User-Agent": "SkylightMobile (web)"},
        method="PUT",
    )
    try:
        with urllib.request.urlopen(r, timeout=30) as resp:
            slot = f"BYHOUR={bh}" if routine else f"start_time={target_time}"
            print(f"Applied chore {pid} HTTP {resp.status} {slot} routine={routine}")
    except urllib.error.HTTPError as e:
        err = e.read().decode()
        print(f"FAIL {pid}: HTTP {e.code} {err}", file=sys.stderr)
        alert_ops(f"Household apply FAIL {pid}: HTTP {e.code}")
        sys.exit(1)
elif prop["id"].startswith("enrich-calendar"):
    eid = str(prop["event_id"])
    fields = prop.get("fields") or {}
    if dry:
        print(f"DRY: PATCH event {eid} fields={fields}")
        sys.exit(0)
    # Load from calendar list (GET by id often 404 for Google-synced events)
    from datetime import date, timedelta
    start60 = date.today().isoformat()
    end60 = (date.today() + timedelta(days=60)).isoformat()
    req = urllib.request.Request(
        f"{api}/frames/{fid}/calendar_events?date_min={start60}&date_max={end60}&timezone={tz}",
        headers={"Authorization": auth, "Accept": "application/json", "User-Agent": "SkylightMobile (web)"},
    )
    with urllib.request.urlopen(req, timeout=90) as resp:
        events = json.loads(resp.read().decode()).get("data") or []
    cur = next((ev for ev in events if str(ev.get("id")) == eid), None)
    if not cur:
        print(f"FAIL {pid}: event {eid} not found in 60d window", file=sys.stderr)
        alert_ops(f"Household apply FAIL {pid}: event not found")
        sys.exit(1)
    snap_dir.joinpath(f"{pid}-pre.json").write_text(json.dumps(cur, indent=2))
    a = cur.get("attributes") or {}
    body = {
        "summary": a.get("summary") or prop.get("summary"),
        "starts_at": a.get("starts_at"),
        "ends_at": a.get("ends_at"),
        "timezone": a.get("timezone") or tz,
        "location": fields.get("location") if fields.get("location") is not None else (a.get("location") or ""),
        "description": fields.get("description") or a.get("description") or "",
    }
    if prop.get("calendar_id"):
        body["calendar_id"] = int(prop["calendar_id"])
    data = json.dumps(body).encode()
    for method in ("PUT", "PATCH"):
        r = urllib.request.Request(
            f"{api}/frames/{fid}/calendar_events/{eid}",
            data=data,
            headers={"Authorization": auth, "Content-Type": "application/json", "User-Agent": "SkylightMobile (web)"},
            method=method,
        )
        try:
            with urllib.request.urlopen(r, timeout=30) as resp:
                print(f"Applied {pid} via {method} HTTP {resp.status}")
                break
        except urllib.error.HTTPError as e:
            if method == "PATCH":
                err = e.read().decode()
                print(f"FAIL {pid}: {e.code} {err}", file=sys.stderr)
                alert_ops(f"Household apply FAIL {pid}: HTTP {e.code}")
                sys.exit(1)
elif prop["id"].startswith("meal-plan-"):
    sittings = prop.get("sittings") or []
    if not sittings:
        print(f"FAIL {pid}: no sittings in proposal", file=sys.stderr)
        sys.exit(1)
    if dry:
        print(f"DRY: createSitting x{len(sittings)} for {pid}")
        for s in sittings:
            print(f"  {s.get('date')} {s.get('meal')}: {s.get('recipe_title')}")
        sys.exit(0)
    applied = 0
    for s in sittings:
        cmd = [
            "skylight", "meals", "createSitting",
            "--frame-id", fid,
            "--date", s["date"],
            "--category-id", str(s["category_id"]),
            "--recipe-id", str(s["recipe_id"]),
        ]
        r = subprocess.run(cmd, capture_output=True, text=True)
        if r.returncode != 0:
            err = (r.stderr or r.stdout or "createSitting failed")[:200]
            print(f"FAIL {pid} sitting {s.get('date')}: {err}", file=sys.stderr)
            alert_ops(f"Meal plan apply FAIL {pid} {s.get('date')}: {err[:80]}")
            sys.exit(1)
        applied += 1
        time.sleep(0.3)
    print(f"Applied meal plan {pid}: {applied} sittings")
else:
    print(f"Cannot auto-apply {pid} — use EDIT to create new proposal", file=sys.stderr)
    sys.exit(1)

prop["status"] = "applied"
prop["applied_at"] = datetime.utcnow().isoformat() + "Z"
Path("$BATCH").write_text(json.dumps(batch, indent=2))
print(f"P2 applied {pid}")
PY
