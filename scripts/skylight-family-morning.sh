#!/usr/bin/env bash
# Family morning digest v2 — calendar, chores by person, points, meals, grocery.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/load-skylight-env.sh"

FID="$SKYLIGHT_FRAME_ID"
TODAY=$(date +%F)
TOMORROW=$(date -d tomorrow +%F 2>/dev/null || python3 -c "from datetime import date,timedelta; print((date.today()+timedelta(days=1)).isoformat())")
WEEK=$(date -d '+7 days' +%F 2>/dev/null || python3 -c "from datetime import date,timedelta; print((date.today()+timedelta(days=7)).isoformat())")
GROCERY_ID="${SKYLIGHT_DEFAULT_GROCERY_LIST_ID:-5948982}"

python3 <<PY
import json, os, subprocess, urllib.request
from collections import defaultdict
from datetime import date

fid = os.environ["SKYLIGHT_FRAME_ID"]
today = "$TODAY"
tomorrow = "$TOMORROW"
week_end = "$WEEK"
grocery_id = "$GROCERY_ID"
tz = os.environ.get("SKYLIGHT_TIMEZONE", "America/Los_Angeles")
auth = os.environ.get("SKYLIGHT_AUTHORIZATION") or (
    "Bearer " + os.environ["SKYLIGHT_RAW_TOKEN"] if os.environ.get("SKYLIGHT_RAW_TOKEN") else ""
)
if not auth:
    raise SystemExit("missing SKYLIGHT_AUTHORIZATION")
api = os.environ.get("SKYLIGHT_API_URL", "https://app.ourskylight.com/api")

PERSON_ORDER = ["Phoebe", "Wesley", "Dan", "Family", "Other"]

def curl_json(path):
    req = urllib.request.Request(
        f"{api}{path}",
        headers={"Authorization": auth, "Accept": "application/json", "User-Agent": "SkylightMobile (web)"},
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode())

def cli_json(*args):
    out = subprocess.check_output(["skylight", *args, "--json"], text=True)
    return json.loads(out)

lines = [f"# Family morning — {today}", ""]

cats = cli_json("categories", "listCategories", "--frame-id", fid)
cat_map = {c["id"]: (c.get("attributes") or {}).get("label", "?") for c in (cats.get("data") or [])}
chore_cats = {c["id"]: (c.get("attributes") or {}).get("label", "?")
              for c in (cats.get("data") or []) if (c.get("attributes") or {}).get("selected_for_chore_chart")}

for label, dmin, dmax in [("Today", today, today), ("Tomorrow", tomorrow, tomorrow)]:
    try:
        cal = curl_json(f"/frames/{fid}/calendar_events?date_min={dmin}&date_max={dmax}&timezone={tz}")
        events = cal.get("data") or []
        lines.append(f"## Calendar {label.lower()}")
        if not events:
            lines.append("- (no events)")
        else:
            for ev in events[:10]:
                attrs = ev.get("attributes") or {}
                summary = attrs.get("summary") or "(untitled)"
                start = attrs.get("start") or attrs.get("start_time") or ""
                lines.append(f"- {start} {summary}".strip())
        lines.append("")
    except Exception as e:
        lines.append(f"_Calendar {label.lower()} fetch failed: {e}_")
        lines.append("")

try:
    pts = cli_json("reward-points", "get", "--frame-id", fid)
    lines.append("## Reward points")
    rows = pts if isinstance(pts, list) else (pts.get("data") or [])
    if not rows:
        lines.append("- (no balances)")
    else:
        shown = 0
        for row in rows:
            if isinstance(row, dict) and "category_id" in row:
                cid = str(row.get("category_id"))
                name = cat_map.get(cid, cid)
                bal = row.get("current_point_balance")
            else:
                cid = (row.get("relationships") or {}).get("category", {}).get("data", {}).get("id")
                name = cat_map.get(cid, cid or "?")
                bal = (row.get("attributes") or {}).get("balance")
            if name in PERSON_ORDER[:3]:
                lines.append(f"- {name}: {bal} pts")
                shown += 1
        if shown == 0:
            lines.append("- (no kid balances)")
    lines.append("")
except Exception as e:
    lines.append(f"_Points fetch failed: {e}_")
    lines.append("")

try:
    chores = cli_json("chores", "listChores", "--frame-id", fid, "--after", today, "--before", tomorrow)
    pending = [c for c in (chores.get("data") or []) if (c.get("attributes") or {}).get("status") != "completed"]
    by_person = defaultdict(list)
    for c in pending:
        rel = (c.get("relationships") or {}).get("category") or {}
        cid = (rel.get("data") or {}).get("id")
        person = cat_map.get(cid) or "Other"
        if person not in PERSON_ORDER:
            person = "Other"
        summary = (c.get("attributes") or {}).get("summary") or "?"
        by_person[person].append(summary)
    lines.append("## Chores today")
    if not pending:
        lines.append("- All clear")
    else:
        for person in PERSON_ORDER:
            items = by_person.get(person) or []
            if not items:
                continue
            lines.append(f"### {person}")
            for s in items[:6]:
                lines.append(f"- [ ] {s}")
            if len(items) > 6:
                lines.append(f"- …{len(items) - 6} more")
    lines.append("")
except Exception as e:
    lines.append(f"_Chores fetch failed: {e}_")
    lines.append("")

try:
    sittings = cli_json("meals", "listSittings", "--frame-id", fid, "--date-min", today, "--date-max", week_end)
    sit_data = sittings.get("data") or []
    lines.append("## Meals this week")
    if not sit_data:
        lines.append("- (no meal plan yet)")
    else:
        for s in sit_data[:10]:
            a = s.get("attributes") or {}
            when = a.get("date") or a.get("served_at") or ""
            meal = a.get("meal_type") or a.get("summary") or "meal"
            recipe = a.get("recipe_summary") or a.get("summary") or ""
            lines.append(f"- {when} {meal}: {recipe}".strip())
        if len(sit_data) > 10:
            lines.append(f"- …{len(sit_data) - 10} more")
    lines.append("")
except Exception as e:
    lines.append(f"_Meals fetch failed: {e}_")
    lines.append("")

try:
    gitems = cli_json("lists", "listItems", "--frame-id", fid, "--list-id", grocery_id)
    open_items = [x for x in (gitems.get("data") or []) if (x.get("attributes") or {}).get("status") != "completed"]
    lines.append("## Grocery")
    if not open_items:
        lines.append("- List empty")
    else:
        for it in open_items[:10]:
            label = (it.get("attributes") or {}).get("label") or "?"
            lines.append(f"- {label}")
        if len(open_items) > 10:
            lines.append(f"- …and {len(open_items) - 10} more")
    lines.append("")
except Exception as e:
    lines.append(f"_Grocery fetch failed: {e}_")
    lines.append("")

out = "\n".join(lines).strip()
if len(out) > 4000:
    out = out[:3990] + "\n…(truncated)"
print(out)
PY
