#!/usr/bin/env bash
# Auto-reset OpenClaw sessions stuck in context-overflow / livenessState=blocked.
# Intended for alfred-cron or openclaw-session-prune.timer hook (every 4h).
#
# Usage: openclaw-session-overflow-guard.sh [--dry-run]
set -euo pipefail

DRY=false
[[ "${1:-}" == "--dry-run" ]] && DRY=true

WINDOW="${OVERFLOW_GUARD_WINDOW:-6 hours ago}"
STALE_WINDOW="${OVERFLOW_STALE_WINDOW:-2 hours ago}"
RESET_SCRIPT="${OPENCLAW_RESET_SESSION_SCRIPT:-$HOME/.openclaw/scripts/reset-openclaw-session.sh}"
TALK_POST="${OPENCLAW_DIR:-$HOME/.openclaw}/scripts/talk-post.sh"
OVERFLOW_NOTICE="${OVERFLOW_GUARD_NOTICE:-Session refreshed — try again.}"

mapfile -t KEYS < <(
  {
    journalctl --user -u openclaw-gateway --since "$WINDOW" --no-pager 2>/dev/null \
      | grep -E 'livenessState=blocked|suggestedAction=reset_or_new' \
      | grep -oE 'sessionKey=[^ ]+' \
      | sed 's/sessionKey=//'
    journalctl --user -u openclaw-gateway --since "$STALE_WINDOW" --no-pager 2>/dev/null \
      | grep -E 'context-overflow-precheck.*messages=0.*overflowTokens=[1-9]' \
      | grep -oE 'sessionKey=[^ ]+' \
      | sed 's/sessionKey=//'
  } | sort -u
)

if ((${#KEYS[@]} == 0)); then
  echo "OVERFLOW_GUARD ok (no blocked sessions in window)"
  exit 0
fi

echo "OVERFLOW_GUARD blocked session keys (${#KEYS[@]}): ${KEYS[*]}"

if $DRY; then
  exit 0
fi

if [[ ! -x "$RESET_SCRIPT" ]]; then
  echo "OVERFLOW_GUARD missing reset script: $RESET_SCRIPT" >&2
  exit 1
fi

"$RESET_SCRIPT" "${KEYS[@]}"

for key in "${KEYS[@]}"; do
  if [[ "$key" =~ nextcloud-talk:group:([a-z0-9]+) ]]; then
    room="${BASH_REMATCH[1]}"
    if [[ -x "$TALK_POST" ]]; then
      bash "$TALK_POST" "$OVERFLOW_NOTICE" "$room" || true
      echo "OVERFLOW_GUARD notice posted room=${room}"
    fi
  fi
done
