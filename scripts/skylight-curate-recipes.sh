#!/usr/bin/env bash
# Curate all Skylight recipes: clean bb-pdc20 Sidekick bodies + polish household recipes.
# Usage: skylight-curate-recipes.sh [--dry-run] [--bb-only] [--household-only]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/load-skylight-env.sh"

exec python3 "${SCRIPT_DIR}/skylight-curate-recipes.py" "$@"
