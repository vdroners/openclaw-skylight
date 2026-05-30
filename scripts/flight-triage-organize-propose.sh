#!/usr/bin/env bash
# flight-triage-organize-propose.sh — create NC batch + dry-run organize plan for Talk card.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=load-nextcloud-env.sh
source "${SCRIPT_DIR}/load-nextcloud-env.sh" 2>/dev/null || true

NC_APP_URL="${NC_TRIAGE_APP_URL:-${NC_URL%/}/index.php/apps/nc_ardupilot_triage}"
NC_USER="${NC_TRIAGE_USER:-NCAdmin}"
NC_PASS="${NC_TRIAGE_PASS:-${NC_WEBDAV_PASSWORD:-}}"
FOLDER_PATH="${2:-}"

if [[ -z "$NC_PASS" ]]; then
	echo '{"ok":false,"error":"NC_TRIAGE_PASS unset"}'
	exit 0
fi

BIN_JSON="${1:-[]}"
create_body=$(BIN_PATHS_JSON="$BIN_JSON" FOLDER_PATH="$FOLDER_PATH" python3 -c '
import json, os
bins = json.loads(os.environ["BIN_PATHS_JSON"])
print(json.dumps({"bin_paths": bins, "folder_path": os.environ["FOLDER_PATH"], "source": "openclaw"}))
')

resp=$(curl -sS -u "${NC_USER}:${NC_PASS}" \
	-H "Content-Type: application/json" \
	-X POST "${NC_APP_URL}/api/batches" \
	-d "$create_body")

batch_id=$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('batch',{}).get('id',''))" <<<"$resp")
if [[ -z "$batch_id" ]]; then
	echo "$resp"
	exit 0
fi

plan=$(curl -sS -u "${NC_USER}:${NC_PASS}" \
	-H "Content-Type: application/json" \
	-X POST "${NC_APP_URL}/api/batches/${batch_id}/organize-plan" \
	-d '{"options":{"rename":true,"slice":true}}')

python3 -c "import json,sys; c=json.loads(sys.argv[1]); p=json.loads(sys.argv[2]); print(json.dumps({'ok':True,'batch_id':c.get('batch',{}).get('id'),'plan_excerpt':str(p)[:2000]},indent=2))" "$resp" "$plan"
