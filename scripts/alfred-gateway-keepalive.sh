#!/usr/bin/env bash
# Lightweight gateway keepalive — enable+start if health check fails.
# Intended for systemd user timer every 5 minutes.
set -euo pipefail

GATEWAY_HEALTH_URL="${OPENCLAW_GATEWAY_HEALTH_URL:-http://127.0.0.1:18789/health}"

health_ok() {
  systemctl --user is-active openclaw-gateway >/dev/null 2>&1 \
    && [[ "$(curl -sS -o /dev/null -w '%{http_code}' --max-time 8 "$GATEWAY_HEALTH_URL" 2>/dev/null || echo 000)" == "200" ]]
}

talk_plugin_ok() {
  local port="${OPENCLAW_TALK_PLUGIN_PORT:-8787}"
  ss -tln 2>/dev/null | grep -q ":${port} "
}

if health_ok && talk_plugin_ok; then
  echo "GATEWAY_KEEPALIVE ok"
  exit 0
fi

if ! health_ok; then
  systemctl --user enable openclaw-gateway >/dev/null 2>&1 || true
  systemctl --user start openclaw-gateway >/dev/null 2>&1 || true
fi

if ! talk_plugin_ok; then
  if journalctl --user -u openclaw-gateway --since "24 hours ago" --no-pager 2>/dev/null \
    | grep -q "plugin not installed: nextcloud-talk"; then
    openclaw plugins install @openclaw/nextcloud-talk >/dev/null 2>&1 || true
  fi
  systemctl --user restart openclaw-gateway >/dev/null 2>&1 || true
fi

for _ in 1 2 3 4 5 6; do
  sleep 5
  if health_ok && talk_plugin_ok; then
    echo "GATEWAY_KEEPALIVE recovered"
    exit 0
  fi
done

echo "GATEWAY_KEEPALIVE failed" >&2
exit 1
