#!/usr/bin/env bash
# Daily stack health summary posted to ops Talk (shell-only, no LLM).
# Posts summary even when verify-alfred-stack fails (prefix FAIL).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOM="${HEALTH_REPORT_TALK_ROOM:-jf7zijqp}"

VERIFY_RC=0
VERIFY_OUT="$(bash "${SCRIPT_DIR}/verify-alfred-stack.sh" 2>&1)" || VERIFY_RC=$?

SUMMARY="$(printf '%s\n' "$VERIFY_OUT" | tail -20 | tr '\n' ' ' | sed 's/  */ /g' | cut -c1-750)"
if [[ "$VERIFY_RC" -ne 0 ]]; then
  SUMMARY="[health] Alfred health FAIL (rc=${VERIFY_RC}): ${SUMMARY}"
else
  SUMMARY="[health] ${SUMMARY}"
fi

bash "${SCRIPT_DIR}/talk-post.sh" "$SUMMARY" "$ROOM"
echo "HEALTH_REPORT_POSTED room=${ROOM} verify_rc=${VERIFY_RC}"
