#!/usr/bin/env bash
# Post a Family Hub nudge when many proposals are pending and none applied.
# Usage: skylight-household-nudge.sh [--dry-run]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/load-skylight-env.sh"

OPENCLAW="${OPENCLAW_DIR:-$HOME/.openclaw}"
BATCH="${OPENCLAW}/state/household-proposals/batch-latest.json"
ROOM="${SKYLIGHT_FAMILY_TALK_ROOM:?set SKYLIGHT_FAMILY_TALK_ROOM}"
DRY=0
PENDING_MIN="${HOME_NUDGE_PENDING_MIN:-10}"

[[ "${1:-}" == "--dry-run" ]] && DRY=1

[[ -f "$BATCH" ]] || { echo "HOME_NUDGE skip (no batch-latest.json)"; exit 0; }

read -r pending applied <<<"$(python3 - "$BATCH" <<'PY'
import json, sys
from collections import Counter
b = json.load(open(sys.argv[1]))
c = Counter(p.get("status") for p in b.get("proposals", []))
print(c.get("pending", 0), c.get("applied", 0))
PY
)"

if [[ "$pending" -lt "$PENDING_MIN" ]] || [[ "$applied" -gt 0 ]]; then
  echo "HOME_NUDGE skip pending=${pending} applied=${applied}"
  exit 0
fi

MSG="Household proposals: ${pending} pending, ${applied} applied. Review cards in this room and reply @alfred YES or NO with the proposal id."
if [[ "$DRY" -eq 1 ]]; then
  echo "HOME_NUDGE dry-run: $MSG"
  exit 0
fi

bash "${SCRIPT_DIR}/talk-post.sh" "$MSG" "$ROOM"
echo "HOME_NUDGE posted room=${ROOM} pending=${pending}"
