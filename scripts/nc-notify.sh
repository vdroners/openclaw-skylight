#!/usr/bin/env bash
# Post native Nextcloud notification via nc_gcs /api/notify.
# Usage: nc-notify.sh [--dry-run] <subject> <message> [link]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/load-nextcloud-env.sh"

DRY=0
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY=1
  shift
fi

SUBJECT="${1:-forge_alert}"
MESSAGE="${2:-}"
LINK="${3:-}"
[[ -n "$MESSAGE" ]] || { echo "usage: $0 [--dry-run] <subject> <message> [link]" >&2; exit 2; }

PAYLOAD="$(python3 - "$SUBJECT" "$MESSAGE" "$LINK" <<'PY'
import json, sys
subject, message, link = sys.argv[1:4]
params = {"message": message}
if link:
    params["link"] = link
print(json.dumps({"subject": subject, "params": params}))
PY
)"

if [[ "$DRY" -eq 1 ]]; then
  echo "nc-notify: dry-run ok subject=$SUBJECT"
  exit 0
fi

NC_BASE="${NEXTCLOUD_URL%/}/apps/nc_gcs/api"
code="$(curl -sS -o /tmp/nc-notify.out -w '%{http_code}' --max-time 20 \
  -u "${NEXTCLOUD_USER}:${NEXTCLOUD_PASS}" \
  -H 'OCS-APIRequest: true' -H 'Content-Type: application/json' \
  -X POST -d "$PAYLOAD" "${NC_BASE}/notify" 2>/dev/null || echo 000)"

if [[ "$code" =~ ^2 ]]; then
  echo "nc-notify: ok HTTP $code"
  exit 0
fi
echo "nc-notify: failed HTTP $code $(head -c 200 /tmp/nc-notify.out 2>/dev/null)" >&2
exit 1
