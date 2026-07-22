#!/usr/bin/env bash
# Lookup BB-PDC20 snapshot recipes (CLI / Alfred exec).
# Usage:
#   skylight-recipe-lookup.sh "banana"
#   skylight-recipe-lookup.sh --id banana-banana-bread
#   skylight-recipe-lookup.sh --list web
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SCRIPT_DIR

python3 - "$@" <<'PY'
import sys
from pathlib import Path

SCRIPT_DIR = Path(__import__("os").environ["SCRIPT_DIR"])
sys.path.insert(0, str(SCRIPT_DIR))

from skylight_recipe_lib import BB_SNAPSHOT, format_recipe_brief, manifest_index, search_recipes

args = sys.argv[1:]
if not args or args[0] in ("-h", "--help"):
    print("Usage: skylight-recipe-lookup.sh [--id slug] [--list web] [query]")
    raise SystemExit(0)

if args[0] == "--list":
    section = args[1] if len(args) > 1 else None
    rows = search_recipes("", section=section)
    for r in rows:
        c = r.get("machine_course_name") or "MANUAL"
        print(f"{r['id']}\t{r['title']}\t{c}")
    raise SystemExit(0)

if args[0] == "--id":
    slug = args[1]
    rows = [r for r in manifest_index(BB_SNAPSHOT) if r["id"] == slug]
    if not rows:
        print(f"No recipe id {slug!r}", file=sys.stderr)
        raise SystemExit(1)
    print(format_recipe_brief(rows[0]))
    raise SystemExit(0)

query = " ".join(args)
matches = search_recipes(query)
if not matches:
    print(f"No match for {query!r}", file=sys.stderr)
    raise SystemExit(1)
for i, meta in enumerate(matches[:3]):
    if i:
        print("\n---\n")
    print(format_recipe_brief(meta))
PY
