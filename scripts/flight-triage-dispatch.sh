#!/usr/bin/env bash
# flight-triage-dispatch.sh — parse @openclaw YES|NO triage-<id>
set -euo pipefail

MSG="${1:-}"
PID=""
ACTION=""

if echo "$MSG" | grep -qiE '@openclaw[[:space:]]+YES[[:space:]]+triage-'; then
	ACTION=yes
	PID=$(echo "$MSG" | grep -oiE 'triage-[0-9]+' | head -1)
elif echo "$MSG" | grep -qiE '@openclaw[[:space:]]+NO[[:space:]]+triage-'; then
	ACTION=no
	PID=$(echo "$MSG" | grep -oiE 'triage-[0-9]+' | head -1)
else
	exit 1
fi

STATE="${HOME}/.openclaw/state/flight-triage-proposals/batch-latest.json"
echo "{\"action\":\"${ACTION}\",\"proposal_id\":\"${PID}\"}"
exit 0
