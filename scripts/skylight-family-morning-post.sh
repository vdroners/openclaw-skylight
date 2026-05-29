#!/usr/bin/env bash
# Family morning digest — auth refresh, generate, post to Family Hub.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOM="${SKYLIGHT_FAMILY_TALK_ROOM:-}"

bash "${SCRIPT_DIR}/skylight-auth-refresh.sh" >/dev/null 2>&1 || true
OUT="$(bash "${SCRIPT_DIR}/skylight-family-morning.sh")"
bash "${SCRIPT_DIR}/talk-post.sh" "$OUT" "$ROOM"
echo "SKYLIGHT_FAMILY_BRIEF_POSTED room=${ROOM}"
