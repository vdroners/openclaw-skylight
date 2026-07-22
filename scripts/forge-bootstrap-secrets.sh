#!/usr/bin/env bash
# Bootstrap Forge API key + webhook HMAC secret for Alfred (idempotent).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENCLAW_DIR="${OPENCLAW_DIR:-$HOME/.openclaw}"
ENV_D="${OPENCLAW_DIR}/.env.d"
API_FILE="${FORGE_API_KEY_FILE:-${ENV_D}/forge-api.secret}"
WH_FILE="${FORGE_WEBHOOK_SECRET_FILE:-${ENV_D}/forge-webhook.secret}"
API_FILE="${API_FILE/#\~/$HOME}"
WH_FILE="${WH_FILE/#\~/$HOME}"
FORGE_URL="${FORGE_API_URL:-https://127.0.0.1:3040}"
ADMIN_PASS_FILE="${FORGE_ADMIN_PASS_FILE:-/media/4TB/3dprintforge/.admin_pass}"

mkdir -p "$ENV_D"
chmod 700 "$ENV_D" 2>/dev/null || true

if [[ ! -f "$WH_FILE" ]]; then
  openssl rand -hex 32 >"$WH_FILE"
  chmod 600 "$WH_FILE"
  echo "created webhook secret: $WH_FILE"
fi

if [[ -f "$API_FILE" && -s "$API_FILE" ]]; then
  echo "api key already exists: $API_FILE"
  exit 0
fi

if [[ ! -f "$ADMIN_PASS_FILE" ]]; then
  echo "missing admin password file: $ADMIN_PASS_FILE" >&2
  exit 1
fi
ADMIN_PASS="$(cat "$ADMIN_PASS_FILE")"
COOKIE="$(mktemp)"
trap 'rm -f "$COOKIE"' EXIT

curl -sk -c "$COOKIE" -b "$COOKIE" -X POST "${FORGE_URL}/api/auth/login" \
  -H 'Content-Type: application/json' \
  -d "{\"username\":\"admin\",\"password\":\"${ADMIN_PASS}\"}" | grep -q '"ok":true' \
  || { echo "forge login failed" >&2; exit 1; }

RESP="$(curl -sk -b "$COOKIE" -X POST "${FORGE_URL}/api/keys" \
  -H 'Content-Type: application/json' \
  -d '{"name":"alfred-automation","permissions":["view","controls"]}')"

KEY="$(python3 -c "import json,sys; print(json.loads(sys.argv[1]).get('key',''))" "$RESP" 2>/dev/null || true)"
if [[ -z "$KEY" ]]; then
  echo "failed to create API key: $RESP" >&2
  exit 1
fi
printf '%s' "$KEY" >"$API_FILE"
chmod 600 "$API_FILE"
echo "created api key: $API_FILE"
