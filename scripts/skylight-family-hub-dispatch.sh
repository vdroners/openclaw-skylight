#!/usr/bin/env bash
# Route Family Hub @alfred YES|NO|EDIT proposal replies to the reply handler.
# Usage: skylight-family-hub-dispatch.sh "message text"
# Exit 0 = handled, 2 = not a proposal command (caller may use LLM), 1 = error
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MSG="${1:-}"
[[ -n "$MSG" ]] || { echo "usage: $0 '<message>'" >&2; exit 1; }

if ! printf '%s' "$MSG" | grep -qiE '@alfred[[:space:]]+(YES|NO|EDIT)[[:space:]]+(enrich-calendar-|enrich-chore-|ask-)[0-9]+'; then
  echo "dispatch: not a household proposal command"
  exit 2
fi

bash "${SCRIPT_DIR}/skylight-household-reply-handler.sh" "$MSG"
echo "Gate C1b: dispatch handled proposal command"
exit 0
