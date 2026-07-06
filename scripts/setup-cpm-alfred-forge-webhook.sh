#!/usr/bin/env bash
# Add alfred-vdroners.ddns.net proxy host for Forge webhook relay (idempotent).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/load-forge-env.sh" 2>/dev/null || true

CPM_CONTAINER="${CPM_CONTAINER:-caddy-proxy-manager-web}"
DB_PATH="/app/data/caddy-proxy-manager.db"
WORK="/tmp/cpm-alfred-forge-$$"
DOMAIN="${FORGE_WEBHOOK_DOMAIN:-alfred-vdroners.ddns.net}"
NAME="Alfred Forge Webhook"
PORT="${FORGE_WEBHOOK_PORT:-8790}"
CPM_UPSTREAM_HOST="${FORGE_CPM_UPSTREAM_HOST:-}"
if [[ -z "$CPM_UPSTREAM_HOST" ]]; then
  if docker ps --format '{{.Names}}' | grep -qx forge-webhook-relay; then
    CPM_UPSTREAM_HOST="forge-webhook-relay"
  else
    CPM_UPSTREAM_HOST="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
  fi
fi
UPSTREAM="[\"http://${CPM_UPSTREAM_HOST}:${PORT}\"]"
DOMAINS="[\"${DOMAIN}\"]"
NOW="$(date -u +%Y-%m-%dT%H:%M:%S.000Z)"

mkdir -p "$WORK"
docker cp "${CPM_CONTAINER}:${DB_PATH}" "$WORK/caddy-proxy-manager.db"

EXISTING=$(docker run --rm -v "$WORK:/data" nouchka/sqlite3 /data/caddy-proxy-manager.db \
  "SELECT id FROM proxy_hosts WHERE domains LIKE '%${DOMAIN}%' LIMIT 1;")

if [[ -n "${EXISTING}" ]]; then
  echo "[cpm] Proxy host for ${DOMAIN} already exists (id=${EXISTING})"
  docker run --rm -v "$WORK:/data" nouchka/sqlite3 /data/caddy-proxy-manager.db \
    "UPDATE proxy_hosts SET upstreams='${UPSTREAM}', updatedAt='${NOW}' WHERE id=${EXISTING};"
  echo "[cpm] Updated upstream -> ${CPM_UPSTREAM_HOST}:${PORT}"
else
  docker run --rm -v "$WORK:/data" nouchka/sqlite3 /data/caddy-proxy-manager.db \
    "INSERT INTO proxy_hosts (name, domains, upstreams, sslForced, hstsEnabled, hstsSubdomains, allowWebsocket, preserveHostHeader, enabled, createdAt, updatedAt, skipHttpsHostnameValidation) VALUES ('${NAME}', '${DOMAINS}', '${UPSTREAM}', 1, 1, 0, 0, 1, 1, '${NOW}', '${NOW}', 1);"
  echo "[cpm] Inserted proxy host for ${DOMAIN} -> 127.0.0.1:${PORT}"
fi

docker cp "$WORK/caddy-proxy-manager.db" "${CPM_CONTAINER}:${DB_PATH}"
rm -rf "$WORK"
docker restart "${CPM_CONTAINER}" >/dev/null
echo "[cpm] Restarted ${CPM_CONTAINER}"
sleep 12
echo "[cpm] Public webhook URL: https://${DOMAIN}/forge-webhook"
echo "[cpm] Ensure No-IP A record ${DOMAIN%%.*} points to this host (same as cloud-vdroners)"
