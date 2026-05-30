#!/usr/bin/env bash
# flight-triage-propose.sh — post Talk card for triage YES/NO.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_PATH="${1:-}"
PID="triage-$(date +%s | tail -c 6)"

if [[ -z "$BIN_PATH" ]]; then
	echo "Usage: $0 /path/to/flight.BIN" >&2
	exit 2
fi

STATE_DIR="${HOME}/.openclaw/state/flight-triage-proposals"
mkdir -p "$STATE_DIR"
cat > "${STATE_DIR}/batch-latest.json" <<EOF
{"version":1,"proposals":[{"id":"${PID}","bin_path":"${BIN_PATH}","state":"pending"}]}
EOF

MSG="Flight log ready for triage: ${BIN_PATH}
Reply: @alfred YES ${PID} | NO ${PID}"

if [[ -x "${SCRIPT_DIR}/talk-post.sh" ]]; then
	"${SCRIPT_DIR}/talk-post.sh" "${FLIGHT_TRIAGE_TALK_ROOM:-}" "$MSG" || echo "$MSG"
else
	echo "$MSG"
fi

echo "proposal_id=${PID}"
