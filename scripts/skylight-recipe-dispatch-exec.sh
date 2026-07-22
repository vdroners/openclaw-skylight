#!/usr/bin/env bash
# Recipe / bread Talk dispatch (read-only lookup + bread timer start).
# Usage: skylight-recipe-dispatch-exec.sh "<message>"
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/load-skylight-env.sh"

MSG="${1:-}"
[[ -n "$MSG" ]] || { echo "usage: $0 \"<message>\"" >&2; exit 2; }

export SCRIPT_DIR MSG OPENCLAW_AGENT_MENTION SKYLIGHT_FAMILY_TALK_ROOM

python3 <<'PY'
import os
import sys
from pathlib import Path

SCRIPT_DIR = Path(os.environ["SCRIPT_DIR"])
sys.path.insert(0, str(SCRIPT_DIR))
sys.path.insert(0, str(SCRIPT_DIR / "lib"))

from recipe_talk_match import parse_recipe_command
from skylight_recipe_lib import (
    BB_SNAPSHOT,
    WEB_ADAPTATIONS_SECTION,
    bread_courses_help,
    format_recipe_brief,
    search_recipes,
)

agent = (os.environ.get("OPENCLAW_AGENT_MENTION") or "@alfred").lstrip("@")
kind, rest = parse_recipe_command(os.environ["MSG"], agent)
mention = os.environ.get("OPENCLAW_AGENT_MENTION") or "@alfred"

if not kind:
    print(f"[recipe] Try: {mention} recipe banana | {mention} bread courses")
    raise SystemExit(0)

if kind == "bread":
    parts = rest.split()
    sub = (parts[0] or "").lower() if parts else ""
    if sub in ("courses", "course", "help", "?"):
        print("[recipe]\n" + bread_courses_help(BB_SNAPSHOT))
        raise SystemExit(0)
    if sub == "start":
        query = " ".join(parts[1:-1]) if len(parts) >= 3 else " ".join(parts[1:])
        crust = parts[-1].lower() if len(parts) >= 2 and parts[-1].lower() in ("light", "medium", "dark") else "medium"
        if len(parts) >= 2 and parts[-1].lower() in ("light", "medium", "dark"):
            query = " ".join(parts[1:-1])
        else:
            query = " ".join(parts[1:])
        if not query.strip():
            print(f"[recipe] Usage: {mention} bread start <recipe> [light|medium|dark]")
            raise SystemExit(0)
        timer = SCRIPT_DIR / "skylight-bread-timer.sh"
        room = os.environ.get("SKYLIGHT_FAMILY_TALK_ROOM", "")
        import subprocess
        cmd = ["bash", str(timer), "start", query, crust]
        if room:
            cmd.extend(["--room", room])
        r = subprocess.run(cmd, capture_output=True, text=True)
        print(r.stdout.strip() or r.stderr.strip() or "[recipe] timer failed")
        raise SystemExit(0 if r.returncode == 0 else 1)
    print(f"[recipe] Bread commands:\n- {mention} bread courses\n- {mention} bread start <recipe> [light|medium|dark]")
    raise SystemExit(0)

# recipe kind
if rest.lower().startswith("list"):
    tail = rest[4:].strip().lower()
    section = WEB_ADAPTATIONS_SECTION if tail == "web" else None
    rows = search_recipes("", section=tail if tail == "web" else None)
    if tail == "web":
        rows = search_recipes("", section="web")
    elif tail:
        rows = search_recipes(tail)
    if not rows:
        print("[recipe] No recipes matched.")
        raise SystemExit(0)
    print(f"[recipe] {len(rows)} recipe(s):")
    for r in rows[:15]:
        c = r.get("machine_course_name") or ("MANUAL" if r.get("prep_type") == "hand-oven" else "?")
        print(f"- {r['title']} (Course: {c})")
    if len(rows) > 15:
        print(f"…{len(rows) - 15} more")
    raise SystemExit(0)

matches = search_recipes(rest)
if not matches:
    print(f"[recipe] No recipe matching {rest!r}. Try: {mention} recipe list web")
    raise SystemExit(0)
meta = matches[0]
if len(matches) > 1:
    alts = ", ".join(m["title"] for m in matches[1:4])
    header = f"[recipe] Best match: {meta['title']}"
    if alts:
        header += f" (also: {alts})"
    print(header)
else:
    print(f"[recipe] {meta['title']}")
print(format_recipe_brief(meta))
PY
