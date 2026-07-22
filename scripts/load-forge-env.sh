#!/usr/bin/env bash
# Load 3DPrintForge / Alfred forge integration env.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENCLAW_DIR="${OPENCLAW_DIR:-$HOME/.openclaw}"
ROOT="${OPENCLAW_SKYLIGHT_ROOT:-}"

_preserve_enabled="${FORGE_ENABLED-__unset__}"

if [[ -z "$ROOT" && -d "${SCRIPT_DIR}/../config" ]]; then
  ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
fi

ENV_FILE="${OPENCLAW_DIR}/.env"
if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "$ENV_FILE"
  set +a
fi

_read_secret() {
  local path="$1"
  [[ -n "$path" ]] || return 0
  path="${path/#\~/$HOME}"
  [[ -f "$path" ]] || return 0
  cat "$path"
}

export OPENCLAW_DIR
export FORGE_ENABLED="${FORGE_ENABLED:-0}"
export FORGE_API_URL="${FORGE_API_URL:-https://127.0.0.1:3040}"
export FORGE_API_KEY_FILE="${FORGE_API_KEY_FILE:-${OPENCLAW_DIR}/.env.d/forge-api.secret}"
export FORGE_PRINTER_ID="${FORGE_PRINTER_ID:-k1-max}"
export FORGE_DASHBOARD_URL="${FORGE_DASHBOARD_URL:-https://forge-vdroners.ddns.net}"
export FORGE_ALERT_TALK_ROOM="${FORGE_ALERT_TALK_ROOM:-${SKYLIGHT_OPS_TALK_ROOM:-}}"
export FORGE_WEBHOOK_SECRET_FILE="${FORGE_WEBHOOK_SECRET_FILE:-${OPENCLAW_DIR}/.env.d/forge-webhook.secret}"
export FORGE_WEBHOOK_BIND="${FORGE_WEBHOOK_BIND:-127.0.0.1}"
export FORGE_WEBHOOK_PORT="${FORGE_WEBHOOK_PORT:-8790}"
export FORGE_PUBLIC_WEBHOOK_URL="${FORGE_PUBLIC_WEBHOOK_URL:-https://alfred-vdroners.ddns.net/forge-webhook}"
export FORGE_QUIET_HOURS="${FORGE_QUIET_HOURS:-23:00-07:00}"
export FORGE_QUIET_CRITICAL_OVERRIDE="${FORGE_QUIET_CRITICAL_OVERRIDE:-1}"
export FORGE_ALERT_MIN_INTERVAL_M="${FORGE_ALERT_MIN_INTERVAL_M:-15}"
export FORGE_STUCK_PRINT_H="${FORGE_STUCK_PRINT_H:-2}"
export FORGE_SLICER_DOWN_M="${FORGE_SLICER_DOWN_M:-10}"
export FORGE_NATIVE_NOTIFY="${FORGE_NATIVE_NOTIFY:-0}"

if [[ -z "${FORGE_API_KEY:-}" ]]; then
  FORGE_API_KEY="$(_read_secret "$FORGE_API_KEY_FILE")"
  export FORGE_API_KEY
fi
if [[ -z "${FORGE_WEBHOOK_SECRET:-}" ]]; then
  FORGE_WEBHOOK_SECRET="$(_read_secret "$FORGE_WEBHOOK_SECRET_FILE")"
  export FORGE_WEBHOOK_SECRET
fi

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/load-nextcloud-env.sh" 2>/dev/null || true

if [[ "$_preserve_enabled" != "__unset__" ]]; then
  export FORGE_ENABLED="$_preserve_enabled"
fi

if [[ -z "${FORGE_ALERT_TALK_ROOM:-}" && -n "${SKYLIGHT_OPS_TALK_ROOM:-}" ]]; then
  export FORGE_ALERT_TALK_ROOM="$SKYLIGHT_OPS_TALK_ROOM"
fi
