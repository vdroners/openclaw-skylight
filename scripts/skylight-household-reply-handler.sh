#!/usr/bin/env bash
# Parse Family Hub replies: @alfred YES|NO|EDIT <proposal-id> [text]
# Usage: skylight-household-reply-handler.sh "message text"
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/load-skylight-env.sh"

MSG="${1:-}"
[[ -n "$MSG" ]] || { echo "usage: $0 '<message>'" >&2; exit 1; }

STATE_DIR="${OPENCLAW_DIR:-$HOME/.openclaw}/state/household-proposals"
BATCH="${STATE_DIR}/batch-latest.json"
ROOM="${SKYLIGHT_FAMILY_TALK_ROOM:-}"

export BATCH ROOM SCRIPT_DIR MSG

python3 <<'PY'
import json, os, re, subprocess, sys
from datetime import datetime
from pathlib import Path

msg = os.environ["MSG"]
batch_path = Path(os.environ["BATCH"])
room = os.environ["ROOM"]
script_dir = os.environ["SCRIPT_DIR"]

m = re.search(
    r"@alfred\s+(YES|NO|EDIT)\s+(enrich-calendar-\d+|enrich-chore-\d+|ask-\d+)(?:\s+(.*))?",
    msg, re.I,
)
if not m:
    print("no household proposal command")
    sys.exit(0)

action, pid, extra = m.group(1).upper(), m.group(2), (m.group(3) or "").strip()
if not batch_path.is_file():
    print(f"No batch file for {pid}", file=sys.stderr)
    sys.exit(1)

batch = json.loads(batch_path.read_text())
prop = next((p for p in batch.get("proposals", []) if p["id"] == pid), None)
if not prop:
    print(f"Unknown proposal {pid} in batch", file=sys.stderr)
    sys.exit(1)

status = prop.get("status") or "pending"
terminal = {"applied", "rejected", "deferred"}

def post_confirm(text):
    r = subprocess.run(
        ["bash", f"{script_dir}/talk-post.sh", text, room],
        capture_output=True, text=True,
    )
    if r.returncode != 0:
        print(r.stderr or r.stdout, file=sys.stderr)
        return False
    print(r.stdout.strip())
    return True

if action == "YES":
    if status == "applied":
        post_confirm(f"Proposal {pid} — already applied (no change).")
        sys.exit(0)
    if status in ("rejected", "deferred"):
        post_confirm(f"Proposal {pid} — cannot apply (status={status}).")
        sys.exit(1)
    prop["status"] = "approved"
    batch_path.write_text(json.dumps(batch, indent=2))
    r = subprocess.run(
        ["bash", f"{script_dir}/skylight-household-apply.sh", "--id", pid],
        capture_output=True, text=True,
    )
    if r.returncode != 0:
        post_confirm(f"Proposal {pid} — apply FAILED: {(r.stderr or r.stdout)[:200]}")
        sys.exit(r.returncode)
    batch = json.loads(batch_path.read_text())
    prop = next(p for p in batch["proposals"] if p["id"] == pid)
    prop["status"] = "applied"
    prop["applied_at"] = datetime.utcnow().isoformat() + "Z"
    batch_path.write_text(json.dumps(batch, indent=2))
    post_confirm(f"Proposal {pid} — applied to Skylight.")
    print(f"P2 applied {pid}")

elif action == "NO":
    if status == "rejected":
        post_confirm(f"Proposal {pid} — already rejected (no Skylight write).")
        print(f"P4 rejected {pid} — idempotent")
        sys.exit(0)
    if status == "applied":
        post_confirm(f"Proposal {pid} — already applied; use rollback if needed.")
        sys.exit(1)
    prop["status"] = "rejected"
    prop["rejected_at"] = datetime.utcnow().isoformat() + "Z"
    batch_path.write_text(json.dumps(batch, indent=2))
    post_confirm(f"Proposal {pid} — rejected (no Skylight write).")
    print(f"P4 rejected {pid} — no API write")

else:
    if status in terminal and status != "edit_pending":
        post_confirm(f"Proposal {pid} — status={status}; edit noted anyway.")
    prop["status"] = "edit_pending"
    prop["edit_text"] = extra
    batch_path.write_text(json.dumps(batch, indent=2))
    snippet = extra[:120] if extra else "(no text)"
    post_confirm(f"Proposal {pid} — edit noted: {snippet}")
    print(f"EDIT {pid}: noted — operator text: {extra!r}")
PY
