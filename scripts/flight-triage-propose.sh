#!/usr/bin/env bash
# flight-triage-propose.sh — post Talk card for triage YES/NO.
# Usage: flight-triage-propose.sh [/path/to/flight.BIN]
#        flight-triage-propose.sh --dry-run /path/to/flight.BIN
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/load-agent-env.sh" 2>/dev/null || true

DRY=0
if [[ "${1:-}" == "--dry-run" ]]; then
	DRY=1
	shift
fi

BIN_PATH="${1:-}"
PID="triage-$(date +%s | tail -c 6)"
MENTION="${OPENCLAW_AGENT_MENTION:-@alfred}"
ROOM="${FLIGHT_TRIAGE_TALK_ROOM:-${SKYLIGHT_OPS_TALK_ROOM:-}}"

if [[ -z "$BIN_PATH" ]]; then
	echo "Usage: $0 [--dry-run] /path/to/flight.BIN" >&2
	exit 2
fi

STATE_DIR="${HOME}/.openclaw/state/flight-triage-proposals"
mkdir -p "$STATE_DIR"
cat > "${STATE_DIR}/batch-latest.json" <<EOF
{"version":1,"proposals":[{"id":"${PID}","bin_path":"${BIN_PATH}","state":"pending"}]}
EOF

MSG="Flight log ready for triage: ${BIN_PATH}
Reply: ${MENTION} YES ${PID} | ${MENTION} NO ${PID}"

if [[ "$DRY" -eq 1 ]]; then
	echo "$MSG"
	echo "proposal_id=${PID}"
	exit 0
fi

if [[ -x "${SCRIPT_DIR}/talk-post.sh" && -n "$ROOM" ]]; then
	# talk-post.sh "message" [room]
	"${SCRIPT_DIR}/talk-post.sh" "$MSG" "$ROOM" || echo "$MSG"
else
	echo "$MSG"
fi

echo "proposal_id=${PID}"
