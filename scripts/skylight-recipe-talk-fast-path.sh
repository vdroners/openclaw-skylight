#!/usr/bin/env bash
# Recipe Talk fast-path (no LLM).
# Usage: skylight-recipe-talk-fast-path.sh "message text" room_token
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

talk_post="${OPENCLAW_DIR:-$HOME/.openclaw}/scripts/talk-post.sh"
if [[ ! -x "$talk_post" ]]; then
  talk_post="${SCRIPT_DIR}/talk-post.sh"
fi

clean_msg="$(python3 - "$MSG" "$SCRIPT_DIR" <<'PY'
import sys
from pathlib import Path
sys.path.insert(0, str(Path(sys.argv[2]) / "lib"))
from forge_talk_match import extract_user_message, is_tool_json_payload
raw = sys.argv[1]
if is_tool_json_payload(raw):
    sys.exit(2)
print(extract_user_message(raw))
PY
)" || {
  echo "skylight-recipe-talk-fast-path: ignored tool JSON payload" >&2
  exit 0
}

summary="$(bash "${SCRIPT_DIR}/skylight-recipe-dispatch-exec.sh" "$clean_msg" 2>&1 || true)"
if [[ -z "$summary" ]]; then
  M="${OPENCLAW_AGENT_MENTION:-@alfred}"
  summary="[recipe] could not parse that command. Try: ${M} recipe banana | ${M} bread courses"
fi
summary="$(printf '%s' "$summary" | head -c 4000)"

if [[ "${RECIPE_TALK_DRY_RUN:-0}" == "1" ]]; then
  echo "$summary"
  echo "skylight-recipe-talk-fast-path: dry-run ok room=$ROOM chars=${#summary}"
  exit 0
fi

bash "$talk_post" "$summary" "$ROOM"
echo "skylight-recipe-talk-fast-path: ok room=$ROOM chars=${#summary}"
