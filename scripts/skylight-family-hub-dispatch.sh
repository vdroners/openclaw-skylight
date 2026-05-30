#!/usr/bin/env bash
# Route Family Hub @openclaw YES|NO|EDIT proposal replies to the reply handler.
# Usage: skylight-family-hub-dispatch.sh [--dry-run] "message text"
# Exit 0 = handled, 2 = not a proposal command, 1 = error
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/load-skylight-env.sh"

DRY=0
MSG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY=1; shift ;;
    *) MSG="$1"; shift ;;
  esac
done

[[ -n "$MSG" ]] || { echo "usage: $0 [--dry-run] '<message>'" >&2; exit 1; }

AGENT="${OPENCLAW_AGENT_NAME:-openclaw}"
if ! printf '%s' "$MSG" | grep -qiE "@${AGENT}[[:space:]]+(YES|NO|EDIT)[[:space:]]+(enrich-calendar-|enrich-chore-|ask-)[0-9]+"; then
  echo "dispatch: not a household proposal command"
  exit 2
fi

ARGS=()
[[ "$DRY" -eq 1 ]] && ARGS+=(--dry-run)
bash "${SCRIPT_DIR}/skylight-household-reply-handler.sh" "${ARGS[@]}" "$MSG"
echo "Gate C1b: dispatch handled proposal command$([[ $DRY -eq 1 ]] && echo ' (dry-run)')"
exit 0
