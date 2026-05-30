#!/usr/bin/env bash
# Readonly Skylight household audit — exports JSON + markdown with V-1..V-12 gates.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/load-skylight-env.sh"

LOG_DIR="${OPENCLAW_DIR:-$HOME/.openclaw}/logs"
mkdir -p "$LOG_DIR"
STAMP=$(date +%F)
OUT_JSON="${LOG_DIR}/skylight-audit-${STAMP}.json"
OUT_MD="${LOG_DIR}/skylight-audit-${STAMP}.md"

FID="$SKYLIGHT_FRAME_ID"
TODAY=$(date +%F)
TOMORROW=$(date -d tomorrow +%F 2>/dev/null || python3 -c "from datetime import date,timedelta; print((date.today()+timedelta(days=1)).isoformat())")
WEEK=$(date -d '+14 days' +%F 2>/dev/null || python3 -c "from datetime import date,timedelta; print((date.today()+timedelta(days=14)).isoformat())")

python3 <<PY
import json, os, subprocess, sys, urllib.request
from collections import defaultdict
from datetime import date

fid = os.environ["SKYLIGHT_FRAME_ID"]
today = "$TODAY"
week_end = "$WEEK"
tz = os.environ.get("SKYLIGHT_TIMEZONE", "America/Los_Angeles")
auth = os.environ.get("SKYLIGHT_AUTHORIZATION", "")
api = os.environ.get("SKYLIGHT_API_URL", "https://app.ourskylight.com/api")
out_json = "$OUT_JSON"
out_md = "$OUT_MD"
script_dir = "$SCRIPT_DIR"

gates = {}

