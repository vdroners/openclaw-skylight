#!/usr/bin/env bash
# Tallies failure signals in the last WINDOW (default 4h) of openclaw-gateway journal
# plus live gateway liveness (active, enabled, /health). Emits JSON on stdout.
#
# Usage: self-watchdog.sh [WINDOW="4 hours ago"]
# Exit 0 always (cron reads JSON, not exit code).
set -uo pipefail

WINDOW="${1:-4 hours ago}"
GATEWAY_HEALTH_URL="${OPENCLAW_GATEWAY_HEALTH_URL:-http://127.0.0.1:18789/health}"

OVERFLOW_THRESHOLD="${OVERFLOW_THRESHOLD:-3}"
TIMEOUT_THRESHOLD="${TIMEOUT_THRESHOLD:-5}"
MSGFAIL_THRESHOLD="${MSGFAIL_THRESHOLD:-5}"
AUTH401_THRESHOLD="${AUTH401_THRESHOLD:-5}"
RESTARTS_THRESHOLD="${RESTARTS_THRESHOLD:-2}"
DELIVERY_QUEUE_THRESHOLD="${DELIVERY_QUEUE_THRESHOLD:-50}"
DELIVERY_QUEUE_DIR="${DELIVERY_QUEUE_DIR:-$HOME/.openclaw/delivery-queue}"

LOG=$(journalctl --user -u openclaw-gateway --since "$WINDOW" --no-pager 2>/dev/null || true)

count() {
  local pattern="$1"
  if [[ -z "$LOG" ]]; then echo 0; return; fi
  printf '%s\n' "$LOG" | grep -ciE "$pattern" || true
}

OVERFLOW=$(count "overflow|auto-compact")
TIMEOUTS=$(count "embedded run timeout|request timed out|FailoverError")
MSGFAIL=$(count "message failed|message required|Unknown target")
AUTH401=$(count "Unauthorized|HTTP 401|status[^0-9]+401")
RESTARTS=$(count "gateway\\] ready")

DELIVERY_QUEUE=0
if [[ -d "$DELIVERY_QUEUE_DIR" ]]; then
  DELIVERY_QUEUE=$(find "$DELIVERY_QUEUE_DIR" -maxdepth 1 -name '*.json' 2>/dev/null | wc -l)
fi

GATEWAY_ENABLED=false
GATEWAY_ACTIVE=false
GATEWAY_HEALTH="000"
if systemctl --user is-enabled openclaw-gateway >/dev/null 2>&1; then
  GATEWAY_ENABLED=true
fi
if systemctl --user is-active openclaw-gateway >/dev/null 2>&1; then
  GATEWAY_ACTIVE=true
fi
GATEWAY_HEALTH=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 "$GATEWAY_HEALTH_URL" 2>/dev/null || echo 000)

TALK_PLUGIN_PORT="${OPENCLAW_TALK_PLUGIN_PORT:-8787}"
TALK_PLUGIN_HEALTH="000"
if command -v ss >/dev/null 2>&1; then
  if ss -tln 2>/dev/null | grep -q ":${TALK_PLUGIN_PORT} "; then
    TALK_PLUGIN_HEALTH="listening"
  fi
elif command -v netstat >/dev/null 2>&1; then
  if netstat -tln 2>/dev/null | grep -q ":${TALK_PLUGIN_PORT} "; then
    TALK_PLUGIN_HEALTH="listening"
  fi
fi

PLUGIN_MISSING=$(count "plugin not installed: nextcloud-talk")

BLOCKED_SESSIONS=0
if [[ -n "$LOG" ]]; then
  BLOCKED_SESSIONS=$(printf '%s\n' "$LOG" \
    | grep -E 'livenessState=blocked|suggestedAction=reset_or_new' \
    | grep -oE 'sessionKey=[^ ]+' \
    | sort -u \
    | wc -l)
fi

ALERTS=()
[[ "$GATEWAY_ENABLED" != "true" ]] && ALERTS+=("gateway_disabled")
[[ "$GATEWAY_ACTIVE" != "true" ]] && ALERTS+=("gateway_inactive")
[[ "$GATEWAY_HEALTH" != "200" ]] && ALERTS+=("gateway_health=${GATEWAY_HEALTH}")
[[ "$TALK_PLUGIN_HEALTH" != "listening" ]] && ALERTS+=("talk_plugin_port_${TALK_PLUGIN_PORT}_down")
[[ $PLUGIN_MISSING -gt 0 ]] && ALERTS+=("nextcloud_talk_plugin_missing")
if [[ $BLOCKED_SESSIONS -gt 0 ]]; then
  ALERTS+=("blocked_sessions=${BLOCKED_SESSIONS}")
fi
[[ $TIMEOUTS -gt $TIMEOUT_THRESHOLD ]] && ALERTS+=("timeouts=$TIMEOUTS (threshold $TIMEOUT_THRESHOLD)")
[[ $MSGFAIL -gt $MSGFAIL_THRESHOLD ]] && ALERTS+=("msgFail=$MSGFAIL (threshold $MSGFAIL_THRESHOLD)")
[[ $AUTH401 -gt $AUTH401_THRESHOLD ]] && ALERTS+=("auth401=$AUTH401 (threshold $AUTH401_THRESHOLD)")
[[ $RESTARTS -gt $RESTARTS_THRESHOLD ]] && ALERTS+=("restarts=$RESTARTS (threshold $RESTARTS_THRESHOLD)")
[[ $DELIVERY_QUEUE -gt $DELIVERY_QUEUE_THRESHOLD ]] && ALERTS+=("delivery_queue=$DELIVERY_QUEUE (threshold $DELIVERY_QUEUE_THRESHOLD)")

if [[ ${#ALERTS[@]} -eq 0 ]]; then
  OK=true
else
  OK=false
fi

ALERTS_JSON=$(printf '%s\n' "${ALERTS[@]-}" | python3 -c '
import sys, json
vals = [l for l in sys.stdin.read().splitlines() if l]
print(json.dumps(vals))
')

printf '{"ok":%s,"window":"%s","gateway_enabled":%s,"gateway_active":%s,"gateway_health":"%s","talk_plugin_port":%d,"talk_plugin_health":"%s","plugin_missing":%d,"overflow":%d,"blocked_sessions":%d,"timeouts":%d,"msgFail":%d,"auth401":%d,"restarts":%d,"delivery_queue":%d,"alerts":%s}\n' \
  "$OK" "$WINDOW" "$GATEWAY_ENABLED" "$GATEWAY_ACTIVE" "$GATEWAY_HEALTH" \
  "$TALK_PLUGIN_PORT" "$TALK_PLUGIN_HEALTH" "$PLUGIN_MISSING" \
  "$OVERFLOW" "$BLOCKED_SESSIONS" "$TIMEOUTS" "$MSGFAIL" "$AUTH401" "$RESTARTS" "$DELIVERY_QUEUE" "$ALERTS_JSON"

exit 0
