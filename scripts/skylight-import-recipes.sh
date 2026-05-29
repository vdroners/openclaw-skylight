#!/usr/bin/env bash
# Import one structured recipe markdown file into Skylight via API.
# Usage: skylight-import-recipes.sh path/to/recipe.md [--category Breakfast|Lunch|Dinner|Snack]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/load-skylight-env.sh"

CATEGORY="Snack"
FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --category) CATEGORY="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 <recipe.md> [--category Breakfast|Lunch|Dinner|Snack]"
      exit 0
      ;;
    *) FILE="$1"; shift ;;
  esac
done

[[ -n "$FILE" && -f "$FILE" ]] || { echo "Missing recipe file" >&2; exit 1; }

python3 <<PY
import os, re, subprocess, sys
from pathlib import Path

path = Path("$FILE")
category_label = "$CATEGORY"
fid = os.environ["SKYLIGHT_FRAME_ID"]
text = path.read_text(encoding="utf-8")

# YAML frontmatter title
m = re.search(r"^title:\s*[\"']?(.+?)[\"']?\s*$", text, re.M)
summary = m.group(1).strip() if m else path.stem.replace("-", " ").title()

# Prefer Sidekick import block if present
block = re.search(r"## Sidekick import\s*\n(.*?)(?:\n## |\Z)", text, re.S)
if block:
    description = block.group(1).strip()
else:
    # Strip frontmatter
    body = re.sub(r"^---\s*\n.*?\n---\s*\n", "", text, count=1, flags=re.S)
    description = body.strip()[:8000]

cats = subprocess.check_output(
    ["skylight", "meals", "listCategories", "--frame-id", fid, "--json"],
    text=True,
)
import json
data = json.loads(cats)
cat_id = None
for c in data.get("data", []):
    if c.get("attributes", {}).get("label") == category_label:
        cat_id = c["id"]
        break
if not cat_id:
    raise SystemExit(f"Unknown meal category: {category_label}")

out = subprocess.check_output(
    [
        "skylight", "meals", "createRecipe",
        "--frame-id", fid,
        "--summary", summary,
        "--description", description,
        "--category-id", cat_id,
        "--json",
    ],
    text=True,
)
recipe = json.loads(out)
rid = recipe.get("data", {}).get("id")
print(f"IMPORTED recipe_id={rid} title={summary!r} category={category_label}")
PY
