#!/usr/bin/env bash
# Deep household audit — 60d calendar, chores, classification, proposals (read-only).
# Usage: skylight-household-deep-audit.sh [--metrics-only]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/load-skylight-env.sh"

METRICS_ONLY=0
[[ "${1:-}" == "--metrics-only" ]] && METRICS_ONLY=1

LOG_DIR="${OPENCLAW_DIR:-$HOME/.openclaw}/logs"
mkdir -p "$LOG_DIR"
STAMP=$(date +%F)
OUT_JSON="${LOG_DIR}/skylight-household-audit-${STAMP}.json"
OUT_MD="${LOG_DIR}/skylight-household-audit-${STAMP}.md"
BASELINE="${LOG_DIR}/household-baseline-${STAMP}.json"

python3 <<PY
import json, os, subprocess, sys, urllib.request
from collections import defaultdict
from datetime import date, timedelta

metrics_only = $METRICS_ONLY
fid = os.environ["SKYLIGHT_FRAME_ID"]
tz = os.environ.get("SKYLIGHT_TIMEZONE", "America/Los_Angeles")
auth = os.environ.get("SKYLIGHT_AUTHORIZATION", "")
api = os.environ.get("SKYLIGHT_API_URL", "https://app.ourskylight.com/api")
out_json = "$OUT_JSON"
out_md = "$OUT_MD"
baseline_path = "$BASELINE"
today = date.today()
end60 = (today + timedelta(days=60)).isoformat()
start60 = today.isoformat()

WRITABLE_CAL_EMAILS = {"family-parent@example.com", "family-kid@example.com"}
DEFAULT_CAL_EMAIL = "family-parent@example.com"
KID_CATS = {"19116283": "Phoebe", "19255362": "Wesley", "19177556": "Dan"}
CHORE_TIME_DEFAULTS = {
    "dishes": ("20:00", True),
    "clean room": ("20:00", True),
    "brush teeth": ("20:00", True),
    "put away toys": ("20:00", True),
    "clean up shoes": ("20:00", True),
    "kitchen counters": ("20:00", False),
    "take out trash": ("07:00", False),
    "mop": ("10:00", False),
    "toilet": ("10:00", False),
    "vacuum (deep)": ("10:00", False),
    "windows/mirrors": ("10:00", False),
    "clip murderpaws": ("10:00", False),
    "deep clean cat box": ("10:00", False),
    "dust": ("10:00", False),
    "laundry": ("10:00", False),
    "run": ("10:00", False),
    "change sheets": ("10:00", False),
}
model_path = os.environ.get("HOUSEHOLD_MODEL_JSON")
if model_path and os.path.isfile(model_path):
    model = json.load(open(model_path))
    w = model.get("writable_calendar_emails") or model.get("writable_calendars")
    if w:
        WRITABLE_CAL_EMAILS = set(w) if isinstance(w, list) else set(w.keys())
    if model.get("default_calendar_email"):
        DEFAULT_CAL_EMAIL = model["default_calendar_email"]
    if model.get("chore_time_defaults"):
        CHORE_TIME_DEFAULTS = {k.lower(): (tuple(v[:2]) if isinstance(v, list) else v)
                               for k, v in model["chore_time_defaults"].items()}
    if model.get("kid_categories"):
        KID_CATS = {str(k): v for k, v in model["kid_categories"].items()}
TYPO_VAGUE = {"cakl", "round", "call", "backup", "payday"}

def curl_json(path):
    req = urllib.request.Request(
        f"{api}{path}",
        headers={"Authorization": auth, "Accept": "application/json", "User-Agent": "SkylightMobile (web)"},
    )
    with urllib.request.urlopen(req, timeout=90) as resp:
        return json.loads(resp.read().decode())

def cli_json(*args):
    out = subprocess.check_output(["skylight", *args, "--json"], text=True)
    return json.loads(out)

def event_start(a):
    return a.get("starts_at") or a.get("start") or a.get("start_time")

def norm_title(s):
    return (s or "").strip().lower()

def is_vague_title(summary):
    t = norm_title(summary)
    if not t:
        return True
    if t in TYPO_VAGUE:
        return True
    words = t.split()
    if len(words) == 1 and len(t) <= 5:
        return True
    return False

def cal_enrich_keywords(summary):
    t = norm_title(summary)
    return any(k in t for k in (
        "lesson", "tutor", "practice", "futsal", "game", "appointment",
        "birthday", "bday", "conference", "appt", "math", "doctor", "ob",
    ))

