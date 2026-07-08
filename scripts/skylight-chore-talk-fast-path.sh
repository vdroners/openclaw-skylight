#!/usr/bin/env bash
# Chore Talk fast-path (no LLM).
# Usage: skylight-chore-talk-fast-path.sh "message text" room_token
# Commands: @alfred chores | @alfred done dishes
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

talk_post="${OPENCLAW_DIR:-$HOME/.openclaw}/scripts/talk-post.sh"
if [[ ! -x "$talk_post" ]]; then
  talk_post="${SCRIPT_DIR}/talk-post.sh"
fi

export MSG ROOM SCRIPT_DIR OPENCLAW_AGENT_MENTION SKYLIGHT_FRAME_ID CHORE_TALK_DRY_RUN

summary="$(
python3 <<'PY'
import json, os, re, subprocess, sys
from datetime import date, timedelta
from pathlib import Path

sys.path.insert(0, str(Path(os.environ["SCRIPT_DIR"]) / "lib"))
from chore_talk_match import parse_chore_command
from forge_talk_match import extract_user_message, is_tool_json_payload

raw = os.environ.get("MSG") or ""
if is_tool_json_payload(raw):
    print("skylight-chore-talk-fast-path: ignored tool JSON", file=sys.stderr)
    sys.exit(0)

mention = os.environ.get("OPENCLAW_AGENT_MENTION") or "@alfred"
agent = mention.lstrip("@") or "alfred"
action, rem = parse_chore_command(raw, agent)
fid = os.environ["SKYLIGHT_FRAME_ID"]
today = date.today()
tomorrow = today + timedelta(days=1)

def list_chores():
    out = subprocess.check_output(
        [
            "skylight", "chores", "listChores",
            "--frame-id", fid,
            "--after", today.isoformat(),
            "--before", tomorrow.isoformat(),
            "--json",
        ],
        text=True,
    )
    return json.loads(out).get("data") or []

def is_complete(attrs: dict) -> bool:
    st = str(attrs.get("status") or "").lower()
    if st in ("complete", "completed", "done"):
        return True
    if attrs.get("completed") in (True, "true", 1, "1"):
        return True
    return False

def person_label(c: dict) -> str:
    rel = (c.get("relationships") or {}).get("category") or {}
    data = rel.get("data") or {}
    return str(data.get("id") or "")

rows = list_chores()
open_rows = []
for c in rows:
    a = c.get("attributes") or {}
    if is_complete(a):
        continue
    open_rows.append(c)

if action == "list":
    if not open_rows:
        print(f"[chores] No open chores for {today.isoformat()}.")
        sys.exit(0)
    lines = [f"[chores] Open today ({today.isoformat()}) — {len(open_rows)}"]
    for c in open_rows[:20]:
        a = c.get("attributes") or {}
        summary = (a.get("summary") or "?").strip()
        st = a.get("start_time") or ""
        lines.append(f"• {summary}" + (f" @ {st}" if st else ""))
    if len(open_rows) > 20:
        lines.append(f"… and {len(open_rows) - 20} more")
    lines.append(f"Mark done: {mention} done <name>")
    print("\n".join(lines))
    sys.exit(0)

if action != "done" or not rem:
    print(
        f"[chores] Try: {mention} chores | {mention} done dishes",
        file=sys.stderr,
    )
    sys.exit(2)

needle = rem.lower().strip()
needle = re.sub(r"^(the|my|our)\s+", "", needle)
matches = []
for c in open_rows:
    a = c.get("attributes") or {}
    title = (a.get("summary") or "").strip()
    tl = title.lower()
    if needle == tl or needle in tl or tl in needle:
        matches.append(c)

if not matches:
    # token overlap fuzzy
    tokens = [t for t in re.split(r"\W+", needle) if len(t) > 2]
    for c in open_rows:
        a = c.get("attributes") or {}
        title = (a.get("summary") or "").strip().lower()
        if tokens and all(t in title for t in tokens):
            matches.append(c)

# dedupe by id
seen = set()
uniq = []
for c in matches:
    cid = c.get("id")
    if cid in seen:
        continue
    seen.add(cid)
    uniq.append(c)
matches = uniq

if not matches:
    print(f"[chores] No open chore matching {rem!r}. Try: {mention} chores")
    sys.exit(0)

if len(matches) > 1:
    titles = {
        ((c.get("attributes") or {}).get("summary") or "").strip().lower()
        for c in matches
    }
    if len(titles) == 1:
        # Same chore series / duplicate title — complete the first open instance.
        matches = matches[:1]
    else:
        lines = [f"[chores] Multiple matches for {rem!r} — be more specific:"]
        for c in matches[:8]:
            a = c.get("attributes") or {}
            lines.append(f"• {(a.get('summary') or '?')}")
        print("\n".join(lines))
        sys.exit(0)

chosen = matches[0]
cid = chosen["id"]
title = ((chosen.get("attributes") or {}).get("summary") or cid).strip()
dry = os.environ.get("CHORE_TALK_DRY_RUN", "0") == "1"
if dry:
    print(f"[chores] DRY: would complete {title!r} id={cid}")
    sys.exit(0)

subprocess.check_call(
    [
        "skylight", "chores", "completeChore",
        "--frame-id", fid,
        "--chore-id", cid,
    ],
)
print(f"[chores] Marked complete: {title}")
PY
)" || {
  rc=$?
  if [[ "$rc" -eq 2 ]]; then
    M="${OPENCLAW_AGENT_MENTION:-@alfred}"
    summary="[chores] could not parse that. Try: ${M} chores | ${M} done dishes"
  else
    echo "skylight-chore-talk-fast-path: failed rc=$rc" >&2
    exit "$rc"
  fi
}

summary="$(printf '%s' "${summary:-}" | head -c 4000)"
[[ -n "$summary" ]] || exit 0

if [[ "${CHORE_TALK_DRY_RUN:-0}" == "1" ]]; then
  echo "$summary"
  echo "skylight-chore-talk-fast-path: dry-run ok room=$ROOM chars=${#summary}"
  exit 0
fi

bash "$talk_post" "$summary" "$ROOM"
echo "skylight-chore-talk-fast-path: ok room=$ROOM chars=${#summary}"
