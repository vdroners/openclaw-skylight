#!/usr/bin/env bash
# flight-triage-scan.sh — list recent .bin under Flight Recordings (DAV).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=load-nextcloud-env.sh
source "${SCRIPT_DIR}/load-nextcloud-env.sh" 2>/dev/null || true

NC_URL="${NC_URL:-}"
USER="${NC_WEBDAV_USERNAME:-NCAdmin}"
PASS="${NC_WEBDAV_PASSWORD:-}"
ROOT="${FLIGHT_TRIAGE_SCAN_ROOT:-/remote.php/dav/files/${USER}/Flight Recordings}"

if [[ -z "$NC_URL" || -z "$PASS" ]]; then
	echo '{"bins":[],"error":"NC_URL or NC_WEBDAV_PASSWORD unset"}'
	exit 0
fi

encoded=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${ROOT}'))")
url="${NC_URL%/}${encoded}"

curl -sS -u "${USER}:${PASS}" -X PROPFIND "$url" \
	-H "Depth: 3" \
	-H "Content-Type: text/xml" \
	--data '<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop><d:displayname/><d:getlastmodified/></d:prop></d:propfind>' \
	| grep -i '\.bin' | head -20 || true
