#!/usr/bin/env bash
# Post a one-time Family Hub reminder for pending household proposals (no LLM).
# Usage: household-proposal-nudge.sh [--dry-run] [--limit N]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/load-skylight-env.sh"

BATCH="${OPENCLAW_DIR:-$HOME/.openclaw}/state/household-proposals/batch-latest.json"
ROOM="${SKYLIGHT_FAMILY_TALK_ROOM:?set SKYLIGHT_FAMILY_TALK_ROOM}"
LIMIT=3
DRY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY=1; shift ;;
    --limit) LIMIT="${2:?}"; shift 2 ;;
    *) echo "usage: $0 [--dry-run] [--limit N]" >&2; exit 2 ;;
  esac
done

[[ -f "$BATCH" ]] || { echo "HOME-NUDGE skip: no batch"; exit 0; }

read -r pending ids <<<"$(python3 - "$BATCH" "$LIMIT" <<'PY'
import json, sys
from pathlib import Path
b = json.loads(Path(sys.argv[1]).read_text())
limit = int(sys.argv[2])
pending = [p for p in b.get("proposals", []) if p.get("status") == "pending"]
ids = [p["id"] for p in pending[:limit]]
print(len(pending), ", ".join(ids))
PY
)"

if [[ "${pending:-0}" -le 5 ]]; then
  echo "HOME-NUDGE skip: pending=${pending:-0} (threshold >5)"
  exit 0
fi

MENTION="${OPENCLAW_AGENT_MENTION:-@openclaw}"
MSG="Household audit: ${pending} cards pending review. Examples: ${ids}. Reply ${MENTION} YES <id> or ${MENTION} NO <id>."

if [[ "$DRY" -eq 1 ]]; then
  echo "HOME-NUDGE dry-run: $MSG"
  exit 0
fi

bash "${SCRIPT_DIR}/talk-post.sh" "$MSG" "$ROOM"
echo "HOME-NUDGE posted room=${ROOM} pending=${pending}"
