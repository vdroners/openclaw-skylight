#!/usr/bin/env bash
# Fill blank Skylight chore times, routine flags, and reward points.
# Usage: skylight-chores-fill-blanks.sh [--dry-run] [--person Dan]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/load-skylight-env.sh"
export OPENCLAW_DIR="${OPENCLAW_DIR:-$HOME/.openclaw}"
export HOUSEHOLD_MODEL_JSON="${HOUSEHOLD_MODEL_JSON:-$OPENCLAW_DIR/config/household-model.json}"

exec python3 "${SCRIPT_DIR}/skylight-chores-fill-blanks.py" "$@"
