#!/usr/bin/env bash
# Run skylight-login if smoke fails with auth error.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if bash "${SCRIPT_DIR}/skylight-smoke.sh" 2>/dev/null; then
  echo "skylight-auth-refresh: smoke OK"
  exit 0
fi

echo "skylight-auth-refresh: smoke failed — running login" >&2
bash "${SCRIPT_DIR}/skylight-login.sh"
bash "${SCRIPT_DIR}/skylight-smoke.sh"
