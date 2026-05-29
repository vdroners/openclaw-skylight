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

python3 <<PY
import json, os, re, subprocess, sys
from pathlib import Path

def parse_recipe(path: Path):
    text = path.read_text(encoding="utf-8")
    m = re.search(r"^title:\s*[\"']?(.+?)[\"']?\s*$", text, re.M)
    summary = m.group(1).strip() if m else path.stem.replace("-", " ").title()
    block = re.search(r"## Sidekick import\s*\n(.*?)(?:\n## |\Z)", text, re.S)
    source = "sidekick_block" if block else "body_fallback"
    if block:
        description = block.group(1).strip()
    else:
        body = re.sub(r"^---\s*\n.*?\n---\s*\n", "", text, count=1, flags=re.S)
        description = body.strip()[:8000]
    ingredient_lines = [
        ln.strip() for ln in description.splitlines()
        if ln.strip().startswith("- ") or re.match(r"^\d+\.", ln.strip())
    ]
    return summary, description, source, ingredient_lines

mode = "$MODE"
if mode == "dry-run":
    path = Path("$FILE")
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
    title = "$TITLE"
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
