#!/usr/bin/env bash
# Bread bake timer — posts start confirmation and schedules completion nudge.
# Usage:
#   skylight-bread-timer.sh start "<recipe query>" [light|medium|dark] [--room TOKEN]
#   skylight-bread-timer.sh fire <timer-id>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/load-skylight-env.sh"

STATE_DIR="${OPENCLAW_DIR:-$HOME/.openclaw}/state/bread-timers"
mkdir -p "$STATE_DIR"

CMD="${1:-}"
shift || true

case "$CMD" in
  start)
    QUERY=""
    CRUST="medium"
    ROOM="${SKYLIGHT_FAMILY_TALK_ROOM:-}"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --room) ROOM="$2"; shift 2 ;;
        light|medium|dark) CRUST="$1"; shift ;;
        *) QUERY="${QUERY:+$QUERY }$1"; shift ;;
      esac
    done
    [[ -n "$QUERY" ]] || { echo "usage: $0 start <recipe> [light|medium|dark] [--room TOKEN]" >&2; exit 1; }
    export QUERY CRUST ROOM SCRIPT_DIR STATE_DIR
    python3 <<'PY'
import json, os, subprocess, sys, uuid
from datetime import datetime, timedelta
from pathlib import Path

SCRIPT_DIR = Path(os.environ["SCRIPT_DIR"])
sys.path.insert(0, str(SCRIPT_DIR))
from skylight_recipe_lib import crust_duration_minutes, format_recipe_brief, search_recipes

query = os.environ["QUERY"]
crust = os.environ["CRUST"]
room = os.environ.get("ROOM") or ""
state_dir = Path(os.environ["STATE_DIR"])

matches = search_recipes(query)
if not matches:
    print(f"[recipe] No recipe matching {query!r}")
    sys.exit(1)
meta = matches[0]
prep = meta.get("prep_type") or ""
if prep == "hand-oven":
    mins = 15
    note = "Oven 425°F — check at 10–15 min"
else:
    mins = crust_duration_minutes(meta.get("crust_times") or {}, crust)
    if not mins:
        print("[recipe] Could not parse crust duration for this recipe.")
        sys.exit(1)
    note = f"Course {meta.get('machine_course')} {meta.get('machine_course_name')} — {crust.title()} crust"

end = datetime.now() + timedelta(minutes=mins)
timer_id = uuid.uuid4().hex[:12]
ready_label = end.strftime("%H:%M")
payload = {
    "id": timer_id,
    "title": meta["title"],
    "crust": crust,
    "started_at": datetime.now().isoformat(timespec="seconds"),
    "ready_at": end.isoformat(timespec="seconds"),
    "minutes": mins,
    "room": room,
}
(state_dir / f"{timer_id}.json").write_text(json.dumps(payload, indent=2), encoding="utf-8")

start_msg = (
    f"[recipe] Started **{meta['title']}**\n"
    f"{note}\n"
    f"Ready about **{ready_label}** ({mins} min)."
)
print(start_msg)

talk_post = Path(os.environ.get("OPENCLAW_DIR", Path.home() / ".openclaw")) / "scripts/talk-post.sh"
if room and talk_post.is_file():
    subprocess.run(["bash", str(talk_post), start_msg, room], check=False, capture_output=True, text=True)

fire_script = SCRIPT_DIR / "skylight-bread-timer.sh"
log = state_dir / f"{timer_id}.log"
subprocess.Popen(
    ["bash", "-c", f"sleep {mins * 60} && bash {fire_script} fire {timer_id} >> {log} 2>&1 &"],
    start_new_session=True,
)
PY
    ;;
  fire)
    TID="${1:-}"
    [[ -n "$TID" ]] || { echo "usage: $0 fire <timer-id>" >&2; exit 1; }
    export TID STATE_DIR SCRIPT_DIR
    python3 <<'PY'
import json, os, subprocess, sys
from pathlib import Path

state_dir = Path(os.environ["STATE_DIR"])
path = state_dir / f"{os.environ['TID']}.json"
if not path.is_file():
    sys.exit(0)
payload = json.loads(path.read_text())
room = payload.get("room") or ""
title = payload.get("title") or "Bread"
msg = f"[recipe] **{title}** — cycle time elapsed. Check the machine and remove the loaf if done."
print(msg)
talk_post = Path(os.environ.get("OPENCLAW_DIR", Path.home() / ".openclaw")) / "scripts/talk-post.sh"
if room and talk_post.is_file():
    subprocess.run(["bash", str(talk_post), msg, room], check=False)
path.unlink(missing_ok=True)
PY
    ;;
  -h|--help)
    echo "Usage: $0 start <recipe> [light|medium|dark] [--room TOKEN] | fire <timer-id>"
    ;;
  *)
    echo "Unknown command: $CMD" >&2
    exit 1
    ;;
esac
