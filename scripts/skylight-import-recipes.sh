#!/usr/bin/env bash
# Import one structured recipe markdown file into Skylight via API.
# Usage: skylight-import-recipes.sh path/to/recipe.md [--category Breakfast|Lunch|Dinner|Snack]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/load-skylight-env.sh"

CATEGORY=""
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

export SCRIPT_DIR
python3 - "$FILE" "$CATEGORY" "$SCRIPT_DIR" <<'PY'
import json, os, subprocess, sys
from pathlib import Path

sys.path.insert(0, sys.argv[3])
from skylight_recipe_lib import (
    category_for_bb_file,
    extract_sidekick_from_markdown,
    list_categories,
    parse_title,
)

path = Path(sys.argv[1])
category_label = sys.argv[2] if sys.argv[2] else category_for_bb_file(path)
fid = os.environ["SKYLIGHT_FRAME_ID"]
text = path.read_text(encoding="utf-8")
summary = parse_title(text, path.stem.replace("-", " ").title())
description = extract_sidekick_from_markdown(text, title=summary)

cats = list_categories(fid)
cat_id = cats.get(category_label)
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
