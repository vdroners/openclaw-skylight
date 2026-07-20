#!/usr/bin/env bash
# flight-triage-dispatch.sh — parse @alfred|@openclaw YES|NO triage-<id>
# Exit: 0=applied, 1=matched but unknown/failed, 2=not a flight-triage command
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MSG="${1:-}"
DRY_RUN="${FLIGHT_TRIAGE_DISPATCH_DRY_RUN:-0}"

AGENT_RAW="${OPENCLAW_AGENT_MENTION:-@alfred}"
AGENT="${AGENT_RAW#@}"
# Accept primary agent + legacy openclaw
AGENTS_RE="(${AGENT}|openclaw|alfred)"

ACTION=""
PID=""

# Normalize rich mention chips to @agent for matching
NORM=$(printf '%s' "$MSG" | python3 -c "
import re, sys
t = sys.stdin.read()
t = re.sub(r'\{mention-user\d+\}', '@${AGENT}', t, flags=re.I)
print(re.sub(r'\s+', ' ', t).strip())
")

if echo "$NORM" | grep -qiE "@${AGENTS_RE}[[:space:]]+YES[[:space:]]+triage-"; then
	ACTION=yes
	PID=$(echo "$NORM" | grep -oiE 'triage-[0-9]+' | head -1)
elif echo "$NORM" | grep -qiE "@${AGENTS_RE}[[:space:]]+NO[[:space:]]+triage-"; then
	ACTION=no
	PID=$(echo "$NORM" | grep -oiE 'triage-[0-9]+' | head -1)
elif echo "$NORM" | grep -qiE '^YES[[:space:]]+triage-' && echo "$MSG" | grep -qiE '\{mention-user[0-9]+\}'; then
	# Chip-only mention already expanded above; keep fallback
	ACTION=yes
	PID=$(echo "$NORM" | grep -oiE 'triage-[0-9]+' | head -1)
elif echo "$NORM" | grep -qiE '^NO[[:space:]]+triage-' && echo "$MSG" | grep -qiE '\{mention-user[0-9]+\}'; then
	ACTION=no
	PID=$(echo "$NORM" | grep -oiE 'triage-[0-9]+' | head -1)
else
	exit 2
fi

STATE_DIR="${HOME}/.openclaw/state/flight-triage-proposals"
STATE="${STATE_DIR}/batch-latest.json"
mkdir -p "$STATE_DIR"

if [[ ! -f "$STATE" ]]; then
	echo "{\"action\":\"${ACTION}\",\"proposal_id\":\"${PID}\",\"error\":\"no_batch_state\"}"
	exit 1
fi

# Resolve proposal
FOUND=$(python3 - "$STATE" "$PID" <<'PY'
import json, sys
from pathlib import Path
state = json.loads(Path(sys.argv[1]).read_text())
pid = sys.argv[2]
props = state.get("proposals") or []
for p in props:
    if str(p.get("id")) == pid:
        print(json.dumps(p))
        raise SystemExit(0)
print("")
PY
)

if [[ -z "$FOUND" ]]; then
	echo "{\"action\":\"${ACTION}\",\"proposal_id\":\"${PID}\",\"error\":\"unknown_id\"}"
	exit 1
fi

BIN_PATH=$(echo "$FOUND" | jq -r '.bin_path // empty')
LABEL=$(echo "$FOUND" | jq -r '.run_label // empty')
if [[ -z "$LABEL" ]]; then
	LABEL="talk_${PID}_$(date +%Y%m%d)"
fi

if [[ "$ACTION" == "no" ]]; then
	python3 - "$STATE" "$PID" <<'PY'
import json, sys
from pathlib import Path
path = Path(sys.argv[1])
pid = sys.argv[2]
state = json.loads(path.read_text())
for p in state.get("proposals") or []:
    if str(p.get("id")) == pid:
        p["state"] = "rejected"
path.write_text(json.dumps(state, indent=2))
PY
	echo "{\"action\":\"no\",\"proposal_id\":\"${PID}\",\"state\":\"rejected\"}"
	exit 0
fi

# YES → intake
if [[ -z "$BIN_PATH" ]]; then
	echo "{\"action\":\"yes\",\"proposal_id\":\"${PID}\",\"error\":\"missing_bin_path\"}"
	exit 1
fi

if [[ "$DRY_RUN" == "1" ]]; then
	echo "{\"action\":\"yes\",\"proposal_id\":\"${PID}\",\"bin_path\":\"${BIN_PATH}\",\"run_label\":\"${LABEL}\",\"dry_run\":true}"
	exit 0
fi

INTAKE="${SCRIPT_DIR}/flight-triage-intake.sh"
if [[ ! -x "$INTAKE" ]]; then
	echo "{\"action\":\"yes\",\"proposal_id\":\"${PID}\",\"error\":\"intake_missing\"}"
	exit 1
fi

set +e
out=$("$INTAKE" "$BIN_PATH" "$LABEL" "Alfred Talk YES ${PID}" 2>&1)
rc=$?
set -e

if [[ $rc -ne 0 ]]; then
	echo "{\"action\":\"yes\",\"proposal_id\":\"${PID}\",\"error\":\"intake_failed\",\"detail\":$(jq -Rn --arg s "$out" '$s')}"
	exit 1
fi

python3 - "$STATE" "$PID" <<'PY'
import json, sys
from pathlib import Path
path = Path(sys.argv[1])
pid = sys.argv[2]
state = json.loads(path.read_text())
for p in state.get("proposals") or []:
    if str(p.get("id")) == pid:
        p["state"] = "accepted"
path.write_text(json.dumps(state, indent=2))
PY

echo "{\"action\":\"yes\",\"proposal_id\":\"${PID}\",\"bin_path\":\"${BIN_PATH}\",\"run_label\":\"${LABEL}\",\"intake_ok\":true}"
exit 0
