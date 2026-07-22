#!/usr/bin/env bash
# Self-watchdog — auto-restart gateway when down; post Talk alert if still unhealthy.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOM="${WATCHDOG_TALK_ROOM:-jf7zijqp}"
GATEWAY_HEALTH_URL="${OPENCLAW_GATEWAY_HEALTH_URL:-http://127.0.0.1:18789/health}"

gateway_healthy() {
  systemctl --user is-active openclaw-gateway >/dev/null 2>&1 \
    && [[ "$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 "$GATEWAY_HEALTH_URL" 2>/dev/null || echo 000)" == "200" ]]
}

if ! gateway_healthy; then
  systemctl --user enable openclaw-gateway >/dev/null 2>&1 || true
  systemctl --user start openclaw-gateway >/dev/null 2>&1 || true
  for _ in 1 2 3 4 5 6; do
    sleep 5
    gateway_healthy && break
  done
fi

talk_port="${OPENCLAW_TALK_PLUGIN_PORT:-8787}"
if ! ss -tln 2>/dev/null | grep -q ":${talk_port} "; then
  systemctl --user restart openclaw-gateway >/dev/null 2>&1 || true
  for _ in 1 2 3 4 5 6; do
    sleep 5
    ss -tln 2>/dev/null | grep -q ":${talk_port} " && break
  done
fi

JSON="$(bash "${SCRIPT_DIR}/self-watchdog.sh")"
OK="$(printf '%s' "$JSON" | python3 -c 'import sys,json; print("true" if json.loads(sys.stdin.read()).get("ok") else "false")')"

if [[ "$OK" == "true" ]]; then
  echo "watchdog OK"
  exit 0
fi

MSG="$(printf '%s' "$JSON" | python3 -c '
import json, sys
d = json.loads(sys.stdin.read())
window = d.get("window", "?")
alerts = d.get("alerts") or []
text = " | ".join(alerts) if alerts else "threshold breach"
print(f"[watchdog] Alfred watchdog ALERT ({window}): {text}. Investigate gateway journal.")
')"

bash "${SCRIPT_DIR}/talk-post.sh" "$MSG" "$ROOM"
echo "watchdog ALERT posted room=${ROOM}"
