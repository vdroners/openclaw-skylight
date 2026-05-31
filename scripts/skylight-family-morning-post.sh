#!/usr/bin/env bash
# Family morning digest — auth refresh, generate, post to Family Hub.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOM="${SKYLIGHT_FAMILY_TALK_ROOM:-}"

bash "${SCRIPT_DIR}/skylight-auth-refresh.sh" >/dev/null 2>&1 || true
OUT="$(bash "${SCRIPT_DIR}/skylight-family-morning.sh")"
if [[ "${SUBARU_MORNING_BRIEF:-0}" == "1" && -x "${SCRIPT_DIR}/subaru-morning-line.sh" ]]; then
  SUBARU_LINE="$(bash "${SCRIPT_DIR}/subaru-morning-line.sh" 2>/dev/null || true)"
  if [[ -n "$SUBARU_LINE" ]]; then
    OUT="${OUT}"$'\n'"${SUBARU_LINE}"
  fi
fi
bash "${SCRIPT_DIR}/talk-post.sh" "$OUT" "$ROOM"
echo "SKYLIGHT_FAMILY_BRIEF_POSTED room=${ROOM}"
