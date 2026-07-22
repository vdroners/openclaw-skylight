#!/usr/bin/env bash
# Forge Talk dispatch (read-only v1).
# Usage: forge-dispatch-exec.sh "<message>" | forge-dispatch-exec.sh help
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/load-forge-env.sh"

if [[ "${FORGE_ENABLED:-0}" != "1" ]]; then
  echo "Forge integration disabled (FORGE_ENABLED=0)."
  exit 0
fi

MSG="${1:-help}"
SUBCMD="$(python3 - "$MSG" "$SCRIPT_DIR" <<'PY'
import os, sys
sys.path.insert(0, os.path.join(sys.argv[2], "lib"))
from forge_talk_match import parse_forge_subcommand
agent = (os.environ.get("OPENCLAW_AGENT_MENTION") or "@alfred").lstrip("@")
print(parse_forge_subcommand(sys.argv[1], agent))
PY
)"

case "$SUBCMD" in
  help)
    M="${OPENCLAW_AGENT_MENTION:-@alfred}"
    cat <<EOF
[forge] Commands (read-only):
- ${M} print status — K1 Max state, file, temps
- ${M} print queue — Moonraker job queue
- ${M} print slicer — Forge Slicer health
- ${M} print help — this message
Dashboard: ${FORGE_DASHBOARD_URL:-https://forge-vdroners.ddns.net}
EOF
    ;;
  status)
    python3 "${SCRIPT_DIR}/lib/forge_api.py" status
    ;;
  queue)
    python3 - "$SCRIPT_DIR" <<'PY'
import json, os, sys
sys.path.insert(0, os.path.join(sys.argv[1], "lib"))
from forge_api import get_moonraker_queue, printer_id
code, data = get_moonraker_queue()
name = printer_id()
if code != 200:
    print(f"[forge] Queue unavailable (HTTP {code}).")
    raise SystemExit(0)
jobs = data.get("queue") if isinstance(data, dict) else data
if not jobs:
    print(f"[forge] {name} — queue empty.")
else:
    print(f"[forge] {name} queue:")
    if isinstance(jobs, list):
        for j in jobs[:10]:
            if isinstance(j, dict):
                print(f"- {j.get('filename') or j.get('name') or j}")
            else:
                print(f"- {j}")
    else:
        print(json.dumps(jobs, indent=2)[:800])
PY
    ;;
  slicer)
    python3 - "$SCRIPT_DIR" <<'PY'
import os, sys
sys.path.insert(0, os.path.join(sys.argv[1], "lib"))
from forge_api import get_slicer_status, slicer_health_direct
d_code, d = slicer_health_direct()
f_code, f = get_slicer_status()
ok_d = isinstance(d, dict) and d.get("ok")
probe = (f.get("probe") or {}) if isinstance(f, dict) else {}
ok_f = probe.get("ok") if isinstance(probe, dict) else f.get("ok")
if ok_d or ok_f:
    ver = d.get("version") if isinstance(d, dict) else ""
    print(f"[forge] Forge Slicer OK (direct={ok_d}, forge={ok_f}) {ver}".strip())
else:
    print("[forge] Forge Slicer DOWN — check: systemctl --user status forge-slicer")
PY
    ;;
  camera)
    pid="${FORGE_PRINTER_ID:-k1-max}"
    echo "[forge] Camera snapshot: ${FORGE_DASHBOARD_URL}/#printer/${pid}"
    ;;
  *)
    python3 "${SCRIPT_DIR}/lib/forge_api.py" status
    ;;
esac
