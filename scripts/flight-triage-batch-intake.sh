#!/usr/bin/env bash
# flight-triage-batch-intake.sh — prefill + optional submit for a staged batch (dry-run default).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=load-nextcloud-env.sh
source "${SCRIPT_DIR}/load-nextcloud-env.sh" 2>/dev/null || true

NC_APP_URL="${NC_TRIAGE_APP_URL:-${NC_URL%/}/index.php/apps/nc_ardupilot_triage}"
NC_USER="${NC_TRIAGE_USER:-NCAdmin}"
NC_PASS="${NC_TRIAGE_PASS:-${NC_WEBDAV_PASSWORD:-}}"
BATCH_ID="${1:-}"
SUBMIT="${2:-no}"

if [[ -z "$BATCH_ID" || -z "$NC_PASS" ]]; then
	echo '{"ok":false,"error":"usage: flight-triage-batch-intake.sh <batch_id> [yes|no]"}'
	exit 1
fi

prefill=$(curl -sS -u "${NC_USER}:${NC_PASS}" \
	-H "Content-Type: application/json" \
	-X POST "${NC_APP_URL}/api/batches/${BATCH_ID}/prefill" \
	-d '{}')

if [[ "$SUBMIT" != "yes" ]]; then
	echo "$prefill" | python3 -m json.tool 2>/dev/null || echo "$prefill"
	exit 0
fi

echo "$prefill"
echo "Submit requires operator-confirmed intake JSON — use NC Batch wizard or pass rows via API."
