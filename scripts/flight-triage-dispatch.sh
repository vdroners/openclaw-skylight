#!/usr/bin/env bash
# flight-triage-dispatch.sh — handle @alfred YES|NO triage-<id>
# Exit 0 = handled, 2 = not a triage command, 1 = error
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/load-agent-env.sh" 2>/dev/null || true
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/load-nextcloud-env.sh" 2>/dev/null || true

MSG="${1:-}"
[[ -n "$MSG" ]] || { echo "usage: $0 '<message>'" >&2; exit 1; }

AGENT="${OPENCLAW_AGENT_NAME:-${OPENCLAW_AGENT_MENTION#@}}"
AGENT="${AGENT:-alfred}"
OPS_ROOM="${FLIGHT_TRIAGE_TALK_ROOM:-${SKYLIGHT_OPS_TALK_ROOM:-}}"
STATE="${HOME}/.openclaw/state/flight-triage-proposals/batch-latest.json"
SEEN="${HOME}/.openclaw/state/flight-triage-proposals/seen-bins.json"

ACTION=""
PID=""
if printf '%s' "$MSG" | grep -qiE "@${AGENT}[[:space:]]+YES[[:space:]]+triage-"; then
  ACTION=yes
  PID=$(printf '%s' "$MSG" | grep -oiE 'triage-[0-9]+' | head -1)
elif printf '%s' "$MSG" | grep -qiE "@${AGENT}[[:space:]]+NO[[:space:]]+triage-"; then
  ACTION=no
  PID=$(printf '%s' "$MSG" | grep -oiE 'triage-[0-9]+' | head -1)
else
  echo "dispatch: not a flight-triage command"
  exit 2
fi

[[ -n "$PID" ]] || { echo "missing triage id" >&2; exit 1; }

if [[ ! -f "$STATE" ]]; then
  echo "no batch-latest for ${PID}" >&2
  [[ -n "$OPS_ROOM" ]] && bash "${SCRIPT_DIR}/talk-post.sh" \
    "Flight triage ${PID}: no pending proposal found." "$OPS_ROOM" || true
  exit 1
fi

eval "$(
python3 - "$STATE" "$PID" "$ACTION" <<'PY'
import json, shlex, sys
from pathlib import Path
state_path, pid, action = sys.argv[1:4]
doc = json.loads(Path(state_path).read_text())
props = doc.get("proposals") or []
found = None
for p in props:
    if str(p.get("id")) == pid:
        found = p
        break
if not found:
    print("FOUND=0")
    raise SystemExit(0)
print("FOUND=1")
print(f"BIN_PATH={shlex.quote(str(found.get('bin_path') or ''))}")
found["status"] = "applied" if action == "yes" else "rejected"
found["state"] = found["status"]
Path(state_path).write_text(json.dumps(doc, indent=2))
PY
)"

if [[ "${FOUND:-0}" != "1" ]]; then
  [[ -n "$OPS_ROOM" ]] && bash "${SCRIPT_DIR}/talk-post.sh" \
    "Flight triage ${PID}: unknown id (not in latest batch)." "$OPS_ROOM" || true
  exit 1
fi

if [[ "$ACTION" == "no" ]]; then
  [[ -n "$OPS_ROOM" ]] && bash "${SCRIPT_DIR}/talk-post.sh" \
    "Flight triage ${PID}: rejected (no intake)." "$OPS_ROOM" || true
  echo "{\"action\":\"no\",\"proposal_id\":\"${PID}\"}"
  exit 0
fi

STEM="$(basename "${BIN_PATH}" | sed 's/\.[Bb][Ii][Nn]$//')"
LABEL="${STEM}_openclaw_$(date +%Y%m%d)"
FOCUS="OpenClaw Talk approve ${PID}"

if [[ -x "${SCRIPT_DIR}/flight-triage-intake.sh" ]]; then
  out="$("${SCRIPT_DIR}/flight-triage-intake.sh" "$BIN_PATH" "$LABEL" "$FOCUS" 2>&1 || true)"
  [[ -n "$OPS_ROOM" ]] && bash "${SCRIPT_DIR}/talk-post.sh" \
    "Flight triage ${PID}: intake submitted for ${BIN_PATH}
${out:0:500}" "$OPS_ROOM" || true
else
  [[ -n "$OPS_ROOM" ]] && bash "${SCRIPT_DIR}/talk-post.sh" \
    "Flight triage ${PID}: intake script missing." "$OPS_ROOM" || true
  exit 1
fi

echo "{\"action\":\"yes\",\"proposal_id\":\"${PID}\",\"bin_path\":\"${BIN_PATH}\"}"
exit 0
