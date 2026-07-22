#!/usr/bin/env bash
# Bulk-import bb-pdc20 (or any) recipe markdown files via Skylight API.
# Usage: skylight-import-recipes-batch.sh [--category Snack] [--limit N] [--dry-run] [--force] <recipe-dir>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMPORT="${SCRIPT_DIR}/skylight-import-recipes.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/load-skylight-env.sh"

CATEGORY=""
LIMIT=0
DRY=0
FORCE=0
DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --category) CATEGORY="$2"; shift 2 ;;
    --limit) LIMIT="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    --force) FORCE=1; shift ;;
    -h|--help)
      echo "Usage: $0 [--category Snack] [--limit N] [--dry-run] [--force] <recipe-root-dir>"
      echo "  Default category: auto from section folder (see skylight_recipe_lib SECTION_CATEGORY)"
      exit 0
      ;;
    *) DIR="$1"; shift ;;
  esac
done

[[ -n "$DIR" && -d "$DIR" ]] || { echo "Missing recipe directory" >&2; exit 1; }

EXISTING_FILE="$(mktemp)"
trap 'rm -f "$EXISTING_FILE"' EXIT

if (( ! FORCE )); then
  skylight meals listRecipes --frame-id "$SKYLIGHT_FRAME_ID" --json >"$EXISTING_FILE" 2>/dev/null || echo '{"data":[]}' >"$EXISTING_FILE"
fi

mapfile -t FILES < <(find "$DIR" -path '*/import-cards/*' -prune -o -name '*.md' -type f -print | grep -E '/[0-9]{2}-' | sort)

imported=0
skipped=0
failed=0
processed=0

for f in "${FILES[@]}"; do
  [[ "$(basename "$f")" == _section.md ]] && continue
  [[ "$f" == *"/import-cards/"* ]] && continue
  if (( LIMIT > 0 && processed >= LIMIT )); then
    echo "Stopped at limit $LIMIT"
    break
  fi
  processed=$((processed + 1))

  title="$(python3 - "$f" <<'PY'
import re, sys
from pathlib import Path
text = Path(sys.argv[1]).read_text(encoding="utf-8")
m = re.search(r'^title:\s*["\']?(.+?)["\']?\s*$', text, re.M)
print(m.group(1).strip() if m else Path(sys.argv[1]).stem.replace("-", " ").title())
PY
)"

  if (( ! FORCE && ! DRY )); then
    if python3 - "$EXISTING_FILE" "$title" <<'PY'
import json, sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text())
title = sys.argv[2]
for r in data.get("data", []):
    if (r.get("attributes") or {}).get("summary") == title:
        sys.exit(0)
sys.exit(1)
PY
    then
      echo "SKIP exists: $title"
      skipped=$((skipped + 1))
      continue
    fi
  fi

  if (( DRY )); then
    echo "DRY: $f ($title)"
    imported=$((imported + 1))
    continue
  fi

  echo "Importing: $title ($f)"
  if [[ -n "$CATEGORY" ]]; then
    import_cmd=(bash "$IMPORT" "$f" --category "$CATEGORY")
  else
    import_cmd=(bash "$IMPORT" "$f")
  fi
  if "${import_cmd[@]}"; then
    imported=$((imported + 1))
    sleep 0.5
  else
    echo "FAIL: $title" >&2
    failed=$((failed + 1))
  fi
done

echo "Batch complete: processed=$processed imported=$imported skipped=$skipped failed=$failed"
