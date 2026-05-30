#!/usr/bin/env bash
# Verify recipe markdown parsing and post-import body (P12 gates).
# Usage:
#   skylight-import-recipes-verify.sh --dry-run <recipe.md>
#   skylight-import-recipes-verify.sh --check-imported "Basic White Bread"
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/load-skylight-env.sh"

MODE=""
FILE=""
TITLE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) MODE=dry-run; FILE="${2:-}"; shift 2 ;;
    --check-imported) MODE=check; TITLE="${2:-}"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 --dry-run <recipe.md> | --check-imported <title>"
      exit 0
      ;;
    *) echo "Unknown: $1" >&2; exit 1 ;;
  esac
done

python3 - "$MODE" "$FILE" "$TITLE" "$SCRIPT_DIR" <<'PY'
import json, os, subprocess, sys
from pathlib import Path

sys.path.insert(0, sys.argv[4])
from skylight_recipe_lib import extract_sidekick_from_markdown, parse_title

def parse_recipe(path: Path):
    text = path.read_text(encoding="utf-8")
    summary = parse_title(text, path.stem.replace("-", " ").title())
    block = "## Sidekick import" in text
    description = extract_sidekick_from_markdown(text, title=summary)
    source = "sidekick_block" if block else "body_fallback"
    ingredient_lines = [
        ln.strip() for ln in description.splitlines()
        if ln.strip().startswith("- ") or __import__("re").match(r"^\d+\.", ln.strip())
    ]
    return summary, description, source, ingredient_lines

mode = sys.argv[1]
if mode == "dry-run":
    path = Path(sys.argv[2])
    if not path.is_file():
        raise SystemExit(f"Missing file: {path}")
    summary, desc, source, ing = parse_recipe(path)
    has_table = "|" in desc
    ok = len(desc) >= 200 and source == "sidekick_block" and not has_table
    print(f"title={summary!r}")
    print(f"source={source}")
    print(f"description_len={len(desc)}")
    print(f"has_markdown_table={has_table}")
    print("ingredient_preview:")
    for ln in ing[:3]:
        print(f"  {ln}")
    print(f"P12-0: {'PASS' if ok else 'FAIL'}")
    sys.exit(0 if ok else 1)

if mode == "check":
    title = sys.argv[3]
    fid = os.environ["SKYLIGHT_FRAME_ID"]
    out = subprocess.check_output(
        ["skylight", "meals", "listRecipes", "--frame-id", fid, "--json"],
        text=True,
    )
    data = json.loads(out)
    matches = [
        r for r in data.get("data", [])
        if (r.get("attributes") or {}).get("summary") == title
    ]
    if not matches:
        print(f"P12-2/P12-4: FAIL — no recipe titled {title!r}")
        sys.exit(1)
    if len(matches) > 1:
        print(f"P12-3: WARN — {len(matches)} recipes titled {title!r}")
    rid = matches[0]["id"]
    body = (matches[0].get("attributes") or {}).get("description") or ""
    checks = {
        "has_ingredients": "Ingredients" in body or body.strip().startswith("- "),
        "has_course": "Course:" in body,
        "no_boilerplate": "Copy everything below" not in body,
        "no_table_pipes": "|" not in body,
        "min_length": len(body) >= 200,
    }
    print(f"recipe_id={rid} title={title!r}")
    for k, v in checks.items():
        print(f"  {k}={v}")
    ok = all(checks.values())
    print(f"P12-4: {'PASS' if ok else 'FAIL'}")
    sys.exit(0 if ok else 1)

raise SystemExit("Specify --dry-run or --check-imported")
PY
