#!/usr/bin/env bash
# Find and remove duplicate Skylight recipes by title.
# Usage: skylight-recipe-dedupe.sh [--dry-run]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/load-skylight-env.sh"

DRY=0
[[ "${1:-}" == "--dry-run" ]] && DRY=1

export SCRIPT_DIR DRY SKYLIGHT_FRAME_ID SKYLIGHT_AUTHORIZATION SKYLIGHT_API_URL

python3 "${SCRIPT_DIR}/skylight-curate-recipes.py" --dedupe-only $([[ "$DRY" -eq 1 ]] && echo --dry-run)
