#!/usr/bin/env bash
# Shell-direct wrapper: scan Flight Recordings and propose newest unseen BIN.
# Usage: flight-triage-shell.sh [--dry-run]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/load-nextcloud-env.sh" 2>/dev/null || true
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/load-agent-env.sh" 2>/dev/null || true

export PATH="${HOME}/go/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}"

DRY=0
[[ "${1:-}" == "--dry-run" ]] && DRY=1

STATE_DIR="${OPENCLAW_DIR:-$HOME/.openclaw}/state/flight-triage-proposals"
mkdir -p "$STATE_DIR"
SEEN_FILE="${STATE_DIR}/seen-bins.json"
OPS_ROOM="${FLIGHT_TRIAGE_TALK_ROOM:-${SKYLIGHT_OPS_TALK_ROOM:-}}"
MENTION="${OPENCLAW_AGENT_MENTION:-@alfred}"

scan_raw="$("${SCRIPT_DIR}/flight-triage-scan.sh" 2>/dev/null || true)"
if [[ -z "$scan_raw" ]]; then
  echo "FLIGHT_TRIAGE_SHELL no bins (empty scan)"
  exit 0
fi
if echo "$scan_raw" | grep -q '"error"'; then
  echo "FLIGHT_TRIAGE_SHELL scan_error ${scan_raw}"
  exit 1
fi

export scan_raw SEEN_FILE STATE_DIR OPS_ROOM MENTION DRY SCRIPT_DIR
python3 <<'PY'
import json, os, re, subprocess, time
from pathlib import Path
from urllib.parse import unquote

raw = os.environ.get("scan_raw") or ""
seen_path = Path(os.environ["SEEN_FILE"])
state_dir = Path(os.environ["STATE_DIR"])
ops = os.environ.get("OPS_ROOM") or ""
mention = os.environ.get("MENTION") or "@alfred"
dry = os.environ.get("DRY") == "1"
script_dir = Path(os.environ["SCRIPT_DIR"])

hrefs = re.findall(r"<d:href>([^<]+\.bin)</d:href>", raw, flags=re.I)
# also catch unquoted paths from grep-style output
if not hrefs:
    hrefs = re.findall(r"(/remote\.php/dav/files/[^\s\"']+\.bin)", raw, flags=re.I)
paths = []
for h in hrefs:
    p = unquote(h.strip())
    # Prefer absolute NC path starting at /remote.php…
    if not p.startswith("/"):
        continue
    paths.append(p)

# unique preserve order
uniq = []
seen_u = set()
for p in paths:
    if p in seen_u:
        continue
    seen_u.add(p)
    uniq.append(p)

seen = {}
if seen_path.is_file():
    try:
        seen = json.loads(seen_path.read_text())
    except Exception:
        seen = {}
if not isinstance(seen, dict):
    seen = {}

pending = [p for p in uniq if p not in seen]
if not pending:
    print("FLIGHT_TRIAGE_SHELL no new bins")
    raise SystemExit(0)

# propose the first (most recently listed / shallowest) new bin
bin_path = pending[0]
pid = f"triage-{int(time.time()) % 1000000:06d}"
prop = {
    "version": 1,
    "proposals": [
        {
            "id": pid,
            "bin_path": bin_path,
            "status": "pending",
            "state": "pending",
        }
    ],
}
batch_path = state_dir / "batch-latest.json"
if dry:
    print(f"FLIGHT_TRIAGE_SHELL dry-run would propose {pid} {bin_path}")
    raise SystemExit(0)

batch_path.write_text(json.dumps(prop, indent=2))
msg = (
    f"Flight log ready for triage:\n{bin_path}\n"
    f"Reply: {mention} YES {pid} | {mention} NO {pid}"
)
talk = script_dir / "talk-post.sh"
if talk.is_file() and ops:
    subprocess.run(["bash", str(talk), msg, ops], check=False, timeout=30)
else:
    print(msg)
seen[bin_path] = {"proposed_at": int(time.time()), "proposal_id": pid}
seen_path.write_text(json.dumps(seen, indent=2))
print(f"FLIGHT_TRIAGE_SHELL proposed {pid}")
PY
