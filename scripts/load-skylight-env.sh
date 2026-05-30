#!/usr/bin/env bash
# Export Skylight API env from ~/.openclaw/.env, repo .env, and skylight config.yaml.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENCLAW_DIR="${OPENCLAW_DIR:-$HOME/.openclaw}"
ROOT="${OPENCLAW_SKYLIGHT_ROOT:-}"

if [[ -z "$ROOT" && -d "${SCRIPT_DIR}/../config" ]]; then
  ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
fi

ENV_FILE="${OPENCLAW_DIR}/.env"
CFG="${HOME}/.config/skylight/config.yaml"

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "$ENV_FILE"
  set +a
fi

if [[ -n "$ROOT" && -f "${ROOT}/.env" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "${ROOT}/.env"
  set +a
fi

export SKYLIGHT_URL="${SKYLIGHT_URL:-https://app.ourskylight.com}"
export SKYLIGHT_API_URL="${SKYLIGHT_API_URL:-https://app.ourskylight.com/api}"
export SKYLIGHT_TIMEZONE="${SKYLIGHT_TIMEZONE:-America/Los_Angeles}"
export SKYLIGHT_FAMILY_TALK_ROOM="${SKYLIGHT_FAMILY_TALK_ROOM:-}"
export SKYLIGHT_OPS_TALK_ROOM="${SKYLIGHT_OPS_TALK_ROOM:-}"
export SKYLIGHT_CONFIG_PATH="${SKYLIGHT_CONFIG_PATH:-$CFG}"
export OPENCLAW_SKYLIGHT_ROOT="${ROOT:-$OPENCLAW_DIR}"
export PATH="${HOME}/go/bin:${PATH}"

if [[ -n "$ROOT" && -f "${ROOT}/config/household-model.json" ]]; then
  export HOUSEHOLD_MODEL_JSON="${ROOT}/config/household-model.json"
elif [[ -f "${OPENCLAW_DIR}/config/household-model.json" ]]; then
  export HOUSEHOLD_MODEL_JSON="${OPENCLAW_DIR}/config/household-model.json"
fi

if [[ -f "$CFG" ]]; then
  eval "$(python3 - "$CFG" <<'PY'
import shlex, sys
from pathlib import Path
try:
    import yaml
except ImportError:
    yaml = None
p = Path(sys.argv[1])
if yaml and p.is_file():
    data = yaml.safe_load(p.read_text()) or {}
    token = str(data.get("token") or "").strip()
    frame = data.get("frame_id") or ""
    if token:
        print(f"export SKYLIGHT_RAW_TOKEN={shlex.quote(token)}")
        print(f"export SKYLIGHT_AUTHORIZATION={shlex.quote('Bearer ' + token)}")
    if frame and not __import__("os").environ.get("SKYLIGHT_FRAME_ID"):
        print(f"export SKYLIGHT_FRAME_ID={shlex.quote(str(frame))}")
PY
)"
fi

unset SKYLIGHT_TOKEN 2>/dev/null || true

: "${SKYLIGHT_FRAME_ID:?SKYLIGHT_FRAME_ID not set}"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/load-agent-env.sh" 2>/dev/null || true
