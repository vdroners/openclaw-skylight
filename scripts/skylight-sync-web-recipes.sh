#!/usr/bin/env bash
# Sync web-adapted BB-PDC20 recipes (section 16) to Skylight and refresh BB manifest bodies.
# Usage: skylight-sync-web-recipes.sh [--dry-run] [--import-only] [--curate-only]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/load-skylight-env.sh"

SNAPSHOT="${BB_SNAPSHOT:-${HOME}/.cursor/snapshots/skylight-bb-pdc20-recipes}"
WEB_DIR="${SNAPSHOT}/16-web-adaptations"
DRY=0
IMPORT_ONLY=0
CURATE_ONLY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY=1; shift ;;
    --import-only) IMPORT_ONLY=1; shift ;;
    --curate-only) CURATE_ONLY=1; shift ;;
    -h|--help)
      cat <<EOF
Usage: $0 [--dry-run] [--import-only] [--curate-only]

Imports markdown from:
  \${BB_SNAPSHOT}/16-web-adaptations/
(default: ~/.cursor/snapshots/skylight-bb-pdc20-recipes/16-web-adaptations/)

Then runs skylight-curate-recipes.py --bb-only to push Sidekick bodies for all
manifest recipes (factory sections 01–15 + web section 16).

Environment:
  BB_SNAPSHOT  Override recipe library root
EOF
      exit 0
      ;;
    *) echo "Unknown: $1" >&2; exit 1 ;;
  esac
done

[[ -d "$WEB_DIR" ]] || { echo "Missing web adaptations dir: $WEB_DIR" >&2; exit 1; }

if (( CURATE_ONLY == 0 )); then
  echo "=== Import web adaptations from $WEB_DIR ==="
  args=()
  (( DRY )) && args+=(--dry-run)
  bash "${SCRIPT_DIR}/skylight-import-recipes-batch.sh" "${args[@]}" "$WEB_DIR"
fi

if (( IMPORT_ONLY == 0 )); then
  echo "=== Curate BB manifest recipes on Skylight ==="
  curate_args=(--bb-only)
  (( DRY )) && curate_args+=(--dry-run)
  python3 "${SCRIPT_DIR}/skylight-curate-recipes.py" "${curate_args[@]}"
fi

echo "=== skylight-sync-web-recipes complete ==="
