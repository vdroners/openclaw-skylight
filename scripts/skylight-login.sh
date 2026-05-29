#!/usr/bin/env bash
# Authenticate to Skylight via skylight-tools CLI; refresh token in config.yaml.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENCLAW_DIR="${OPENCLAW_DIR:-$HOME/.openclaw}"
ENV_FILE="${OPENCLAW_DIR}/.env"

export PATH="${HOME}/go/bin:${PATH}"

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "$ENV_FILE"
  set +a
fi

: "${SKYLIGHT_EMAIL:?set SKYLIGHT_EMAIL in ~/.openclaw/.env}"
: "${SKYLIGHT_PASSWORD:?set SKYLIGHT_PASSWORD in ~/.openclaw/.env}"

ARGS=(account login --email "$SKYLIGHT_EMAIL" --password "$SKYLIGHT_PASSWORD")
if [[ -n "${SKYLIGHT_FRAME_ID:-}" ]]; then
  ARGS+=(--save-frame-id "$SKYLIGHT_FRAME_ID")
fi

skylight "${ARGS[@]}"
echo "skylight-login: token saved to ${SKYLIGHT_CONFIG_PATH:-$HOME/.config/skylight/config.yaml}"
