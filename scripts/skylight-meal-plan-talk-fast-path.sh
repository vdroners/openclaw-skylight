#!/usr/bin/env bash
# Talk trigger for weekly meal-plan propose (no LLM).
# Usage: skylight-meal-plan-talk-fast-path.sh "message text" room_token
set -euo pipefail

MSG="${1:-}"
ROOM="${2:-}"
if [[ -z "$MSG" || -z "$ROOM" ]]; then
  echo "usage: $0 \"<message>\" <room_token>" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/load-skylight-env.sh"

export PATH="${HOME}/go/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}"

if ! python3 - "$MSG" "$SCRIPT_DIR" <<'PY'
import os, sys
from pathlib import Path
sys.path.insert(0, str(Path(sys.argv[2]) / "lib"))
from chore_talk_match import is_meal_plan_command
from forge_talk_match import is_tool_json_payload
msg = sys.argv[1]
if is_tool_json_payload(msg):
    raise SystemExit(2)
agent = (os.environ.get("OPENCLAW_AGENT_MENTION") or "@alfred").lstrip("@")
raise SystemExit(0 if is_meal_plan_command(msg, agent) else 2)
PY
then
  echo "skylight-meal-plan-talk-fast-path: not a meal-plan command" >&2
  exit 2
fi

if [[ "${MEAL_PLAN_TALK_DRY_RUN:-0}" == "1" ]]; then
  bash "${SCRIPT_DIR}/skylight-meal-plan-propose.sh" --dry-run
  echo "skylight-meal-plan-talk-fast-path: dry-run ok room=$ROOM"
  exit 0
fi

bash "${SCRIPT_DIR}/skylight-meal-plan-propose.sh"
echo "skylight-meal-plan-talk-fast-path: ok room=$ROOM"
