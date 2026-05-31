#!/usr/bin/env bash
# Post a message to Nextcloud Talk via OCS API (form-encoded; avoids JSON 400s).
# Usage: talk-post.sh "message body" [room_token]
#        talk-post.sh --dry-run "message" [room_token]
#        talk-post.sh --test-retry
# Env: NEXTCLOUD_URL, NEXTCLOUD_USER, NEXTCLOUD_PASS
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/load-nextcloud-env.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/nc-http-retry.sh"

: "${NEXTCLOUD_URL:?missing NEXTCLOUD_URL}"
: "${NEXTCLOUD_USER:?missing NEXTCLOUD_USER}"
: "${NEXTCLOUD_PASS:?missing NEXTCLOUD_PASS}"

if [[ "${1:-}" == "--test-retry" ]]; then
  echo "NC-TALK-2 retry helper loaded (nc-http-retry.sh)"
  exit 0
fi

DRY=0
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY=1
  shift
fi

ROOM="${2:-${SKYLIGHT_OPS_TALK_ROOM:?set SKYLIGHT_OPS_TALK_ROOM in .env}}"
MAX_CHARS="${TALK_MAX_CHARS:-32000}"

MSG="$(printf '%s' "${1:-}" | head -c "$MAX_CHARS")"
if [ -z "$MSG" ]; then
  echo "talk-post: empty message" >&2
  exit 1
fi

if [[ "$DRY" -eq 1 ]]; then
  echo "talk-post: dry-run ok room=$ROOM chars=${#MSG}"
  exit 0
fi

CHAT_URL="$NEXTCLOUD_URL/ocs/v2.php/apps/spreed/api/v1/chat/$ROOM"
RESP="$(nc_curl_retry -sS -u "$NEXTCLOUD_USER:$NEXTCLOUD_PASS" \
  -H 'OCS-APIRequest: true' -H 'Accept: application/json' \
  -X POST \
  --data-urlencode "message=$MSG" \
  "$CHAT_URL")"

STATUS="$(printf '%s' "$RESP" | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
except json.JSONDecodeError:
    print("parse_error")
    raise SystemExit(0)
meta = (d.get("ocs") or {}).get("meta") or {}
print(meta.get("status", "unknown"))
code = meta.get("statuscode", "")
if code:
    print(code, file=sys.stderr)
')"

if [ "$STATUS" != "ok" ]; then
  echo "talk-post: failed status=$STATUS room=$ROOM http=${NC_HTTP_CODE:-?}" >&2
  printf '%s\n' "$RESP" >&2
  exit 1
fi

echo "talk-post: ok room=$ROOM chars=${#MSG}"
