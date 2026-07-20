#!/usr/bin/env bash
# Export NEXTCLOUD_URL/USER/PASS from env or openclaw.json skill env overlay.
set -euo pipefail

OPENCLAW_DIR="${OPENCLAW_DIR:-$HOME/.openclaw}"
CFG="${OPENCLAW_DIR}/openclaw.json"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${OPENCLAW_SKYLIGHT_ROOT:-}"

if [[ -z "$ROOT" && -d "${SCRIPT_DIR}/../config" ]]; then
  ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
fi

if [[ -f "${OPENCLAW_DIR}/.env" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "${OPENCLAW_DIR}/.env"
  set +a
fi

if [[ -n "$ROOT" && -f "${ROOT}/.env" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "${ROOT}/.env"
  set +a
fi

if [[ -f "$CFG" ]]; then
  eval "$(python3 - "$CFG" <<'PY'
import json, os, shlex, sys
from pathlib import Path
cfg = json.loads(Path(sys.argv[1]).read_text())
env = (cfg.get("skills") or {}).get("entries", {}).get("nextcloud", {}).get("env") or {}
for k in ("NEXTCLOUD_URL", "NEXTCLOUD_USER", "NEXTCLOUD_PASS"):
    v = env.get(k) or os.environ.get(k)
    if v:
        print(f"export {k}={shlex.quote(str(v))}")
PY
)"
fi

: "${NEXTCLOUD_URL:?NEXTCLOUD_URL not set — export or add to .env}"
: "${NEXTCLOUD_USER:?NEXTCLOUD_USER not set}"
: "${NEXTCLOUD_PASS:?NEXTCLOUD_PASS not set}"

# Aliases used by flight-triage-scan / intake (NC_* family)
export NC_URL="${NC_URL:-$NEXTCLOUD_URL}"
export NC_WEBDAV_USERNAME="${NC_WEBDAV_USERNAME:-$NEXTCLOUD_USER}"
export NC_WEBDAV_PASSWORD="${NC_WEBDAV_PASSWORD:-$NEXTCLOUD_PASS}"
