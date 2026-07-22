#!/usr/bin/env bash
# Archive and clear one or more OpenClaw session keys (context overflow recovery).
#
# Usage:
#   reset-openclaw-session.sh agent:main:main
#   reset-openclaw-session.sh agent:main:nextcloud-talk:group:9x4f25n3
#   reset-openclaw-session.sh --all-talk-rooms
#
# Stops the gateway briefly so sessions.json is not rewritten mid-edit.
set -euo pipefail

AGENT="${OPENCLAW_AGENT:-main}"
SESSIONS_DIR="${OPENCLAW_SESSIONS_DIR:-$HOME/.openclaw/agents/${AGENT}/sessions}"
SESSIONS_JSON="${SESSIONS_DIR}/sessions.json"
ARCHIVE_DIR="${SESSIONS_DIR}/archive"
STAMP="$(date -Iseconds)"
ORPHAN_MIN_BYTES="${RESET_ORPHAN_MIN_BYTES:-1048576}"

usage() {
  echo "Usage: $0 <sessionKey> [sessionKey...]" >&2
  echo "       $0 --all-talk-rooms" >&2
  exit 2
}

[[ $# -ge 1 ]] || usage

KEYS=()
if [[ "$1" == "--all-talk-rooms" ]]; then
  mapfile -t KEYS < <(python3 - "$SESSIONS_JSON" <<'PY'
import json, sys
p = sys.argv[1]
data = json.load(open(p))
for k in sorted(data):
    if "nextcloud-talk:group:" in k and not k.endswith(":heartbeat"):
        print(k)
PY
  )
  [[ ${#KEYS[@]} -gt 0 ]] || { echo "No talk room session keys found" >&2; exit 1; }
else
  KEYS=("$@")
fi

mkdir -p "$ARCHIVE_DIR"

echo "Stopping openclaw-gateway for session reset..."
systemctl --user stop openclaw-gateway 2>/dev/null || true

python3 - "$SESSIONS_JSON" "$ARCHIVE_DIR" "$STAMP" "$ORPHAN_MIN_BYTES" "${KEYS[@]}" <<'PY'
import json, shutil, sys
from pathlib import Path

sessions_json = Path(sys.argv[1])
archive_dir = Path(sys.argv[2])
stamp = sys.argv[3]
orphan_min = int(sys.argv[4])
keys = sys.argv[5:]
sessions_dir = sessions_json.parent

data = json.loads(sessions_json.read_text())
active_ids = set()
for entry in data.values():
    if isinstance(entry, dict) and isinstance(entry.get("sessionId"), str):
        active_ids.add(entry["sessionId"])

removed = []
for key in keys:
    entry = data.pop(key, None)
    if entry is None:
        print(f"skip (not in sessions.json): {key}")
        continue
    sid = entry.get("sessionId") if isinstance(entry, dict) else entry
    if not isinstance(sid, str):
        print(f"skip (no sessionId): {key}")
        continue
    dest = archive_dir / f"{stamp}-{sid}"
    dest.mkdir(parents=True, exist_ok=True)
    for pattern in (f"{sid}.jsonl", f"{sid}.trajectory.jsonl", f"{sid}.*"):
        for path in sessions_dir.glob(pattern):
            if path.is_file():
                shutil.move(str(path), str(dest / path.name))
    active_ids.discard(sid)
    removed.append(f"{key} -> {sid}")
    print(f"archived {key} ({sid})")

sessions_json.write_text(json.dumps(data, indent=2) + "\n")

orphan_n = 0
orphan_dest = archive_dir / f"{stamp}-orphan-trajectories"
for path in sessions_dir.glob("*.trajectory.jsonl"):
    if not path.is_file() or path.stat().st_size < orphan_min:
        continue
    sid = path.name.replace(".trajectory.jsonl", "")
    if sid in active_ids:
        continue
    orphan_dest.mkdir(parents=True, exist_ok=True)
    shutil.move(str(path), str(orphan_dest / path.name))
    orphan_n += 1

print(f"reset complete: {len(removed)} session(s), {orphan_n} orphan trajectory file(s)")
PY

echo "Starting openclaw-gateway..."
systemctl --user start openclaw-gateway
sleep 5
code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 http://127.0.0.1:18789/health 2>/dev/null || echo 000)
echo "gateway health=$code"
