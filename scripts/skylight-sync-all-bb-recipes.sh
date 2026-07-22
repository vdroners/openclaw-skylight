#!/usr/bin/env bash
# Bulk-import entire BB-PDC20 snapshot then curate Sidekick bodies.
# Usage: skylight-sync-all-bb-recipes.sh [--dry-run] [--force]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/load-skylight-env.sh"

SNAPSHOT="${BB_SNAPSHOT:-${HOME}/.cursor/snapshots/skylight-bb-pdc20-recipes}"
DRY=0
FORCE=0
IMPORT_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY=1; IMPORT_ARGS+=(--dry-run); shift ;;
    --force) FORCE=1; IMPORT_ARGS+=(--force); shift ;;
    -h|--help)
      echo "Usage: $0 [--dry-run] [--force]"
      exit 0
      ;;
    *) echo "Unknown: $1" >&2; exit 1 ;;
  esac
done

[[ -d "$SNAPSHOT" ]] || { echo "Missing snapshot: $SNAPSHOT" >&2; exit 1; }

echo "=== Import all sections from $SNAPSHOT ==="
for section in "$SNAPSHOT"/[0-9][0-9]-*/; do
  [[ -d "$section" ]] || continue
  name="$(basename "$section")"
  echo "--- Section $name ---"
  bash "${SCRIPT_DIR}/skylight-import-recipes-batch.sh" "${IMPORT_ARGS[@]}" "$section"
done

if (( DRY == 0 )); then
  echo "=== Curate BB manifest on Skylight ==="
  python3 "${SCRIPT_DIR}/skylight-curate-recipes.py" --bb-only
fi

echo "=== skylight-sync-all-bb-recipes complete ==="