def curl_json(path):
    req = urllib.request.Request(
        f"{api}{path}",
        headers={"Authorization": auth, "Accept": "application/json", "User-Agent": "SkylightMobile (web)"},
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.loads(resp.read().decode())

def cli_json(*args):
    out = subprocess.check_output(["skylight", *args, "--json"], text=True)
    return json.loads(out)

audit = {"generated_at": date.today().isoformat(), "frame_id": fid, "gates": {}, "data": {}}

smoke = subprocess.run(["bash", f"{script_dir}/skylight-smoke.sh"], capture_output=True, text=True)
gates["V-1"] = {"pass": smoke.returncode == 0, "detail": (smoke.stdout or smoke.stderr)[-120:]}

cats = cli_json("categories", "listCategories", "--frame-id", fid)
audit["data"]["categories"] = cats
cat_list = cats.get("data") or []
ghost = [c for c in cat_list if ":" in (c.get("attributes") or {}).get("label", "")]
family = [c for c in cat_list if (c.get("attributes") or {}).get("selected_for_chore_chart")]
gates["V-2"] = {"pass": len(cat_list) >= 10, "profiles": len(cat_list), "chore_chart": len(family), "ghost_hex": len(ghost)}

src = curl_json(f"/frames/{fid}/source_calendars")
audit["data"]["source_calendars"] = src
cal_data = src.get("data") or []
default_cal = [c for c in cal_data if (c.get("attributes") or {}).get("default_for_new_events")]
default_cal_id = os.environ.get("SKYLIGHT_DEFAULT_CALENDAR_ID", "")
gates["V-3"] = {
    "pass": len(cal_data) >= 5,
    "count": len(cal_data),
    "default_calendar_id": default_cal[0]["id"] if default_cal else None,
    "env_default_calendar_id": default_cal_id,
}

chores = cli_json("chores", "listChores", "--frame-id", fid, "--after", today, "--before", week_end)
audit["data"]["chores_sample"] = chores
groups = defaultdict(list)
for c in chores.get("data") or []:
    a = c.get("attributes") or {}
    gid = str(a.get("group") or a.get("series") or c["id"].split("-")[0])
    groups[gid].append(c)
series_rows = []
none_pts = 0
for gid, items in sorted(groups.items(), key=lambda x: (x[1][0].get("attributes") or {}).get("summary", "")):
    i = items[0]
    a = i.get("attributes") or {}
    rel = (i.get("relationships") or {}).get("category") or {}
    cat_id = (rel.get("data") or {}).get("id")
    pts = a.get("reward_points")
    if pts is None:
        none_pts += 1
    series_rows.append({
        "group_id": gid,
        "summary": a.get("summary"),
        "category_id": cat_id,
        "reward_points": pts,
        "recurrence_set": a.get("recurrence_set"),
        "routine": a.get("routine"),
        "start_time": a.get("start_time"),
    })
audit["data"]["chore_series"] = series_rows
gates["V-4"] = {"pass": len(series_rows) > 0, "series_count": len(series_rows), "reward_points_none": none_pts}

taskbox = cli_json("task-box", "listItems", "--frame-id", fid)
audit["data"]["task_box"] = taskbox
tb_items = taskbox.get("data") or []
chore_names = {r["summary"].lower() for r in series_rows if r.get("summary")}
tb_names = {(x.get("attributes") or {}).get("summary", "").lower() for x in tb_items}
overlap = chore_names & tb_names
gates["V-5"] = {"pass": True, "task_box_count": len(tb_items), "overlap_count": len(overlap)}

lists = cli_json("lists", "listLists", "--frame-id", fid)
audit["data"]["lists"] = lists
grocery_id = os.environ.get("SKYLIGHT_DEFAULT_GROCERY_LIST_ID", "5948982")
gitems = cli_json("lists", "listItems", "--frame-id", fid, "--list-id", grocery_id)
audit["data"]["grocery_items"] = gitems
gi = gitems.get("data") or []
pending = [x for x in gi if (x.get("attributes") or {}).get("status") != "completed"]
completed = [x for x in gi if (x.get("attributes") or {}).get("status") == "completed"]
gates["V-6"] = {"pass": True, "pending": len(pending), "completed": len(completed)}

recipes = cli_json("meals", "listRecipes", "--frame-id", fid)
audit["data"]["recipes"] = recipes
rtitles = [(r.get("attributes") or {}).get("summary") for r in recipes.get("data") or []]
dupes = [t for t in set(rtitles) if rtitles.count(t) > 1 and t]
gates["V-7"] = {"pass": True, "recipe_count": len(rtitles), "duplicate_titles": dupes}

try:
    sittings = cli_json("meals", "listSittings", "--frame-id", fid, "--date-min", today, "--date-max", week_end)
    audit["data"]["meal_sittings"] = sittings
    gates["V-8"] = {"pass": True, "sittings_14d": len(sittings.get("data") or [])}
except subprocess.CalledProcessError as e:
    gates["V-8"] = {"pass": False, "error": str(e)}

rewards = curl_json(f"/frames/{fid}/rewards")
audit["data"]["rewards"] = rewards
rp = curl_json(f"/frames/{fid}/reward_points")
audit["data"]["reward_points"] = rp
gates["V-9"] = {"pass": True, "catalog_count": len(rewards.get("data") or [])}

try:
    events = curl_json(f"/frames/{fid}/calendar_events?date_min={today}&date_max={week_end}&timezone={tz}")
    audit["data"]["events_14d"] = events
    gates["V-10"] = {"pass": True, "events_14d": len(events.get("data") or [])}
except Exception as e:
    gates["V-10"] = {"pass": False, "error": str(e)}

probe = subprocess.run(["bash", f"{script_dir}/skylight-google-write-probe.sh"], capture_output=True, text=True)
gates["V-11"] = {"pass": probe.returncode == 0, "detail": (probe.stdout or probe.stderr or "")[-120:]}

pilot_titles = ["Basic White Bread", "Honey Bread", "Cranberry & Walnut Bread"]
found = [t for t in pilot_titles if rtitles.count(t) == 1]
dup_pilot = [t for t in pilot_titles if rtitles.count(t) > 1]
gates["V-12"] = {"pass": len(found) == 3, "found": found, "missing": [t for t in pilot_titles if t not in rtitles], "dupes": dup_pilot}

audit["gates"] = gates
with open(out_json, "w", encoding="utf-8") as f:
    json.dump(audit, f, indent=2)

cat_map = {c["id"]: (c.get("attributes") or {}).get("label") for c in cat_list}
lines = [
    f"# Skylight household audit — {today}",
    "",
    f"Frame \`{fid}\` | JSON: \`{out_json}\`",
    "",
    "## Gate summary",
    "",
    "| Gate | PASS | Detail |",
    "|------|------|--------|",
]
for gid in sorted(gates.keys()):
    g = gates[gid]
    detail = ", ".join(f"{k}={v}" for k, v in g.items() if k != "pass")[:100]
    lines.append(f"| {gid} | {'PASS' if g.get('pass') else 'FAIL'} | {detail} |")
lines += ["", "## Chore series", "", "| Group | Summary | Person | Pts | Routine |", "|-------|---------|--------|-----|---------|"]
for r in series_rows:
    person = cat_map.get(str(r.get("category_id")), r.get("category_id") or "?")
    lines.append(f"| {r['group_id']} | {r.get('summary')} | {person} | {r.get('reward_points')} | {r.get('routine')} |")
lines += ["", f"## Grocery: pending={len(pending)} completed={len(completed)}", f"## Task box overlap: {len(overlap)}", f"## Recipes: {len(rtitles)}"]
with open(out_md, "w", encoding="utf-8") as f:
    f.write("\n".join(lines) + "\n")

print(f"Wrote {out_json}")
print(f"Wrote {out_md}")
pa = all(gates.get(k, {}).get("pass") for k in ("V-1", "V-2", "V-3", "V-10"))
print(f"PA gate: {'PASS' if pa else 'FAIL'}")
sys.exit(0 if pa else 1)
PY
