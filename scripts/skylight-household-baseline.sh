#!/usr/bin/env bash
# Phase 0 baseline — metrics + Family Hub summary (gate B0).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOM="${SKYLIGHT_FAMILY_TALK_ROOM:-}"

bash "${SCRIPT_DIR}/skylight-auth-refresh.sh" >/dev/null 2>&1 || true
bash "${SCRIPT_DIR}/skylight-household-deep-audit.sh" --metrics-only

STAMP=$(date +%F)
BASELINE="${OPENCLAW_DIR:-$HOME/.openclaw}/logs/household-baseline-${STAMP}.json"

BODY="$(python3 - "$BASELINE" <<'PY'
import json, sys
from pathlib import Path
d = json.loads(Path(sys.argv[1]).read_text())
m = d.get("metrics", {})
lines = [
    "Household audit — baseline snapshot",
    "",
    f"Chores missing start time: {m.get('chores_missing_start_time', '?')} / {m.get('chores_series_count', '?')}",
    f"Calendar 60d events: {m.get('calendar_events_60d', '?')}",
    f"Missing location: {m.get('calendar_missing_location', '?')}",
    f"Missing description: {m.get('calendar_missing_description', '?')}",
    f"Vague titles (ask): {m.get('ask_operator_count', '?')}",
    f"Proposed chore time fixes: {m.get('enrich_chores_count', '?')}",
    f"Proposed calendar enrichments: {m.get('enrich_calendar_count', '?')}",
    "",
    "Proposals coming next. Reply @openclaw YES <proposal-id> when cards post.",
]
print("\n".join(lines))
PY
)"

bash "${SCRIPT_DIR}/talk-post.sh" "$BODY" "$ROOM"
echo "Gate B0: baseline posted"
