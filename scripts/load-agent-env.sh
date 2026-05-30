#!/usr/bin/env bash
# Agent mention alias for Talk proposal commands (override in .env if needed).
set -euo pipefail

export OPENCLAW_AGENT_MENTION="${OPENCLAW_AGENT_MENTION:-@openclaw}"
export OPENCLAW_AGENT_NAME="${OPENCLAW_AGENT_NAME:-${OPENCLAW_AGENT_MENTION#@}}"

MODEL="${HOUSEHOLD_MODEL_JSON:-}"
if [[ -n "$MODEL" && -f "$MODEL" ]]; then
  eval "$(python3 - "$MODEL" <<'PY'
import json, shlex, sys
from pathlib import Path
p = Path(sys.argv[1])
if not p.is_file():
    raise SystemExit
m = json.loads(p.read_text())
mention = (m.get("agent_mention") or "").strip()
if mention:
    print(f"export OPENCLAW_AGENT_MENTION={shlex.quote(mention)}")
    print(f"export OPENCLAW_AGENT_NAME={shlex.quote(mention.lstrip('@'))}")
PY
)"
fi