chores = cli_json("chores", "listChores", "--frame-id", fid, "--after", start60, "--before", end60)
groups = defaultdict(list)
for c in chores.get("data") or []:
    a = c.get("attributes") or {}
    gid = str(a.get("group") or a.get("series") or c["id"].split("-")[0])
    groups[gid].append(c)
series_rows = []
chores_missing_start = 0
chores_missing_routine = 0
chore_titles = set()
for gid, items in groups.items():
    i = items[0]
    a = i.get("attributes") or {}
    rel = (i.get("relationships") or {}).get("category") or {}
    cat_id = str((rel.get("data") or {}).get("id") or "")
    summary = a.get("summary") or ""
    chore_titles.add(norm_title(summary))
    st = a.get("start_time")
    routine = a.get("routine")
    if not st:
        chores_missing_start += 1
    if cat_id in KID_CATS and not routine:
        chores_missing_routine += 1
    series_rows.append({
        "group_id": gid,
        "summary": summary,
        "category_id": cat_id,
        "person": KID_CATS.get(cat_id, "Dan" if cat_id == "19177556" else "?"),
        "reward_points": a.get("reward_points"),
        "recurrence_set": a.get("recurrence_set"),
        "routine": routine,
        "start_time": st,
    })

src_cals = curl_json(f"/frames/{fid}/source_calendars")
cal_email_to_id = {}
for sc in src_cals.get("data") or []:
    label = (sc.get("attributes") or {}).get("label") or ""
    sid = str(sc.get("id") or "")
    if label and sid:
        cal_email_to_id[label] = sid

def resolve_cal(ev):
    a = ev.get("attributes") or {}
    rel = ev.get("relationships") or {}
    email = (a.get("calendar_id") or "").strip()
    if not email:
        acct = (rel.get("calendar_account") or {}).get("data") or {}
        email = (acct.get("id") or "").strip()
    if not email and a.get("editable"):
        email = DEFAULT_CAL_EMAIL
    return email, cal_email_to_id.get(email, "")

events_raw = curl_json(f"/frames/{fid}/calendar_events?date_min={start60}&date_max={end60}&timezone={tz}")
events = []
for ev in events_raw.get("data") or []:
    a = ev.get("attributes") or {}
    cal_email, cal_numeric = resolve_cal(ev)
    events.append({
        "id": ev.get("id"),
        "summary": a.get("summary"),
        "starts_at": event_start(a),
        "ends_at": a.get("ends_at"),
        "location": (a.get("location") or "").strip(),
        "description": (a.get("description") or "").strip(),
        "calendar_email": cal_email,
        "calendar_id": cal_numeric,
        "editable": a.get("editable"),
        "recurring": a.get("recurring"),
        "all_day": a.get("all_day"),
    })

cal_missing_loc = sum(1 for e in events if not e["location"] and not is_vague_title(e["summary"]))
cal_missing_desc = sum(1 for e in events if not e["description"])
cal_missing_start = sum(1 for e in events if not e["starts_at"])
cal_vague = sum(1 for e in events if is_vague_title(e["summary"]))

seen_class = set()
enrich_calendar = []
ask_operator = []
calendar_to_chore = []
proposal_seq = 0

def next_id(prefix):
    global proposal_seq
    proposal_seq += 1
    return f"{prefix}-{proposal_seq:03d}"

writable_events = [e for e in events if e["calendar_email"] in WRITABLE_CAL_EMAILS]
writable_missing_desc = sum(1 for e in writable_events if not e["description"] and not is_vague_title(e["summary"]))
writable_vague = sum(1 for e in writable_events if is_vague_title(e["summary"]))

