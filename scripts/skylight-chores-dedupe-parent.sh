#!/usr/bin/env bash
# Consolidate duplicate parent-member chores (configured in household-model.json).
# Usage: skylight-chores-dedupe-parent.sh [--dry-run]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/load-skylight-env.sh"
export OPENCLAW_DIR="${OPENCLAW_DIR:-$HOME/.openclaw}"

exec python3 "${SCRIPT_DIR}/skylight-chores-dedupe-parent.py" "$@"
