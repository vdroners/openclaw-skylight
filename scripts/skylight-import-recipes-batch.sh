#!/usr/bin/env bash
# Bulk-import bb-pdc20 (or any) recipe markdown files via Skylight API.
# Usage: skylight-import-recipes-batch.sh [--category Snack] [--limit N] [--dry-run] <recipe-dir>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMPORT="${SCRIPT_DIR}/skylight-import-recipes.sh"
CATEGORY="Snack"
LIMIT=0
DRY=0
DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --category) CATEGORY="$2"; shift 2 ;;
    --limit) LIMIT="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    -h|--help)
      echo "Usage: $0 [--category Snack] [--limit N] [--dry-run] <recipe-root-dir>"
      exit 0
      ;;
    *) DIR="$1"; shift ;;
  esac
done

[[ -n "$DIR" && -d "$DIR" ]] || { echo "Missing recipe directory" >&2; exit 1; }

mapfile -t FILES < <(find "$DIR" -path '*/import-cards/*' -prune -o -name '*.md' -type f -print | grep -E '/[0-9]{2}-' | sort)
count=0
for f in "${FILES[@]}"; do
  [[ "$(basename "$f")" == _section.md ]] && continue
  [[ "$f" == *"/import-cards/"* ]] && continue
  if (( LIMIT > 0 && count >= LIMIT )); then
    echo "Stopped at limit $LIMIT"
    break
  fi
  if (( DRY )); then
    echo "DRY: $f"
  else
    echo "Importing: $f"
    bash "$IMPORT" "$f" --category "$CATEGORY"
    sleep 1
  fi
  count=$((count + 1))
done
echo "Batch complete: $count recipe(s)"
