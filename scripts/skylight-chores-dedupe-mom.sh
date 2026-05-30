#!/usr/bin/env bash
# Consolidate Mom's duplicate monthly shelf/piano/knitting chores.
# Usage: skylight-chores-dedupe-mom.sh [--dry-run]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/load-skylight-env.sh"
export OPENCLAW_DIR="${OPENCLAW_DIR:-$HOME/.openclaw}"

exec python3 "${SCRIPT_DIR}/skylight-chores-dedupe-mom.py" "$@"