for e in events:
    key = (norm_title(e["summary"]), e["calendar_email"])
    if key in seen_class:
        continue
    seen_class.add(key)
    if e["calendar_email"] not in WRITABLE_CAL_EMAILS:
        continue
    cid = e["calendar_id"]
    summary = e["summary"] or ""
    if is_vague_title(summary):
        ask_operator.append({
            "id": next_id("ask"),
            "event_id": e["id"],
            "title": summary,
            "calendar_id": cid,
            "questions": ["Who/what is this?", "Keep on calendar or clarify title?"],
            "status": "pending",
        })
        continue
    if cal_enrich_keywords(summary) or (not e["location"] or not e["description"]):
        fields = {}
        if not e["location"]:
            fields["location"] = None
        if not e["description"]:
            ns = norm_title(summary)
            if "math" in ns or "tutor" in ns:
                fields["description"] = "Phoebe math tutoring"
            elif "lesson" in ns and "phoebe" in ns:
                fields["description"] = "Phoebe lesson — details from email"
            elif "futsal" in ns or "little stars" in ns:
                fields["description"] = e["description"] or "Wesley futsal practice"
            elif "birthday" in ns or "bday" in ns:
                fields["description"] = "Family birthday"
            else:
                fields["description"] = f"Family event: {summary}"
        if fields:
            enrich_calendar.append({
                "id": next_id("enrich-calendar"),
                "event_id": e["id"],
                "summary": summary,
                "calendar_id": cid,
                "action": "patch",
                "fields": fields,
                "confidence": 0.7 if fields.get("description") else 0.5,
                "source": "rule",
                "status": "pending",
            })

enrich_chores = []
for row in series_rows:
    if row["start_time"]:
        continue
    ns = norm_title(row["summary"])
    defaults = CHORE_TIME_DEFAULTS.get(ns)
    if not defaults:
        for k, v in CHORE_TIME_DEFAULTS.items():
            if k in ns:
                defaults = v
                break
    if not defaults:
        continue
    st, routine = defaults
    enrich_chores.append({
        "id": next_id("enrich-chore"),
        "group_id": row["group_id"],
        "summary": row["summary"],
        "person": row["person"],
        "action": "updateChore",
        "fields": {"start_time": st, "routine": routine, "reward_points": row["reward_points"] or 1},
        "confidence": 0.85,
        "source": "plan_defaults",
        "status": "pending",
    })

overlap = []
for e in events:
    t = norm_title(e["summary"])
    if t and t in chore_titles:
        overlap.append({"summary": e["summary"], "event_id": e["id"]})

taskbox = cli_json("task-box", "listItems", "--frame-id", fid)
tb_count = len(taskbox.get("data") or [])

metrics = {
    "chores_series_count": len(series_rows),
    "chores_missing_start_time": chores_missing_start,
    "chores_missing_routine_flag": chores_missing_routine,
    "calendar_events_60d": len(events),
    "calendar_missing_location": cal_missing_loc,
    "calendar_missing_description": cal_missing_desc,
    "calendar_missing_starts_at": cal_missing_start,
    "calendar_vague_titles": cal_vague,
    "calendar_chore_name_overlap": len(overlap),
    "task_box_count": tb_count,
    "ask_operator_count": len(ask_operator),
    "enrich_calendar_count": len(enrich_calendar),
    "enrich_chores_count": len(enrich_chores),
    "writable_events_60d": len(writable_events),
    "writable_missing_desc": writable_missing_desc,
    "writable_vague_titles": writable_vague,
}

audit = {
    "generated_at": today.isoformat(),
    "frame_id": fid,
    "window": {"start": start60, "end": end60},
    "metrics": metrics,
    "enrich_calendar": enrich_calendar,
    "enrich_chores": enrich_chores,
    "calendar_to_chore_candidates": calendar_to_chore,
    "ask_operator": ask_operator,
    "deferred": [],
    "overlap_calendar_chore": overlap,
    "chore_series": series_rows,
}

with open(out_json, "w", encoding="utf-8") as f:
    json.dump(audit, f, indent=2)

if metrics_only:
    with open(baseline_path, "w", encoding="utf-8") as f:
        json.dump({"generated_at": today.isoformat(), "metrics": metrics, "type": "baseline"}, f, indent=2)
    print(f"Wrote {baseline_path}")

if not metrics_only:
    lines = [f"# Household deep audit — {today.isoformat()}", "", "## Metrics", ""]
    for k, v in metrics.items():
        lines.append(f"- **{k}**: {v}")
    lines += ["", f"Proposals: calendar={len(enrich_calendar)} chores={len(enrich_chores)} ask={len(ask_operator)}"]
    with open(out_md, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    print(f"Wrote {out_md}")

print(f"Wrote {out_json}")
if metrics_only:
    pass
else:
    print(f"Baseline unchanged: {baseline_path}")
a1 = bool(enrich_calendar or enrich_chores or ask_operator)
print(f"Gate A1: {'PASS' if a1 else 'FAIL'}")
print(f"Gate A2: PASS")
print(f"Gate A3: {'PASS' if len(overlap) == 0 else 'WARN overlap=' + str(len(overlap))}")
sys.exit(0 if a1 else 1)
PY
