#!/usr/bin/env bash
# flight-triage-propose.sh — post Talk card for triage YES/NO.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/load-agent-env.sh" 2>/dev/null || true

BIN_PATH="${1:-}"
[[ -n "$BIN_PATH" ]] || { echo "Usage: $0 /path/to/flight.BIN" >&2; exit 2; }

MENTION="${OPENCLAW_AGENT_MENTION:-@alfred}"
PID="triage-$(date +%s | tail -c 6)"
STATE_DIR="${HOME}/.openclaw/state/flight-triage-proposals"
mkdir -p "$STATE_DIR"
cat > "${STATE_DIR}/batch-latest.json" <<EOF
{"version":1,"proposals":[{"id":"${PID}","bin_path":"${BIN_PATH}","status":"pending","state":"pending"}]}
EOF

MSG="Flight log ready for triage: ${BIN_PATH}
Reply: ${MENTION} YES ${PID} | ${MENTION} NO ${PID}"

ROOM="${FLIGHT_TRIAGE_TALK_ROOM:-${SKYLIGHT_OPS_TALK_ROOM:-}}"
if [[ -x "${SCRIPT_DIR}/talk-post.sh" && -n "$ROOM" ]]; then
  bash "${SCRIPT_DIR}/talk-post.sh" "$MSG" "$ROOM" || echo "$MSG"
else
  echo "$MSG"
fi

echo "proposal_id=${PID}"
