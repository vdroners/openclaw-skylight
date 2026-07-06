#!/usr/bin/env bash
# Run forge-webhook-relay on the CPM docker network (CPM cannot reach host :8790).
set -euo pipefail

CONTAINER="${FORGE_RELAY_CONTAINER:-forge-webhook-relay}"
NETWORK="${CPM_NETWORK:-caddy-proxy-manager_caddy-network}"
IMAGE="${FORGE_RELAY_IMAGE:-forge-webhook-relay:local}"
OPENCLAW_DIR="${OPENCLAW_DIR:-$HOME/.openclaw}"
PORT="${FORGE_WEBHOOK_PORT:-8790}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

docker network inspect "$NETWORK" >/dev/null 2>&1 || {
  echo "missing docker network $NETWORK" >&2
  exit 1
}

# Build slim image with python + bash + curl for talk-post.sh
if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "[relay-docker] Building $IMAGE ..."
  docker build -t "$IMAGE" -f - "$ROOT" <<'DOCKERFILE'
FROM debian:bookworm-slim
RUN apt-get update -qq && apt-get install -y -qq --no-install-recommends \
    python3 ca-certificates curl bash && rm -rf /var/lib/apt/lists/*
WORKDIR /relay
DOCKERFILE
fi

docker rm -f "$CONTAINER" >/dev/null 2>&1 || true

SKYLIGHT_SCRIPTS="${OPENCLAW_SKYLIGHT_ROOT:-/media/4TB/openclaw-skylight}/scripts"

docker run -d \
  --name "$CONTAINER" \
  --network "$NETWORK" \
  --restart unless-stopped \
  -p "127.0.0.1:${PORT}:${PORT}" \
  -v "${OPENCLAW_DIR}:${OPENCLAW_DIR}:ro" \
  -v "${SKYLIGHT_SCRIPTS}:${OPENCLAW_DIR}/scripts:ro" \
  --env-file "${OPENCLAW_DIR}/.env" \
  -e "OPENCLAW_DIR=${OPENCLAW_DIR}" \
  -e "FORGE_WEBHOOK_BIND=0.0.0.0" \
  -e "FORGE_WEBHOOK_SECRET_FILE=${OPENCLAW_DIR}/.env.d/forge-webhook.secret" \
  "$IMAGE" \
  python3 "${OPENCLAW_DIR}/forge-webhook-relay.py"

sleep 2
docker run --rm --network "$NETWORK" curlimages/curl:8.5.0 -sf --max-time 5 \
  "http://${CONTAINER}:${PORT}/health" >/dev/null \
  && echo "[relay-docker] OK — ${CONTAINER}:${PORT} reachable from ${NETWORK}" \
  || { echo "[relay-docker] FAIL — health check from docker network" >&2; exit 1; }

curl -sf --max-time 5 "http://127.0.0.1:${PORT}/health" >/dev/null \
  && echo "[relay-docker] OK — 127.0.0.1:${PORT} published for local gates" \
  || echo "[relay-docker] WARN — local publish check failed"

echo "[relay-docker] CPM upstream should be: http://${CONTAINER}:${PORT}"
