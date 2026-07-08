#!/usr/bin/env bash
# Propose weekly meal plan (Dinner sittings) for Family Hub YES/NO flow.
# Usage: skylight-meal-plan-propose.sh [--dry-run] [--days N]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/load-skylight-env.sh"

ROOM="${SKYLIGHT_FAMILY_TALK_ROOM:-}"
STATE_DIR="${OPENCLAW_DIR:-$HOME/.openclaw}/state/household-proposals"
DRY=0
DAYS=7

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY=1; shift ;;
    --days) DAYS="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 [--dry-run] [--days N]"
      exit 0
      ;;
    *) echo "Unknown: $1" >&2; exit 1 ;;
  esac
done

export SCRIPT_DIR STATE_DIR ROOM DRY DAYS SKYLIGHT_FRAME_ID OPENCLAW_AGENT_MENTION

python3 <<'PY'
import json, os, subprocess, sys
from datetime import date, timedelta
from pathlib import Path

SCRIPT_DIR = Path(os.environ["SCRIPT_DIR"])
sys.path.insert(0, str(SCRIPT_DIR))

fid = os.environ["SKYLIGHT_FRAME_ID"]
room = os.environ.get("ROOM") or ""
dry = int(os.environ["DRY"])
days = int(os.environ["DAYS"])
mention = os.environ.get("OPENCLAW_AGENT_MENTION") or "@alfred"
state_dir = Path(os.environ["STATE_DIR"])
state_dir.mkdir(parents=True, exist_ok=True)

out = subprocess.check_output(
    ["skylight", "meals", "listRecipes", "--frame-id", fid, "--json"],
    text=True,
)
recipes = json.loads(out).get("data") or []
cats_out = subprocess.check_output(
    ["skylight", "meals", "listCategories", "--frame-id", fid, "--json"],
    text=True,
)
cat_label = {
    c["id"]: (c.get("attributes") or {}).get("label", "")
    for c in json.loads(cats_out).get("data") or []
}
dinner_id = next((cid for cid, lbl in cat_label.items() if lbl == "Dinner"), None)
pool = []
for r in recipes:
    attrs = r.get("attributes") or {}
    title = attrs.get("summary") or ""
    rel = (r.get("relationships") or {}).get("meal_category") or {}
    cat_id = (rel.get("data") or {}).get("id")
    lbl = cat_label.get(cat_id, "")
    if lbl in ("Dinner", "Lunch") or not dinner_id:
        pool.append({"id": r["id"], "title": title, "category_id": cat_id or dinner_id})
if not pool:
    print("No recipes on Skylight for meal plan.", file=sys.stderr)
    sys.exit(1)

start = date.today()
week_id = f"meal-plan-{start.isocalendar()[0]}-w{start.isocalendar()[1]:02d}"
sittings = []
for i in range(days):
    d = start + timedelta(days=i)
    pick = pool[i % len(pool)]
    sittings.append(
        {
            "date": d.isoformat(),
            "recipe_id": pick["id"],
            "recipe_title": pick["title"],
            "category_id": pick["category_id"] or dinner_id,
            "meal": "Dinner",
        }
    )

prop = {
    "id": week_id,
    "type": "meal_plan",
    "status": "pending",
    "title": f"Weekly meal plan ({start.isoformat()} + {days} days)",
    "sittings": sittings,
}

batch_path = state_dir / "batch-latest.json"
batch = {"proposals": [], "posted_at": date.today().isoformat()}
if batch_path.is_file():
    prev = json.loads(batch_path.read_text())
    batch["proposals"] = [p for p in prev.get("proposals", []) if not str(p.get("id", "")).startswith("meal-plan-")]
batch["proposals"].insert(0, prop)
batch_path.write_text(json.dumps(batch, indent=2), encoding="utf-8")
(stamp := state_dir / f"batch-{date.today().isoformat()}.json").write_text(json.dumps(batch, indent=2), encoding="utf-8")

lines = [
    f"**Meal plan proposal** `{week_id}`",
    f"Reply `{mention} YES {week_id}` to add {len(sittings)} dinners to Skylight.",
    f"Reply `{mention} NO {week_id}` to skip.",
    "",
]
for s in sittings:
    lines.append(f"- {s['date']} Dinner: {s['recipe_title']}")
body = "\n".join(lines)
print(body)

if dry:
    print(f"DRY-RUN meal plan {week_id} ({len(sittings)} sittings)")
    sys.exit(0)

if not room:
    print("SKYLIGHT_FAMILY_TALK_ROOM not set — batch saved only", file=sys.stderr)
    sys.exit(0)

subprocess.run(
    ["bash", str(SCRIPT_DIR / "talk-post.sh"), body, room],
    check=True,
)
print(f"Posted meal plan {week_id} to Family Hub")
PY
